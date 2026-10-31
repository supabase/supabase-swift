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
      guard let callbackScheme else {
        throw AuthError.oauthFlowFailed(
          """
          Provide a redirect URL with a scheme, either through the `redirectTo` parameter \
          or globally through `AuthClient.Configuration.redirectToURL`.
          """
        )
      }

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
