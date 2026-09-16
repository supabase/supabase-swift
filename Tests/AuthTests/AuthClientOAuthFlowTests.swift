//
//  AuthClientOAuthFlowTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 16/09/26.
//

import Foundation
import Testing

@testable import Auth

#if canImport(AuthenticationServices)
  import AuthenticationServices

  /// Covers the decision logic around `ASWebAuthenticationSession` in
  /// ``AuthClient/signInWithOAuth(provider:redirectTo:scopes:queryParams:configure:)``.
  ///
  /// The session itself can only run in front of a real user, so the method that presents it
  /// stays uncovered by design. These helpers hold everything that decides *what* the session is
  /// told and *how* its answer is interpreted, which is the part worth pinning.
  @Suite
  struct AuthClientOAuthFlowTests {

    // MARK: - Callback scheme resolution

    @Test
    func resolvesTheSchemeFromTheConfiguredURL() throws {
      let scheme = try AuthClient.oauthCallbackScheme(
        configured: URL(string: "myapp://callback")!,
        redirectTo: nil
      )

      #expect(scheme == "myapp")
    }

    @Test
    func resolvesTheSchemeFromThePerCallURL() throws {
      let scheme = try AuthClient.oauthCallbackScheme(
        configured: nil,
        redirectTo: URL(string: "myapp://callback")!
      )

      #expect(scheme == "myapp")
    }

    /// Pins today's precedence, which is **not** the one the authorize URL uses: the base
    /// `signInWithOAuth(…launchFlow:)` overload builds that with `redirectTo ?? configuration
    /// .redirectToURL`, so when both are set with different schemes the session ends up
    /// listening on a scheme the provider never redirects to.
    ///
    /// Recorded as-is rather than fixed here so the behavior change lands as its own
    /// reviewable commit — see SDK-1873, which flips this expectation.
    @Test
    func prefersTheConfiguredURLOverThePerCallOne() throws {
      let scheme = try AuthClient.oauthCallbackScheme(
        configured: URL(string: "configured://callback")!,
        redirectTo: URL(string: "myapp://callback")!
      )

      #expect(scheme == "configured")
    }

    @Test
    func throwsWhenNeitherURLIsProvided() throws {
      let error = #expect(throws: AuthError.self) {
        try AuthClient.oauthCallbackScheme(configured: nil, redirectTo: nil)
      }

      #expect(error?.kind == .oauthFlowFailed)
      // The message has to name both knobs — it is the only guidance a caller gets, and either
      // one fixes the failure.
      #expect(error?.message.contains("redirectTo") == true)
      #expect(error?.message.contains("AuthClient.Configuration.redirectToURL") == true)
    }

    /// A URL can parse without a scheme, and a scheme is exactly what the session needs.
    @Test
    func throwsWhenTheOnlyURLHasNoScheme() throws {
      let withoutScheme = URL(string: "/callback")!
      #expect(withoutScheme.scheme == nil, "precondition: this fixture must have no scheme")

      let error = #expect(throws: AuthError.self) {
        try AuthClient.oauthCallbackScheme(configured: nil, redirectTo: withoutScheme)
      }

      #expect(error?.kind == .oauthFlowFailed)
    }

    // MARK: - Callback result mapping

    @Test
    func mapsAReturnedURLToSuccess() throws {
      let url = URL(string: "myapp://callback?code=abc")!
      let result = try #require(AuthClient.oauthCallbackResult(url: url, error: nil))

      #expect(try result.get() == url)
    }

    @Test
    func mapsAReportedErrorToFailure() throws {
      let reported = ASWebAuthenticationSessionError(.canceledLogin)
      let result = try #require(AuthClient.oauthCallbackResult(url: nil, error: reported))

      let failure = #expect(throws: ASWebAuthenticationSessionError.self) { try result.get() }
      #expect(failure?.code == .canceledLogin)
    }

    /// The session should never report both. If it does, the error is the safer of the two to
    /// believe — a URL alongside an error is not a callback the flow can trust.
    @Test
    func prefersTheErrorWhenBothAreReported() throws {
      let result = try #require(
        AuthClient.oauthCallbackResult(
          url: URL(string: "myapp://callback")!,
          error: ASWebAuthenticationSessionError(.canceledLogin)
        )
      )

      #expect(throws: ASWebAuthenticationSessionError.self) { try result.get() }
    }

    /// `nil` is how the mapping reports a broken session contract. The caller turns it into
    /// ``AuthClient/oauthSessionContractViolation`` and a `reportIssue`, which is kept out of
    /// the pure helper so these tests never drive it (`reportIssue` in a `@Test` segfaults under
    /// `xcodebuild test`, SDK-435).
    @Test
    func reportsNoResultWhenTheSessionReturnsNeither() {
      #expect(AuthClient.oauthCallbackResult(url: nil, error: nil) == nil)
    }

    // MARK: - Presentation context

    #if !os(tvOS) && !os(watchOS)
      @Test
      @MainActor
      func installsADefaultPresentationContextWhenConfigureLeftItUnset() throws {
        let session = makeSession()

        let installed = AuthClient.installDefaultPresentationContextIfNeeded(on: session)

        #expect(installed != nil)
        // Returned so the caller can hold it: the session's own reference is weak, and an
        // anchor that deallocates before `start()` leaves the session unable to present.
        #expect(session.presentationContextProvider === installed)
      }

      /// A `configure` closure that supplied its own anchor must keep it.
      @Test
      @MainActor
      func leavesAPresentationContextSuppliedByConfigureAlone() throws {
        let session = makeSession()
        let supplied = DefaultPresentationContextProvider()
        session.presentationContextProvider = supplied

        let installed = AuthClient.installDefaultPresentationContextIfNeeded(on: session)

        #expect(installed == nil)
        #expect(session.presentationContextProvider === supplied)
      }

      /// Built but never started — `start()` is what needs a real user in front of it.
      private func makeSession() -> ASWebAuthenticationSession {
        ASWebAuthenticationSession(
          url: URL(string: "https://example.supabase.co/auth/v1/authorize")!,
          callbackURLScheme: "myapp"
        ) { _, _ in }
      }
    #endif
  }
#endif
