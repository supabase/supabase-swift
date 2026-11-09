//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Helpers
import InlineSnapshotTesting
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

let apiKey =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

@Suite
struct AuthClientTests {
  let transport = RecordingTransport()
  let storage = InMemoryTestStorage()

  @Test
  func eventsStartWithInitialSession() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let change = await sut.events().first { _ in true }

    expectNoDifference(change, AuthChange(event: .initialSession, status: .signedIn(.valid)))
    expectNoDifference(sut.status, .signedIn(.valid))
  }

  @Test
  func eventsKeepAChangeAppliedBeforeTheFirstRead() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let events = sut.events()
    try await sut.dependencies.sessionStore.commit(
      .signedOut(.userInitiated, event: .signedOut))
    let changes = await events.prefix(2).collect()

    expectNoDifference(changes.map(\.event), [.initialSession, .signedOut])
    expectNoDifference(changes.last?.signOutReason, .userInitiated)
    expectNoDifference(sut.status, .signedOut(.userInitiated))
  }

  @Test
  func eventsFinishWhenTheClientIsReleased() async throws {
    var sut: AuthClient? = makeSUT()
    await sut?.initialization()
    let events = try #require(sut).events()

    sut = nil
    let changes = try await withTimeout(.seconds(5)) { await events.collect() }

    expectNoDifference(
      changes, [AuthChange(event: .initialSession, status: .signedOut(.sessionMissing))])
  }

  @Test
  func eventsReleaseTheSubscriberWhenCancelledBeforeTheFirstRead() async throws {
    let sut = makeSUT()
    let store = sut.dependencies.sessionStore
    let subscribersBefore = store.subscriberCount

    let stream = sut.events()

    expectNoDifference(store.subscriberCount, subscribersBefore + 1)

    let consumer = Task {
      for await _ in stream {}
    }
    consumer.cancel()

    await consumer.value

    expectNoDifference(store.subscriberCount, subscribersBefore)
  }

  @Test
  func globalSignOutKeepsASessionSignedInWhileLoggingOut() async throws {
    let sut = makeSUT()

    var nextSession = Session.valid
    nextSession.accessToken = "next-access-token"
    nextSession.refreshToken = "next-refresh-token"

    transport.stub(.post, "logout") { [nextSession] _, _ in
      try await sut.seedSession(nextSession)
      return noContent
    }

    try await sut.seedSession(.valid)

    try await sut.signOut(scope: .global)

    expectNoDifference(sut.currentSession, nextSession)
  }

  @Test
  func signInAnonymously() async throws {
    let session = Session(fromMockNamed: "anonymous-sign-in-response").received(at: Self.now)

    transport.stub(.post, "signup", data: MockData.anonymousSignInResponse) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 2" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{}" \
      	"http://localhost:54321/auth/v1/signup"
      """#
    }

    let sut = makeSUT()

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.signInAnonymously() },
      expectedEvents: [.initialSession, .signedIn],
      expectedSessions: [nil, session]
    )

    expectNoDifference(sut.currentSession, session)
    expectNoDifference(sut.currentUser, session.user)
  }

  @Test
  func oauthSignInThroughHandleRedirect() async throws {
    transport.stub(.post, "token", query: ["grant_type": "pkce"], data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 126" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"auth_code\":\"12345\",\"code_verifier\":\"nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA\"}" \
      	"http://localhost:54321/auth/v1/token?grant_type=pkce"
      """#
    }

    let sut = makeSUT()

    let changes = sut.events()

    _ = try await sut.oauthSignInURL(
      .google, options: OAuthOptions(redirectTo: URL(string: "supabase://auth-callback")))
    try await sut.handleRedirect(URL(string: "supabase://auth-callback?code=12345")!)

    let events = await changes.prefix(2).collect().map(\.event)

    expectNoDifference(events, [.initialSession, .signedIn])
  }

  @Test
  func concurrentPKCEFlowsKeepIndependentVerifiers() async throws {
    let sut = makeSUT()
    try await sut.seedSession(.valid)

    transport.stub(
      .get, "user/identities/authorize",
      data: Data(#"{"url": "https://github.com/login/oauth/authorize"}"#.utf8))

    let flowA = try await sut.linkIdentityURL(.github).id

    let flowB = try await sut.linkIdentityURL(.google).id

    #expect(flowA != flowB)

    transport.stub(.post, "token", query: ["grant_type": "pkce"], data: MockData.session)

    _ = try await sut.exchangeCodeForSession("code-a", flowID: flowA)

    #expect(try await sut.dependencies.flowStore.flow(id: flowA) == nil)
    #expect(try await sut.dependencies.flowStore.flow(id: flowB) != nil)
  }

  @Test
  func linkIdentityURL() async throws {
    let url =
      "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
    let sut = makeSUT()

    transport.stub(
      .get, "user/identities/authorize",
      data: Data(
        """
        {
          "url": "\(url)"
        }
        """.utf8)
    ) {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user/identities/authorize?code_challenge=hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY&code_challenge_method=s256&provider=github&skip_http_redirect=true"
      """#
    }

    try await sut.seedSession(.valid)

    let flow = try await sut.linkIdentityURL(.github)

    expectNoDifference(flow.url, URL(string: url)!)
    #expect(try await sut.dependencies.flowStore.flow(id: flow.id) != nil)
  }

  @Test
  func linkIdentityIDTokenEmitsUserUpdated() async throws {
    transport.stub(.post, "token", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 166" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"access_token\":\"access-token\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"id_token\":\"id-token\",\"link_identity\":true,\"nonce\":\"nonce\",\"provider\":\"apple\"}" \
      	"http://localhost:54321/auth/v1/token?grant_type=id_token"
      """#
    }

    let sut = makeSUT()

    try await sut.seedSession(.valid)

    let updatedSession = try await assertAuthStateChanges(
      sut: sut,
      action: {
        try await sut.linkIdentity(
          idToken: IDTokenCredentials(
            provider: .apple,
            idToken: "id-token",
            nonce: "nonce",
            accessToken: "access-token",
            captchaToken: "captcha-token"
          )
        )
      },
      expectedEvents: [.initialSession, .userUpdated]
    )

    expectNoDifference(sut.currentSession, updatedSession)
  }

  @Test
  func adminListUsers() async throws {
    transport.stub(.get, "admin/users") { _, _ in
      let response = HTTPResponse(
        status: .ok,
        headerFields: [
          .init("X-Total-Count")!: "669",
          .init("Link")!:
            "</admin/users?page=2&per_page=>; rel=\"next\", </admin/users?page=14&per_page=>; rel=\"last\"",
        ])
      return (response, MockData.listUsersResponse)
    }

    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)

    let response = try await sut.listUsers()
    expectNoDifference(response.total, 669)
    expectNoDifference(response.nextPage, 2)
    expectNoDifference(response.lastPage, 14)
    try transport.assertFirstRequestSnapshot(.get, "admin/users") {
      #"""
      curl \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/admin/users"
      """#
    }
  }

  @Test
  func adminListUsers_noNextPage() async throws {
    transport.stub(.get, "admin/users") { _, _ in
      let response = HTTPResponse(
        status: .ok,
        headerFields: [
          .init("X-Total-Count")!: "669",
          .init("Link")!: "</admin/users?page=14&per_page=>; rel=\"last\"",
        ])
      return (response, MockData.listUsersResponse)
    }

    let sut = AuthAdminClient.testing(secretKey: apiKey, http: transport)

    let response = try await sut.listUsers()
    expectNoDifference(response.total, 669)
    #expect(response.nextPage == nil)
    expectNoDifference(response.lastPage, 14)
    try transport.assertFirstRequestSnapshot(.get, "admin/users") {
      #"""
      curl \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/admin/users"
      """#
    }
  }

  @Test
  func signUpWithEmailAndPassword() async throws {
    transport.stub(.post, "signup", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 238" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"data\":{\"custom_key\":\"custom_value\"},\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"password\":\"the.pass\"}" \
      	"http://localhost:54321/auth/v1/signup?redirect_to=https://supabase.com"
      """#
    }

    let sut = makeSUT()

    _ = try await sut.signUp(
      email: "example@mail.com",
      password: "the.pass",
      options: SignUpOptions(
        userMetadata: ["custom_key": .string("custom_value")],
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "dummy-captcha"
      )
    )
  }

  @Test
  func signUpWithPhoneAndPassword() async throws {
    transport.stub(.post, "signup", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 159" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"channel\":\"sms\",\"data\":{\"custom_key\":\"custom_value\"},\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"password\":\"the.pass\",\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/signup"
      """#
    }

    let sut = makeSUT()

    _ = try await sut.signUp(
      phone: "+1 202-918-2132",
      password: "the.pass",
      options: SignUpOptions(
        userMetadata: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
      )
    )
  }

  @Test
  func signUpWhenConfirmationRequired() async throws {
    transport.stub(.post, "signup", data: MockData.signUpConfirmationRequired)

    let sut = makeSUT()

    let result = try await sut.signUp(
      email: "jane@example.com",
      password: "the.pass"
    )

    guard case .confirmationRequired(let user) = result else {
      Issue.record("Expected .confirmationRequired, got \(result)")
      return
    }
    #expect(user.email == "jane@example.com")
    #expect(sut.currentSession == nil)
  }

  @Test
  func signUpWhenSignedInCommitsTheSession() async throws {
    transport.stub(.post, "signup", data: MockData.session)

    let sut = makeSUT()

    let result = try await sut.signUp(email: "jane@example.com", password: "the.pass")

    guard case .signedIn(let session) = result else {
      Issue.record("Expected .signedIn, got \(result)")
      return
    }
    expectNoDifference(sut.currentSession, session)
  }

  @Test
  func signInWithEmailAndPassword() async throws {
    transport.stub(.post, "token", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 107" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"password\":\"the.pass\"}" \
      	"http://localhost:54321/auth/v1/token?grant_type=password"
      """#
    }

    let sut = makeSUT()

    try await sut.signIn(
      email: "example@mail.com",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  @Test
  func signInWithPhoneAndPassword() async throws {
    transport.stub(.post, "token", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 106" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"password\":\"the.pass\",\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/token?grant_type=password"
      """#
    }

    let sut = makeSUT()

    try await sut.signIn(
      phone: "+1 202-918-2132",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  @Test
  func signInWithIdToken() async throws {
    transport.stub(.post, "token", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 167" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"access_token\":\"access-token\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"id_token\":\"id-token\",\"link_identity\":false,\"nonce\":\"nonce\",\"provider\":\"apple\"}" \
      	"http://localhost:54321/auth/v1/token?grant_type=id_token"
      """#
    }

    let sut = makeSUT()

    try await sut.signInWithIDToken(
      IDTokenCredentials(
        provider: .apple,
        idToken: "id-token",
        nonce: "nonce",
        accessToken: "access-token",
        captchaToken: "captcha-token"
      )
    )
  }

  @Test
  func signInWithWeb3Ethereum() async throws {
    transport.stub(.post, "token", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 448" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"chain\":\"ethereum\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"message\":\"example.com wants you to sign in with your Ethereum account:\n0x2c7536E3605D9C16a7a3D7b1898e529396a65c23\n\nURI: https:\/\/example.com\nVersion: 1\nChain ID: 1\nNonce: abc123\nIssued At: 2026-01-01T00:00:00.000Z\",\"signature\":\"0x468cc42ece552183597cbbbd0418a5d3efff707a1021a222ad16e55124327ee670d363a8ee08976b5bd5f7af5e3ac53a4e43983a9ac7f4853a75423fcc387ddc1c\"}" \
      	"http://localhost:54321/auth/v1/token?grant_type=web3"
      """#
    }

    let sut = makeSUT()

    try await sut.signInWithWeb3(
      Web3Credentials(
        chain: .ethereum,
        message:
          "example.com wants you to sign in with your Ethereum account:\n0x2c7536E3605D9C16a7a3D7b1898e529396a65c23\n\nURI: https://example.com\nVersion: 1\nChain ID: 1\nNonce: abc123\nIssued At: 2026-01-01T00:00:00.000Z",
        signature:
          "0x468cc42ece552183597cbbbd0418a5d3efff707a1021a222ad16e55124327ee670d363a8ee08976b5bd5f7af5e3ac53a4e43983a9ac7f4853a75423fcc387ddc1c",
        captchaToken: "captcha-token"
      )
    )
  }

  @Test
  func signInWithWeb3Solana() async throws {
    transport.stub(.post, "token", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 305" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"chain\":\"solana\",\"message\":\"example.com wants you to sign in with your Solana account:\n4Cw1koUQtqybLFem7uqhzMBznMPGARbFS4cjaYbM9RnR\n\nURI: https:\/\/example.com\nVersion: 1\nIssued At: 2026-01-01T00:00:00.000Z\",\"signature\":\"dGVzdC1zaWduYXR1cmUtYnl0ZXMtdGhhdC1hcmUtNjQtYnl0ZXMtbG9uZy1mb3ItdGVzdGluZw==\"}" \
      	"http://localhost:54321/auth/v1/token?grant_type=web3"
      """#
    }

    let sut = makeSUT()

    try await sut.signInWithWeb3(
      Web3Credentials(
        chain: .solana,
        message:
          "example.com wants you to sign in with your Solana account:\n4Cw1koUQtqybLFem7uqhzMBznMPGARbFS4cjaYbM9RnR\n\nURI: https://example.com\nVersion: 1\nIssued At: 2026-01-01T00:00:00.000Z",
        signature: "dGVzdC1zaWduYXR1cmUtYnl0ZXMtdGhhdC1hcmUtNjQtYnl0ZXMtbG9uZy1mb3ItdGVzdGluZw=="
      )
    )
  }

  @Test
  func signInWithWeb3UnsupportedChainError() async throws {
    transport.stub(
      .post, "token", status: .badRequest,
      data: Data(
        """
        {
          "error_code": "web3_unsupported_chain",
          "msg": "Unsupported chain"
        }
        """.utf8)
    )

    let sut = makeSUT()

    do {
      _ = try await sut.signInWithWeb3(
        Web3Credentials(
          chain: "bitcoin",
          message: "irrelevant",
          signature: "irrelevant"
        )
      )
      Issue.record("Expected AuthError.server")
    } catch let error as AuthError {
      #expect(error.kind == .server)
      #expect(error.code == .web3UnsupportedChain)
      #expect(error.response?.status == 400)
    }
  }

  @Test
  func signInWithOTPUsingEmail() async throws {
    transport.stub(.post, "otp") {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 235" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"create_user\":true,\"data\":{\"custom_key\":\"custom_value\"},\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"}}" \
      	"http://localhost:54321/auth/v1/otp?redirect_to=https://supabase.com"
      """#
    }

    let sut = makeSUT()

    try await sut.signInWithOTP(
      email: "example@mail.com",
      options: EmailOTPOptions(
        shouldCreateUser: true,
        userMetadata: ["custom_key": .string("custom_value")],
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "dummy-captcha"
      )
    )
  }

  @Test
  func signInWithOTPUsingPhone() async throws {
    transport.stub(.post, "otp", data: Data(#"{"message_id":"SM123"}"#.utf8)) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 161" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"channel\":\"whatsapp\",\"create_user\":true,\"data\":{\"custom_key\":\"custom_value\"},\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/otp"
      """#
    }

    let sut = makeSUT()

    let messageID = try await sut.signInWithOTP(
      phone: "+1 202-918-2132",
      options: PhoneOTPOptions(
        shouldCreateUser: true,
        userMetadata: ["custom_key": .string("custom_value")],
        channel: .whatsapp,
        captchaToken: "dummy-captcha"
      )
    )

    #expect(messageID == MessageID(rawValue: "SM123"))
  }

  @Test
  func signInWithOTPUsingPhoneWithoutAMessageID() async throws {
    transport.stub(.post, "otp", data: Data("{}".utf8))
    let sut = makeSUT()

    let messageID = try await sut.signInWithOTP(phone: "+1 202-918-2132")

    #expect(messageID == nil)
  }

  @Test
  func oauthSignInURL() async throws {
    let sut = makeSUT()
    let flow = try await sut.oauthSignInURL(
      .github,
      options: OAuthOptions(
        scopes: ["read", "write"],
        redirectTo: URL(string: "https://dummy-url.com/redirect")!,
        queryItems: [URLQueryItem(name: "extra_key", value: "extra_value")]
      )
    )
    expectNoDifference(
      flow.url,
      URL(
        string:
          "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read%20write&redirect_to=https://dummy-url.com/redirect&code_challenge=hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY&code_challenge_method=s256&extra_key=extra_value"
      )!
    )
  }

  @Test
  func refreshSession() async throws {
    transport.stub(.post, "token", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 33" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"refresh_token\":\"refresh-token\"}" \
      	"http://localhost:54321/auth/v1/token?grant_type=refresh_token"
      """#
    }

    let sut = makeSUT()
    var session = Session.valid
    session.refreshToken = "refresh-token"
    try await sut.seedSession(session)
    try await sut.refreshSession()
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
    @Test
    func sessionFromURL() async throws {
      transport.stub(.get, "user", data: MockData.user) {
        #"""
        curl \
        	--header "Authorization: bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/user"
        """#
      }

      let currentDate = Date()

      let sut = makeSUT(
        date: { currentDate }, redirectTo: URL(string: "https://dummy-url.com/callback")!)

      let url = URL(
        string:
          "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
      )!

      let result = try await sut.handleRedirect(url)
      let expectedSession = Session(
        accessToken: "accesstoken",
        tokenType: "bearer",
        expiresIn: .seconds(60),
        expiresAt: currentDate.addingTimeInterval(60),
        receivedAt: currentDate,
        refreshToken: "refreshtoken",
        user: User(fromMockNamed: "user")
      )
      expectNoDifference(result, .signedIn(expectedSession, verification: nil))
    }
  #endif

  @Test
  func importSessionWithAFutureExpirationDate() async throws {
    transport.stub(.get, "user", data: MockData.user) {
      #"""
      curl \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }

    let sut = makeSUT()
    try await sut.seedSession(.valid)

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    try await sut.importSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  @Test
  func importSessionWithAnExpiredToken() async throws {
    transport.stub(.post, "token", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 39" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"refresh_token\":\"dummy-refresh-token\"}" \
      	"http://localhost:54321/auth/v1/token?grant_type=refresh_token"
      """#
    }

    let sut = makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

    try await sut.importSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  @Test
  func verifyOTPUsingEmail() async throws {
    transport.stub(.post, "verify", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 64" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"email\":\"example@mail.com\",\"token\":\"123456\",\"type\":\"magiclink\"}" \
      	"http://localhost:54321/auth/v1/verify"
      """#
    }

    let sut = makeSUT()

    let result = try await sut.verifyOTP(
      email: "example@mail.com",
      token: "123456",
      type: .magiclink
    )

    guard case .signedIn(let session) = result else {
      Issue.record("Expected .signedIn, got \(result)")
      return
    }
    #expect(sut.currentSession == session)
  }

  @Test
  func verifyOTPUsingPhone() async throws {
    transport.stub(.post, "verify", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 57" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"phone\":\"+1 202-918-2132\",\"token\":\"123456\",\"type\":\"sms\"}" \
      	"http://localhost:54321/auth/v1/verify"
      """#
    }

    let sut = makeSUT()

    try await sut.verifyOTP(
      phone: "+1 202-918-2132",
      token: "123456",
      type: .sms
    )
  }

  @Test
  func verifyOTPUsingTokenHash() async throws {
    transport.stub(.post, "verify", data: MockData.session) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 39" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"token_hash\":\"abc-def\",\"type\":\"email\"}" \
      	"http://localhost:54321/auth/v1/verify"
      """#
    }

    let sut = makeSUT()

    try await sut.verifyOTP(
      tokenHash: "abc-def",
      type: .email
    )
  }

  @Test(arguments: [
    (EmailOTPType.recovery, AuthEvent.passwordRecovery),
    (EmailOTPType.emailChange, AuthEvent.signedIn),
    (EmailOTPType.email, AuthEvent.signedIn),
  ])
  func verifyOTPWithTokenHashEmitsTheEventForItsType(
    type: EmailOTPType, event: AuthEvent
  ) async throws {
    transport.stub(.post, "verify", data: MockData.session)
    let sut = makeSUT()

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.verifyOTP(tokenHash: "abc-def", type: type) },
      expectedEvents: [.initialSession, event]
    )
  }

  @Test(arguments: ["email", "phone"])
  func verifyOTPForAChangeOfTheSignedInUserEmitsUserUpdated(channel: String) async throws {
    transport.stub(.post, "verify", data: MockData.session)
    let sut = makeSUT()
    let held = try AuthClient.Configuration.jsonDecoder.decode(
      Session.self, from: MockData.session
    ).received(at: Self.now)
    try await sut.seedSession(held)

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        if channel == "email" {
          try await sut.verifyOTP(tokenHash: "abc-def", type: .emailChange)
        } else {
          try await sut.verifyOTP(phone: "+1 202-918-2132", token: "123456", type: .phoneChange)
        }
      },
      expectedEvents: [.initialSession, .userUpdated]
    )
  }

  @Test
  func verifyOTPWithEmailForRecoveryEmitsPasswordRecovery() async throws {
    transport.stub(.post, "verify", data: MockData.session)
    let sut = makeSUT()

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        try await sut.verifyOTP(email: "example@mail.com", token: "123456", type: .recovery)
      },
      expectedEvents: [.initialSession, .passwordRecovery]
    )
  }

  @Test(arguments: [
    (PhoneOTPType.phoneChange, AuthEvent.signedIn),
    (PhoneOTPType.sms, AuthEvent.signedIn),
  ])
  func verifyOTPWithPhoneEmitsTheEventForItsType(
    type: PhoneOTPType, event: AuthEvent
  ) async throws {
    transport.stub(.post, "verify", data: MockData.session)
    let sut = makeSUT()

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.verifyOTP(phone: "+1 202-918-2132", token: "123456", type: type) },
      expectedEvents: [.initialSession, event]
    )
  }

  @Test
  func verifyOTPForEmailChangeSingleConfirmation() async throws {
    transport.stub(.post, "verify", data: MockData.emailChangeSingleConfirmation)

    let sut = makeSUT()

    let result = try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.verifyOTP(tokenHash: "abc-def", type: .emailChange) },
      expectedEvents: [.initialSession]
    )

    #expect(
      result
        == .emailChangePending(
          message:
            "Confirmation link accepted. Please proceed to confirm link sent to the other email"
        )
    )
    #expect(sut.currentSession == nil)
  }

  /// The time `makeSUT` stamps on every session its client receives by default.
  static let now = Date()

  func makeSUT(
    url: URL = clientURL,
    storageKey: String = uniqueStorageKey(),
    date: @escaping @Sendable () -> Date = { Self.now },
    platform: AuthPlatform = .live,
    autoRefresh: AuthClient.AutoRefreshPolicy = .manual,
    redirectTo: URL? = nil
  ) -> AuthClient {
    let configuration = AuthClient.Configuration(
      url: url,
      storageKey: storageKey,
      headers: HTTPFields(["apikey": apiKey]),
      storage: storage,
      redirectTo: redirectTo,
      autoRefresh: autoRefresh,
      http: .init(transport: transport),
      now: date)

    var pkce = PKCE.live
    pkce.generateCodeVerifier = {
      "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
    }
    pkce.generateCodeChallenge = { _ in
      "hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY"
    }

    return AuthClient(configuration: configuration, pkce: pkce, platform: platform)
  }

  func assertAuthStateChanges<T>(
    sut: AuthClient,
    action: () async throws -> T,
    expectedEvents: [AuthEvent],
    expectedSessions: [Session?]? = nil,
    timeout: Duration = .seconds(30),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws -> T {
    let events = sut.events()
    try await sut.dependencies.sessionStore.load()
    let result = try await action()
    sut.dependencies.sessionStore.finishChanges()
    let changes = try await withTimeout(timeout) { await events.collect() }

    expectNoDifference(
      changes.map(\.event), expectedEvents,
      fileID: fileID, filePath: filePath, line: line, column: column)

    if let expectedSessions {
      expectNoDifference(
        changes.map(\.session), expectedSessions,
        fileID: fileID, filePath: filePath, line: line, column: column)
    }

    return result
  }
}

