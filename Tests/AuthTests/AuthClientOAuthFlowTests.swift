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

  @Suite
  struct AuthClientOAuthFlowTests {

    @Test
    func fallsBackToTheConfiguredURLWhenNoPerCallOneIsGiven() {
      let configured = URL(string: "configured://callback")!

      #expect(
        AuthClient.oauthRedirectURL(redirectTo: nil, configured: configured) == configured
      )
    }

    @Test
    func usesThePerCallURLWhenNoConfiguredOneIsSet() {
      let perCall = URL(string: "myapp://callback")!

      #expect(AuthClient.oauthRedirectURL(redirectTo: perCall, configured: nil) == perCall)
    }

    @Test
    func prefersThePerCallURLOverTheConfiguredOne() {
      let perCall = URL(string: "myapp://callback")!

      #expect(
        AuthClient.oauthRedirectURL(
          redirectTo: perCall,
          configured: URL(string: "configured://callback")!
        ) == perCall
      )
    }

    @Test
    func resolvesToNothingWhenNeitherURLIsSet() {
      #expect(AuthClient.oauthRedirectURL(redirectTo: nil, configured: nil) == nil)
    }

    @Test(
      arguments: [
        (perCall: "myapp://callback", configured: "configured://callback"),
        (perCall: "myapp://callback", configured: nil),
        (perCall: nil, configured: "configured://callback"),
      ] as [(perCall: String?, configured: String?)]
    )
    func theCallbackSchemeAlwaysMatchesTheResolvedRedirect(
      perCall: String?,
      configured: String?
    ) throws {
      let resolved = AuthClient.oauthRedirectURL(
        redirectTo: perCall.map { URL(string: $0)! },
        configured: configured.map { URL(string: $0)! }
      )

      let scheme = try ASWebAuthenticationSessionPresenter.callbackScheme(resolved?.scheme)

      #expect(scheme == resolved?.scheme)
    }

    @Test
    func throwsWhenNeitherURLIsProvided() throws {
      let error = #expect(throws: AuthError.self) {
        try ASWebAuthenticationSessionPresenter.callbackScheme(nil)
      }

      #expect(error?.kind == .oauthFlowFailed)
      #expect(error?.message.contains("redirectTo") == true)
      #expect(error?.message.contains("AuthClient.Configuration.redirectToURL") == true)
    }

    @Test
    func throwsWhenTheOnlyURLHasNoScheme() throws {
      let withoutScheme = URL(string: "/callback")!
      #expect(withoutScheme.scheme == nil, "precondition: this fixture must have no scheme")

      let error = #expect(throws: AuthError.self) {
        try ASWebAuthenticationSessionPresenter.callbackScheme(withoutScheme.scheme)
      }

      #expect(error?.kind == .oauthFlowFailed)
    }

    @Test
    @MainActor
    func aNilCallbackSchemeThrowsTheGuidance() async throws {
      let presenter = ASWebAuthenticationSessionPresenter()

      let error = await #expect(throws: AuthError.self) {
        try await presenter.authenticate(
          url: URL(string: "https://example.supabase.co/auth/v1/authorize")!,
          callbackScheme: nil
        )
      }

      #expect(error?.kind == .oauthFlowFailed)
      #expect(error?.message.contains("redirectTo") == true)
      #expect(error?.message.contains("AuthClient.Configuration.redirectToURL") == true)
    }

    @Test
    func mapsAReturnedURLToSuccess() throws {
      let url = URL(string: "myapp://callback?code=abc")!
      let result = try #require(
        ASWebAuthenticationSessionPresenter.callbackResult(url: url, error: nil))

      #expect(try result.get() == url)
    }

    @Test
    func mapsAReportedErrorToFailure() throws {
      let reported = ASWebAuthenticationSessionError(.canceledLogin)
      let result = try #require(
        ASWebAuthenticationSessionPresenter.callbackResult(url: nil, error: reported))

      let failure = #expect(throws: ASWebAuthenticationSessionError.self) { try result.get() }
      #expect(failure?.code == .canceledLogin)
    }

    @Test
    func prefersTheErrorWhenBothAreReported() throws {
      let result = try #require(
        ASWebAuthenticationSessionPresenter.callbackResult(
          url: URL(string: "myapp://callback")!,
          error: ASWebAuthenticationSessionError(.canceledLogin)
        )
      )

      #expect(throws: ASWebAuthenticationSessionError.self) { try result.get() }
    }

    @Test
    func reportsNoResultWhenTheSessionReturnsNeither() {
      #expect(ASWebAuthenticationSessionPresenter.callbackResult(url: nil, error: nil) == nil)
    }

    #if !os(tvOS) && !os(watchOS)
      @Test
      @MainActor
      func installsADefaultPresentationContextWhenConfigureLeftItUnset() throws {
        let session = makeSession()

        let installed = ASWebAuthenticationSessionPresenter.installDefaultPresentationAnchor(
          on: session)

        #expect(installed != nil)
        // Returned so the caller can hold it: the session's own reference is weak, and an
        // anchor that deallocates before `start()` leaves the session unable to present.
        #expect(session.presentationContextProvider === installed)
      }

      @Test
      @MainActor
      func leavesAPresentationContextSuppliedByConfigureAlone() throws {
        let session = makeSession()
        let supplied = DefaultPresentationContextProvider()
        session.presentationContextProvider = supplied

        let installed = ASWebAuthenticationSessionPresenter.installDefaultPresentationAnchor(
          on: session)

        #expect(installed == nil)
        #expect(session.presentationContextProvider === supplied)
      }

      private func makeSession() -> ASWebAuthenticationSession {
        ASWebAuthenticationSession(
          url: URL(string: "https://example.supabase.co/auth/v1/authorize")!,
          callbackURLScheme: "myapp"
        ) { _, _ in }
      }
    #endif
  }
#endif
