#if canImport(AuthenticationServices)
  import AuthenticationServices
  public import Foundation
  import IssueReporting

  /// A presenter that shows the provider page in an `ASWebAuthenticationSession`.
  ///
  /// It is the default presenter on Apple platforms. The client must have a redirect URL with a
  /// scheme, from ``OAuthOptions/redirectTo`` or ``AuthClient/Configuration/redirectToURL``.
  public struct ASWebAuthenticationSessionPresenter: WebAuthPresenter {
    /// Whether the session asks the browser for a private session, with no shared cookies.
    public let prefersEphemeralWebBrowserSession: Bool

    /// Creates a presenter.
    ///
    /// - Parameter prefersEphemeralWebBrowserSession: Set to `true` to ask the browser for a
    ///   private session. The user then signs in again, with no saved cookies.
    public init(prefersEphemeralWebBrowserSession: Bool = false) {
      self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
    }

    /// Opens `url` in an `ASWebAuthenticationSession` and returns the callback URL.
    ///
    /// - Throws: `CancellationError` when the user cancels. An error of kind
    ///   ``AuthError/Kind-swift.struct/oauthFlowFailed`` when `callbackScheme` is `nil`. Else the
    ///   error of the session.
    @MainActor
    public func authenticate(url: URL, callbackScheme: String?) async throws -> URL {
      let callbackScheme = try Self.callbackScheme(callbackScheme)

      return try await withCheckedThrowingContinuation { continuation in
        var presentationAnchor: AnyObject?

        let session = ASWebAuthenticationSession(
          url: url,
          callbackURLScheme: callbackScheme
        ) { url, error in
          if let result = Self.callbackResult(url: url, error: error) {
            continuation.resume(with: result)
          } else {
            reportIssue(Self.sessionContractViolation)
            continuation.resume(
              throwing: AuthError.oauthFlowFailed(Self.sessionContractViolation)
            )
          }

          withExtendedLifetime(presentationAnchor) {}
        }

        #if !os(tvOS)
          session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        #endif
        presentationAnchor = Self.installDefaultPresentationAnchor(on: session)

        session.start()
      }
    }

    /// Pure so the guidance message can be covered without presenting a session.
    static func callbackScheme(_ scheme: String?) throws -> String {
      guard let scheme else {
        throw AuthError.oauthFlowFailed(
          """
          Provide a redirect URL with a scheme, either through the `redirectTo` parameter \
          or globally through `AuthClient.Configuration.redirectToURL`.
          """
        )
      }
      return scheme
    }

    static let sessionContractViolation =
      "ASWebAuthenticationSession returned neither a URL nor an error."

    /// Maps the `(url, error)` pair `ASWebAuthenticationSession` reports onto a result, favouring
    /// the error when it somehow reports both. A cancelled login becomes `CancellationError`, as
    /// ``WebAuthPresenter/authenticate(url:callbackScheme:)`` requires.
    ///
    /// Returns `nil` for the combination it documents as impossible — neither value present —
    /// which the caller turns into ``sessionContractViolation``. The reporting stays with the
    /// caller because driving `reportIssue` from a `@Test` function segfaults under
    /// `xcodebuild test` (SDK-435); keeping it out here is what lets this be tested directly.
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
        guard session.presentationContextProvider == nil else { return nil }
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

  #if !os(tvOS) && !os(watchOS)
    @MainActor
    final class DefaultPresentationContextProvider: NSObject,
      ASWebAuthenticationPresentationContextProviding
    {
      func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
      }
    }
  #endif
#endif