enum MockData {
  static let listUsersResponse = try! Data(
    contentsOf: Bundle.module.url(forResource: "list-users-response", withExtension: "json")!
  )

  static let session = try! Data(
    contentsOf: Bundle.module.url(forResource: "session", withExtension: "json")!
  )

  static let user = try! Data(
    contentsOf: Bundle.module.url(forResource: "user", withExtension: "json")!
  )

  static let anonymousSignInResponse = try! Data(
    contentsOf: Bundle.module.url(forResource: "anonymous-sign-in-response", withExtension: "json")!
  )

  static let signUpConfirmationRequired = try! Data(
    contentsOf: Bundle.module.url(forResource: "signup-response", withExtension: "json")!
  )

  static let emailChangeSingleConfirmation = try! Data(
    contentsOf: Bundle.module.url(
      forResource: "email-change-single-confirmation", withExtension: "json"
    )!
  )
}

#if canImport(AuthenticationServices) && !os(watchOS)
  extension WebAuthnAuthenticator {
    /// An authenticator whose ceremonies return `{}` unless a test overrides them.
    static func fake(
      register:
        @escaping @MainActor @Sendable (WebAuthnCreationOptions, ASPresentationAnchor?)
        async throws -> JSONValue = { _, _ in [:] },
      authenticate:
        @escaping @MainActor @Sendable (WebAuthnRequestOptions, ASPresentationAnchor?)
        async throws -> JSONValue = { _, _ in [:] }
    ) -> Self {
      WebAuthnAuthenticator(register: register, authenticate: authenticate)
    }
  }
#endif
