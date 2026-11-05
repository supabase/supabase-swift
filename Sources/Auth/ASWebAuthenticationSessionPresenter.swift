#if canImport(AuthenticationServices)
  import AuthenticationServices
  import ConcurrencyExtras
  public import Foundation
  import IssueReporting

  /// A presenter that shows the provider page in an `ASWebAuthenticationSession`.
  ///
  /// It is the default presenter on Apple platforms. The client must have a redirect URL, from
  /// ``OAuthOptions/redirectTo`` or ``AuthClient/Configuration/redirectTo``.
  ///
  /// Cancelling the task that awaits ``authenticate(url:redirectURL:)`` closes the page and throws
  /// `CancellationError`. So does the user closing it. On tvOS, the system cannot close the page
  /// for the app: the call throws at once, and the page stays until the user dismisses it. A new page
  /// cannot open before then. Only
  /// one page can be open at a time: a second call while one is open throws an error of kind
  /// ``AuthError/Kind-swift.struct/oauthFlowFailed``.
  ///
  /// ## Choose the redirect URL
  ///
  /// A redirect URL with a custom scheme, like `myapp://callback`, works on every version.
  ///
  /// An HTTPS redirect URL, like `https://example.com/auth/callback`, is a universal link. The
  /// presenter listens for it on iOS 17.4, macOS 14.4, tvOS 17.4, visionOS 1.1, and watchOS 10.4
  /// and later. Before those versions, it listens for the scheme `https`, which the system does
  /// not accept. To use a universal link, add the `webcredentials:` associated domain for the
  /// host of the redirect URL to your app, and host the matching `apple-app-site-association`
  /// file there.
  ///
  /// ## Platform support
  ///
  /// `ASWebAuthenticationSession` exists on tvOS 16 and watchOS 6.2. Both are available, but test
  /// the flow on a device before you advertise it. tvOS has no ephemeral session, so
  /// ``prefersEphemeralWebBrowserSession`` has no effect there.
  public struct ASWebAuthenticationSessionPresenter: WebAuthPresenter {
    /// Whether the session asks the browser for a private session, with no shared cookies.
    public let prefersEphemeralWebBrowserSession: Bool

    private let httpsCallbacksAvailable: Bool
    private let activeSession: ActiveWebAuthSession
    private let makeSession: WebAuthSessionFactory

    /// Creates a presenter.
    ///
    /// - Parameter prefersEphemeralWebBrowserSession: Set to `true` to ask the browser for a
    ///   private session. The user then signs in again, with no saved cookies.
    public init(prefersEphemeralWebBrowserSession: Bool = false) {
      self.init(
        prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession,
        httpsCallbacksAvailable: Self.systemSupportsHTTPSCallbacks,
        activeSession: .shared,
        makeSession: SystemWebAuthSession.init
      )
    }

    init(
      prefersEphemeralWebBrowserSession: Bool,
      httpsCallbacksAvailable: Bool,
      activeSession: ActiveWebAuthSession,
      makeSession: @escaping WebAuthSessionFactory
    ) {
      self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
      self.httpsCallbacksAvailable = httpsCallbacksAvailable
      self.activeSession = activeSession
      self.makeSession = makeSession
    }

    /// Opens `url` in an `ASWebAuthenticationSession` and returns the callback URL.
    ///
    /// - Throws: `CancellationError` when the user cancels or the task is cancelled. An error of
    ///   kind ``AuthError/Kind-swift.struct/oauthFlowFailed`` when `redirectURL` is `nil` or has
    ///   no scheme, or when another page is open. Else the error of the session.
    @MainActor
    public func authenticate(url: URL, redirectURL: URL?) async throws -> URL {
      try await authenticate(
        url: url,
        callback: redirectURL.flatMap {
          Self.callback(for: $0, httpsCallbacksAvailable: httpsCallbacksAvailable)
        }
      )
    }

    /// Opens `url` in an `ASWebAuthenticationSession` and returns the callback URL.
    ///
    /// This method listens for `callbackScheme`. To listen for a universal link, call
    /// ``authenticate(url:redirectURL:)``.
    ///
    /// - Throws: The errors of ``authenticate(url:redirectURL:)``.
    @MainActor
    public func authenticate(url: URL, callbackScheme: String?) async throws -> URL {
      try await authenticate(url: url, callback: callbackScheme.map(WebAuthCallback.scheme))
    }

    @MainActor
    private func authenticate(url: URL, callback: WebAuthCallback?) async throws -> URL {
      guard let callback else {
        throw AuthError.oauthFlowFailed(
          """
          Provide a redirect URL with a scheme, either through the `redirectTo` parameter \
          or globally through `AuthClient.Configuration.redirectTo`.
          """
        )
      }
      try Task.checkCancellation()
      guard let lease = activeSession.begin() else {
        throw AuthError.oauthFlowFailed(
          "Another sign-in page is already open. Wait for it to close, then try again."
        )
      }

      let handle = WebAuthSessionHandle()

      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let pending = PendingResult(continuation)
          let session = makeSession(url, callback, prefersEphemeralWebBrowserSession) {
            url, error in
            lease.release()
            if let result = Self.callbackResult(url: url, error: error) {
              pending.resume(with: result)
            } else {
              reportIssue(Self.sessionContractViolation)
              pending.resume(
                with: .failure(AuthError.oauthFlowFailed(Self.sessionContractViolation)))
            }
          }
          handle.hold(session, pending: pending, lease: lease)
          if !session.start() {
            lease.release()
            pending.resume(
              with: .failure(
                AuthError.oauthFlowFailed("The system could not open the sign-in page.")))
          }
        }
      } onCancel: {
        Task { @MainActor in handle.cancel() }
      }
    }

    static var systemSupportsHTTPSCallbacks: Bool {
      if #available(iOS 17.4, macOS 14.4, tvOS 17.4, visionOS 1.1, watchOS 10.4, *) {
        true
      } else {
        false
      }
    }

    /// The callback to listen for: the host and path of an HTTPS `redirectURL` where the system
    /// supports it, else the scheme. `nil` when `redirectURL` has no scheme.
    static func callback(for redirectURL: URL, httpsCallbacksAvailable: Bool) -> WebAuthCallback? {
      guard let scheme = redirectURL.scheme else { return nil }
      if httpsCallbacksAvailable, scheme.lowercased() == "https", let host = redirectURL.host {
        let path = redirectURL.path(percentEncoded: false)
        return .https(host: host, path: path.isEmpty ? "/" : path)
      }
      return .scheme(scheme)
    }

    static let sessionContractViolation =
      "ASWebAuthenticationSession returned neither a URL nor an error."

    /// Maps the session's `(url, error)` onto a result, preferring the error. A cancelled login
    /// becomes `CancellationError`. Returns `nil` when neither is set; the caller reports that,
    /// because `reportIssue` in a `@Test` crashes under `xcodebuild test`.
    static func callbackResult(url: URL?, error: (any Error)?) -> Result<URL, any Error>? {
      if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
        return .failure(CancellationError())
      }
      if let error { return .failure(error) }
      if let url { return .success(url) }
      return nil
    }

    /// `ASWebAuthenticationSession.presentationContextProvider` is weak. Hold the returned
    /// provider until the session completes.
    @MainActor
    static func installDefaultPresentationAnchor(
      on session: ASWebAuthenticationSession
    ) -> AnyObject? {
      #if os(tvOS) || os(watchOS)
        return nil
      #else
        let provider = DefaultPresentationContextProvider()
        session.presentationContextProvider = provider
        return provider
      #endif
    }
  }

  extension WebAuthPresenter where Self == ASWebAuthenticationSessionPresenter {
    /// An ``ASWebAuthenticationSessionPresenter`` that shares cookies with the browser.
    public static var `default`: Self { ASWebAuthenticationSessionPresenter() }
  }

  /// What a session listens for to know the sign-in is done.
  enum WebAuthCallback: Equatable, Sendable {
    case scheme(String)
    case https(host: String, path: String)
  }

  /// The part of `ASWebAuthenticationSession` that the presenter uses. A fake stands in for it
  /// in tests, because the system session needs a window and a user.
  @MainActor
  protocol WebAuthSession: AnyObject {
    /// `false` when `cancel()` leaves the page open, as on tvOS.
    var dismissesOnCancel: Bool { get }
    /// Returns `false` when the session cannot start.
    func start() -> Bool
    func cancel()
  }

  /// Makes a session that calls `completion` once, when the page closes or redirects.
  typealias WebAuthSessionFactory =
    @MainActor @Sendable (
      _ url: URL,
      _ callback: WebAuthCallback,
      _ prefersEphemeralWebBrowserSession: Bool,
      _ completion: @escaping @Sendable (URL?, (any Error)?) -> Void
    ) -> any WebAuthSession

  /// Resumes the awaiting call once. The system does not promise a completion call after
  /// `cancel()`, and it may still call after the presenter gave up, so the first result wins.
  final class PendingResult: Sendable {
    private let continuation: LockIsolated<CheckedContinuation<URL, any Error>?>

    init(_ continuation: CheckedContinuation<URL, any Error>) {
      self.continuation = LockIsolated(continuation)
    }

    func resume(with result: Result<URL, any Error>) {
      let taken = continuation.withValue { continuation in
        defer { continuation = nil }
        return continuation
      }
      taken?.resume(with: result)
    }
  }

  /// Lets the cancellation handler, which runs anywhere, reach the session on the main actor. It
  /// also holds the session until `authenticate` returns.
  @MainActor
  final class WebAuthSessionHandle {
    private var session: (any WebAuthSession)?
    private var pending: PendingResult?
    private var lease: ActiveWebAuthSession.Lease?

    func hold(
      _ session: any WebAuthSession, pending: PendingResult, lease: ActiveWebAuthSession.Lease
    ) {
      self.session = session
      self.pending = pending
      self.lease = lease
    }

    /// Stops the wait. The slot for the page frees now only if `cancel()` closes the page. Else it
    /// frees when the system reports that the user closed it.
    func cancel() {
      session?.cancel()
      if session?.dismissesOnCancel == true { lease?.release() }
      pending?.resume(with: .failure(CancellationError()))
    }
  }

  /// Tracks whether a page is open, so a second one does not start on top of it.
  final class ActiveWebAuthSession: Sendable {
    static let shared = ActiveWebAuthSession()

    private let isActive = LockIsolated(false)

    /// Returns `nil` when a page is already open.
    func begin() -> Lease? {
      isActive.withValue { isActive -> Lease? in
        guard !isActive else { return nil }
        isActive = true
        return Lease(owner: self)
      }
    }

    /// The right to the slot. Releasing twice is safe, so a late call cannot free the slot of a
    /// later page.
    final class Lease: Sendable {
      private let owner: ActiveWebAuthSession
      private let isReleased = LockIsolated(false)

      fileprivate init(owner: ActiveWebAuthSession) { self.owner = owner }

      func release() {
        let isFirstRelease = isReleased.withValue { isReleased -> Bool in
          defer { isReleased = true }
          return !isReleased
        }
        if isFirstRelease { owner.isActive.setValue(false) }
      }
    }
  }

  /// The real `ASWebAuthenticationSession`, with the presentation anchor it needs.
  @MainActor
  final class SystemWebAuthSession: WebAuthSession {
    private let session: ASWebAuthenticationSession
    /// `ASWebAuthenticationSession.presentationContextProvider` is weak, so the session holds it.
    private let presentationAnchor: AnyObject?

    init(
      url: URL,
      callback: WebAuthCallback,
      prefersEphemeralWebBrowserSession: Bool,
      completion: @escaping @Sendable (URL?, (any Error)?) -> Void
    ) {
      switch callback {
      case .scheme(let scheme):
        session = ASWebAuthenticationSession(
          url: url, callbackURLScheme: scheme, completionHandler: completion)
      case .https(let host, let path):
        if #available(iOS 17.4, macOS 14.4, tvOS 17.4, visionOS 1.1, watchOS 10.4, *) {
          session = ASWebAuthenticationSession(
            url: url, callback: .https(host: host, path: path), completionHandler: completion)
        } else {
          session = ASWebAuthenticationSession(
            url: url, callbackURLScheme: "https", completionHandler: completion)
        }
      }

      #if !os(tvOS)
        session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
      #endif
      presentationAnchor = ASWebAuthenticationSessionPresenter.installDefaultPresentationAnchor(
        on: session)
    }

    #if os(tvOS)
      let dismissesOnCancel = false
    #else
      let dismissesOnCancel = true
    #endif

    func start() -> Bool { session.start() }

    /// `cancel()` does not exist on tvOS. There, the page stays until the user closes it.
    func cancel() {
      #if !os(tvOS)
        session.cancel()
      #endif
    }
  }

  #if !os(tvOS) && !os(watchOS)
    @MainActor
    final class DefaultPresentationContextProvider: NSObject,
      ASWebAuthenticationPresentationContextProviding
    {
      func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        AuthPlatform.defaultPresentationAnchor()
      }
    }
  #endif
#endif
