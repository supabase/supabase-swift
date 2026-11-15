// SwiftPM turns off cross-import overlays, so import the overlay that declares
// `WebAuthenticationSession` by name instead of relying on `AuthenticationServices` + `SwiftUI`.
#if canImport(_AuthenticationServices_SwiftUI)
  import AuthenticationServices
  public import Foundation
  public import _AuthenticationServices_SwiftUI

  /// A presenter that shows the provider page with SwiftUI's `WebAuthenticationSession`.
  ///
  /// Use it inside a SwiftUI view. Read the session from the environment and pass it to
  /// ``WebAuthPresenter/webAuthenticationSession(_:prefersEphemeralWebBrowserSession:)``:
  ///
  /// ```swift
  /// struct SignInView: View {
  ///   @Environment(\.webAuthenticationSession) private var webAuthenticationSession
  ///
  ///   var body: some View {
  ///     Button("Sign in with GitHub") {
  ///       Task {
  ///         try await supabase.auth.signInWithOAuth(
  ///           .github,
  ///           presenter: .webAuthenticationSession(webAuthenticationSession)
  ///         )
  ///       }
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// It works like ``ASWebAuthenticationSessionPresenter``, but SwiftUI picks the window that shows
  /// the page. The client must have a redirect URL, from ``OAuthOptions/redirectTo`` or
  /// ``AuthClient/Configuration/redirectTo``. When the user closes the page, the call throws
  /// `CancellationError`. Only one page can be open at a time, across both presenters: a second
  /// call while one is open throws an error of kind ``AuthError/Kind-swift.struct/oauthFlowFailed``.
  /// An HTTPS redirect URL is a universal link: the presenter listens for it
  /// on iOS 17.4, macOS 14.4, tvOS 17.4, visionOS 1.1, and watchOS 10.4 and later. See
  /// ``ASWebAuthenticationSessionPresenter`` for how to set one up.
  @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
  public struct WebAuthenticationSessionPresenter: WebAuthPresenter {
    /// Whether the session asks the browser for a private session, with no shared cookies.
    public let prefersEphemeralWebBrowserSession: Bool

    private let httpsCallbacksAvailable: Bool
    private let activeSession: ActiveWebAuthSession
    private let openPage: OpenPage

    /// Opens the page and returns the callback URL. The real session needs a window and a user, so
    /// tests pass a fake.
    typealias OpenPage =
      @MainActor @Sendable (
        _ url: URL, _ callback: WebAuthCallback, _ prefersEphemeralWebBrowserSession: Bool
      ) async throws -> URL

    /// Creates a presenter that shows the page with `session`.
    ///
    /// - Parameters:
    ///   - session: The `webAuthenticationSession` value from the SwiftUI environment.
    ///   - prefersEphemeralWebBrowserSession: Set to `true` to ask the browser for a private
    ///     session. The user then signs in again, with no saved cookies.
    public init(
      _ session: WebAuthenticationSession,
      prefersEphemeralWebBrowserSession: Bool = false
    ) {
      self.init(
        prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession,
        httpsCallbacksAvailable: ASWebAuthenticationSessionPresenter.systemSupportsHTTPSCallbacks,
        activeSession: .shared,
        openPage: { url, callback, prefersEphemeral in
          try await Self.authenticate(
            session, url: url, callback: callback, prefersEphemeral: prefersEphemeral)
        }
      )
    }

    init(
      prefersEphemeralWebBrowserSession: Bool,
      httpsCallbacksAvailable: Bool,
      activeSession: ActiveWebAuthSession,
      openPage: @escaping OpenPage
    ) {
      self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
      self.httpsCallbacksAvailable = httpsCallbacksAvailable
      self.activeSession = activeSession
      self.openPage = openPage
    }

    /// Opens `url` with the SwiftUI session and returns the callback URL.
    ///
    /// - Throws: `CancellationError` when the user closes the page, or when the task is cancelled
    ///   before the page opens. A cancel while the page is open goes to SwiftUI's session. An
    ///   error of kind ``AuthError/Kind-swift.struct/oauthFlowFailed`` when `redirectURL` is `nil`
    ///   or has no scheme, or when another page is open. Else the error of the session.
    @MainActor
    public func authenticate(url: URL, redirectURL: URL?) async throws -> URL {
      try await authenticate(
        url: url,
        callback: redirectURL.flatMap {
          ASWebAuthenticationSessionPresenter.callback(
            for: $0, httpsCallbacksAvailable: httpsCallbacksAvailable)
        }
      )
    }

    /// Opens `url` with the SwiftUI session and returns the callback URL.
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
      let callback = try WebAuthCallback.required(callback)
      try Task.checkCancellation()
      let lease = try activeSession.beginOrThrow()
      defer { lease.release() }
      do {
        return try await openPage(url, callback, prefersEphemeralWebBrowserSession)
      } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
        throw CancellationError()
      }
    }

    @MainActor
    private static func authenticate(
      _ session: WebAuthenticationSession,
      url: URL,
      callback: WebAuthCallback,
      prefersEphemeral: Bool
    ) async throws -> URL {
      let browserSession: WebAuthenticationSession.BrowserSession? =
        prefersEphemeral ? .ephemeral : nil
      switch callback {
      case .scheme(let scheme):
        return try await session.authenticate(
          using: url, callbackURLScheme: scheme, preferredBrowserSession: browserSession)
      case .https(let host, let path):
        if #available(iOS 17.4, macOS 14.4, tvOS 17.4, visionOS 1.1, watchOS 10.4, *) {
          return try await session.authenticate(
            using: url,
            callback: .https(host: host, path: path),
            preferredBrowserSession: browserSession,
            additionalHeaderFields: [:]
          )
        }
        return try await session.authenticate(
          using: url, callbackURLScheme: "https", preferredBrowserSession: browserSession)
      }
    }
  }

  @available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9.4, *)
  extension WebAuthPresenter where Self == WebAuthenticationSessionPresenter {
    /// A ``WebAuthenticationSessionPresenter`` that shows the page with `session`.
    ///
    /// - Parameters:
    ///   - session: The `webAuthenticationSession` value from the SwiftUI environment.
    ///   - prefersEphemeralWebBrowserSession: Set to `true` to ask the browser for a private
    ///     session.
    /// - Returns: The presenter.
    public static func webAuthenticationSession(
      _ session: WebAuthenticationSession,
      prefersEphemeralWebBrowserSession: Bool = false
    ) -> Self {
      WebAuthenticationSessionPresenter(
        session, prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession)
    }
  }
#endif
