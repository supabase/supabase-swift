//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import Mocker
import TestHelpers
import XCTest

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthClientTests: XCTestCase {
  var sessionManager: SessionManager!

  var storage: InMemoryLocalStorage!

  var http: HTTPClientMock!
  var sut: AuthClient!

  #if !os(Windows) && !os(Linux) && !os(Android)
    override func invokeTest() {
      withMainSerialExecutor {
        super.invokeTest()
      }
    }
  #endif

  override func setUp() {
    super.setUp()
    storage = InMemoryLocalStorage()

    //    isRecording = true
  }

  override func tearDown() {
    super.tearDown()

    Mocker.removeAll()

    let completion = { [weak sut] in
      XCTAssertNil(sut, "sut should not leak")
    }

    defer { completion() }

    sut = nil
    sessionManager = nil
    storage = nil
  }

  func testOnAuthStateChanges() async throws {
    let session = Session.validSession
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(session)

    let events = LockIsolated([AuthChangeEvent]())

    let handle = await sut.onAuthStateChange { event, _ in
      events.withValue {
        $0.append(event)
      }
    }

    expectNoDifference(events.value, [.initialSession])

    handle.remove()
  }

  func testAuthStateChanges() async throws {
    let session = Session.validSession
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(session)

    let stateChange = await sut.authStateChanges.first { _ in true }
    expectNoDifference(stateChange?.event, .initialSession)
    expectNoDifference(stateChange?.session, session)
  }

  func testSignOut() async throws {
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("logout"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .post: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/logout?scope=global"
      """#
    }
    .register()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.signOut() },
      expectedEvents: [.initialSession, .signedOut]
    )

    do {
      _ = try await sut.session
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        - AuthError.sessionMissing

        """
      }
    }
  }

  func testSignOutWithOthersScopeShouldNotRemoveLocalSession() async throws {
    Mock(
      url: clientURL.appendingPathComponent("logout").appendingQueryItems([
        URLQueryItem(name: "scope", value: "others")
      ]),
      statusCode: 200,
      data: [
        .post: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/logout?scope=others"
      """#
    }
    .register()

    sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.signOut(scope: .others)

    let sessionRemoved = Dependencies[sut.clientID].sessionStorage.get() == nil
    XCTAssertFalse(sessionRemoved)
  }

  func testSignOutShouldRemoveSessionIfUserIsNotFound() async throws {
    Mock(
      url: clientURL.appendingPathComponent("logout").appendingQueryItems([
        URLQueryItem(name: "scope", value: "global")
      ]),
      statusCode: 404,
      data: [
        .post: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/logout?scope=global"
      """#
    }
    .register()

    sut = makeSUT()

    let validSession = Session.validSession
    Dependencies[sut.clientID].sessionStorage.store(validSession)

    let eventsTask = Task { [sut] in
      await sut!.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    try await sut.signOut()

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    expectNoDifference(events, [.initialSession, .signedOut])
    expectNoDifference(sessions, [.validSession, nil])

    let sessionRemoved = Dependencies[sut.clientID].sessionStorage.get() == nil
    XCTAssertTrue(sessionRemoved)
  }

  func testSignOutShouldRemoveSessionIfJWTIsInvalid() async throws {
    Mock(
      url: clientURL.appendingPathComponent("logout").appendingQueryItems([
        URLQueryItem(name: "scope", value: "global")
      ]),
      statusCode: 401,
      data: [
        .post: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/logout?scope=global"
      """#
    }
    .register()

    sut = makeSUT()

    let validSession = Session.validSession
    Dependencies[sut.clientID].sessionStorage.store(validSession)

    let eventsTask = Task { [sut] in
      await sut!.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    try await sut.signOut()

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    expectNoDifference(events, [.initialSession, .signedOut])
    expectNoDifference(sessions, [validSession, nil])

    let sessionRemoved = Dependencies[sut.clientID].sessionStorage.get() == nil
    XCTAssertTrue(sessionRemoved)
  }

  func testSignOutShouldRemoveSessionIf403Returned() async throws {
    Mock(
      url: clientURL.appendingPathComponent("logout").appendingQueryItems([
        URLQueryItem(name: "scope", value: "global")
      ]),
      statusCode: 403,
      data: [
        .post: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/logout?scope=global"
      """#
    }
    .register()

    sut = makeSUT()

    let validSession = Session.validSession
    Dependencies[sut.clientID].sessionStorage.store(validSession)

    let eventsTask = Task { [sut] in
      await sut!.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    try await sut.signOut()

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    expectNoDifference(events, [.initialSession, .signedOut])
    expectNoDifference(sessions, [validSession, nil])

    let sessionRemoved = Dependencies[sut.clientID].sessionStorage.get() == nil
    XCTAssertTrue(sessionRemoved)
  }

  func testSignInAnonymously() async throws {
    let session = Session(fromMockNamed: "anonymous-sign-in-response")

    Mock(
      url: clientURL.appendingPathComponent("signup"),
      statusCode: 200,
      data: [
        .post: MockData.anonymousSignInResponse
      ]
    )
    .snapshotRequest {
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
    .register()

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

  func testSignInWithOAuth() async throws {
    Mock(
      url: clientURL.appendingPathComponent("token").appendingQueryItems([
        URLQueryItem(name: "grant_type", value: "pkce")
      ]),
      statusCode: 200,
      data: [
        .post: MockData.session
      ]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    try await sut.signInWithOAuth(
      provider: .google,
      redirectTo: URL(string: "supabase://auth-callback")
    ) { (url: URL) in
      URL(string: "supabase://auth-callback?code=12345") ?? url
    }

    let events = await eventsTask.value.map(\.event)

    expectNoDifference(events, [.initialSession, .signedIn])
  }

  func testGetLinkIdentityURL() async throws {
    let url =
      "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("user/identities/authorize"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data(
          """
          {
            "url": "\(url)"
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user/identities/authorize?code_challenge=hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY&code_challenge_method=s256&provider=github&skip_http_redirect=true"
      """#
    }
    .register()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.getLinkIdentityURL(provider: .github)

    expectNoDifference(
      response,
      OAuthResponse(
        provider: .github,
        url: URL(
          string: url
        )!
      )
    )
  }

  func testLinkIdentity() async throws {
    let url =
      "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"

    Mock(
      url: clientURL.appendingPathComponent("user/identities/authorize"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: Data(
          """
          {
            "url": "\(url)"
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user/identities/authorize?code_challenge=hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY&code_challenge_method=s256&provider=github&skip_http_redirect=true"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let receivedURL = LockIsolated<URL?>(nil)
    Dependencies[sut.clientID].urlOpener.open = { url in
      receivedURL.setValue(url)
    }

    try await sut.linkIdentity(provider: .github)

    expectNoDifference(receivedURL.value?.absoluteString, url)
  }

  func testLinkIdentityWithIdToken() async throws {
    Mock(
      url: clientURL.appendingPathComponent("token"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let updatedSession = try await assertAuthStateChanges(
      sut: sut,
      action: {
        try await sut.linkIdentityWithIdToken(
          credentials: OpenIDConnectCredentials(
            provider: .apple,
            idToken: "id-token",
            accessToken: "access-token",
            nonce: "nonce",
            gotrueMetaSecurity: AuthMetaSecurity(
              captchaToken: "captcha-token"
            )
          )
        )
      },
      expectedEvents: [.initialSession, .userUpdated]
    )

    expectNoDifference(sut.currentSession, updatedSession)
  }

  func testAdminListUsers() async throws {
    Mock(
      url: clientURL.appendingPathComponent("admin/users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: MockData.listUsersResponse
      ],
      additionalHeaders: [
        "X-Total-Count": "669",
        "Link":
          "</admin/users?page=2&per_page=>; rel=\"next\", </admin/users?page=14&per_page=>; rel=\"last\"",
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/admin/users?page=&per_page="
      """#
    }
    .register()

    let sut = makeSUT()

    let response = try await sut.admin.listUsers()
    expectNoDifference(response.total, 669)
    expectNoDifference(response.nextPage, 2)
    expectNoDifference(response.lastPage, 14)
  }

  func testAdminListUsers_noNextPage() async throws {
    Mock(
      url: clientURL.appendingPathComponent("admin/users"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .get: MockData.listUsersResponse
      ],
      additionalHeaders: [
        "X-Total-Count": "669",
        "Link": "</admin/users?page=14&per_page=>; rel=\"last\"",
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/admin/users?page=&per_page="
      """#
    }
    .register()

    let sut = makeSUT()

    let response = try await sut.admin.listUsers()
    expectNoDifference(response.total, 669)
    XCTAssertNil(response.nextPage)
    expectNoDifference(response.lastPage, 14)
  }

  func testSessionFromURL_withError() async throws {
    sut = makeSUT()

    Dependencies[sut.clientID].codeVerifierStorage.set("code-verifier")

    let url = URL(
      string:
        "https://my.redirect.com?error=server_error&error_code=422&error_description=Identity+is+already+linked+to+another+user#error=server_error&error_code=422&error_description=Identity+is+already+linked+to+another+user"
    )!

    do {
      try await sut.session(from: url)
      XCTFail("Expect failure")
    } catch {
      expectNoDifference(
        error as? AuthError,
        AuthError.pkceGrantCodeExchange(
          message: "Identity is already linked to another user",
          error: "server_error",
          code: "422"
        )
      )
    }
  }

  func testSignUpWithEmailAndPassword() async throws {
    Mock(
      url: clientURL.appendingPathComponent("signup"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    try await sut.signUp(
      email: "example@mail.com",
      password: "the.pass",
      data: ["custom_key": .string("custom_value")],
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "dummy-captcha"
    )
  }

  func testSignUpWithPhoneAndPassword() async throws {
    Mock(
      url: clientURL.appendingPathComponent("signup"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    try await sut.signUp(
      phone: "+1 202-918-2132",
      password: "the.pass",
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  func testSignInWithEmailAndPassword() async throws {
    Mock(
      url: clientURL.appendingPathComponent("token"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    try await sut.signIn(
      email: "example@mail.com",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  func testSignInWithPhoneAndPassword() async throws {
    Mock(
      url: clientURL.appendingPathComponent("token"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    try await sut.signIn(
      phone: "+1 202-918-2132",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  func testSignInWithIdToken() async throws {
    Mock(
      url: clientURL.appendingPathComponent("token"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    try await sut.signInWithIdToken(
      credentials: OpenIDConnectCredentials(
        provider: .apple,
        idToken: "id-token",
        accessToken: "access-token",
        nonce: "nonce",
        gotrueMetaSecurity: AuthMetaSecurity(
          captchaToken: "captcha-token"
        )
      )
    )
  }

  func testSignInWithOTPUsingEmail() async throws {
    Mock(
      url: clientURL.appendingPathComponent("otp"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data()]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    try await sut.signInWithOTP(
      email: "example@mail.com",
      redirectTo: URL(string: "https://supabase.com"),
      shouldCreateUser: true,
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  func testSignInWithOTPUsingPhone() async throws {
    Mock(
      url: clientURL.appendingPathComponent("otp"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 156" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"channel\":\"sms\",\"create_user\":true,\"data\":{\"custom_key\":\"custom_value\"},\"gotrue_meta_security\":{\"captcha_token\":\"dummy-captcha\"},\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/otp"
      """#
    }
    .register()

    let sut = makeSUT()

    try await sut.signInWithOTP(
      phone: "+1 202-918-2132",
      shouldCreateUser: true,
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  func testGetOAuthSignInURL() async throws {
    let sut = makeSUT(flowType: .implicit)
    let url = try sut.getOAuthSignInURL(
      provider: .github,
      scopes: "read,write",
      redirectTo: URL(string: "https://dummy-url.com/redirect")!,
      queryParams: [("extra_key", "extra_value")]
    )
    expectNoDifference(
      url,
      URL(
        string:
          "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read,write&redirect_to=https://dummy-url.com/redirect&extra_key=extra_value"
      )!
    )
  }

  func testRefreshSession() async throws {
    Mock(
      url: clientURL.appendingPathComponent("token"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()
    try await sut.refreshSession(refreshToken: "refresh-token")
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
    func testSessionFromURL() async throws {
      Mock(
        url: clientURL.appendingPathComponent("user"),
        ignoreQuery: true,
        statusCode: 200,
        data: [.get: MockData.user]
      )
      .snapshotRequest {
        #"""
        curl \
        	--header "Authorization: bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/user"
        """#
      }
      .register()

      let sut = makeSUT(flowType: .implicit)

      let currentDate = Date()

      Dependencies[sut.clientID].date = { currentDate }

      let url = URL(
        string:
          "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
      )!

      let session = try await sut.session(from: url)
      let expectedSession = Session(
        accessToken: "accesstoken",
        tokenType: "bearer",
        expiresIn: 60,
        expiresAt: currentDate.addingTimeInterval(60).timeIntervalSince1970,
        refreshToken: "refreshtoken",
        user: User(fromMockNamed: "user")
      )
      expectNoDifference(session, expectedSession)
    }
  #endif

  func testSessionWithURL_implicitFlow() async throws {
    Mock(
      url: clientURL.appendingPathComponent("user"),
      statusCode: 200,
      data: [
        .get: MockData.user
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }
    .register()

    let sut = makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
    )!
    try await sut.session(from: url)
  }

  func testSessionWithURL_implicitFlow_invalidURL() async throws {
    let sut = makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#invalid_key=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
    )!

    do {
      try await sut.session(from: url)
    } catch let AuthError.implicitGrantRedirect(message) {
      expectNoDifference(message, "Not a valid implicit grant flow URL: \(url)")
    }
  }

  func testSessionWithURL_implicitFlow_error() async throws {
    let sut = makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#error_description=Invalid+code&error=invalid_grant"
    )!

    do {
      try await sut.session(from: url)
    } catch let AuthError.implicitGrantRedirect(message) {
      expectNoDifference(message, "Invalid code")
    }
  }

  func testSessionWithURL_implicitFlow_recoveryType() async throws {
    Mock(
      url: clientURL.appendingPathComponent("user"),
      statusCode: 200,
      data: [
        .get: MockData.user
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }
    .register()

    let sut = makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer&type=recovery"
    )!

    let eventsTask = Task {
      await sut.authStateChanges.prefix(3).collect().map(\.event)
    }

    await Task.yield()

    try await sut.session(from: url)

    let events = await eventsTask.value
    expectNoDifference(events, [.initialSession, .signedIn, .passwordRecovery])
  }

  func testSessionWithURL_pkceFlow_error() async throws {
    let sut = makeSUT()

    let url = URL(
      string:
        "https://dummy-url.com/callback#error_description=Invalid+code&error=invalid_grant&error_code=500"
    )!

    do {
      try await sut.session(from: url)
    } catch let AuthError.pkceGrantCodeExchange(message, error, code) {
      expectNoDifference(message, "Invalid code")
      expectNoDifference(error, "invalid_grant")
      expectNoDifference(code, "500")
    }
  }

  func testSessionWithURL_pkceFlow_error_noErrorDescription() async throws {
    let sut = makeSUT()

    let url = URL(
      string:
        "https://dummy-url.com/callback#error=invalid_grant&error_code=500"
    )!

    do {
      try await sut.session(from: url)
    } catch let AuthError.pkceGrantCodeExchange(message, error, code) {
      expectNoDifference(message, "Error in URL with unspecified error_description.")
      expectNoDifference(error, "invalid_grant")
      expectNoDifference(code, "500")
    }
  }

  func testSessionFromURLWithMissingComponent() async {
    let sut = makeSUT()

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken"
    )!

    do {
      _ = try await sut.session(from: url)
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        ▿ AuthError
          ▿ pkceGrantCodeExchange: (3 elements)
            - message: "Not a valid PKCE flow URL: https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken"
            - error: Optional<String>.none
            - code: Optional<String>.none

        """
      }
    }
  }

  func testSetSessionWithAFutureExpirationDate() async throws {
    Mock(
      url: clientURL.appendingPathComponent("user"),
      statusCode: 200,
      data: [.get: MockData.user]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }
    .register()

    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  func testSetSessionWithAExpiredToken() async throws {
    Mock(
      url: clientURL.appendingPathComponent("token"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

    try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  func testVerifyOTPUsingEmail() async throws {
    Mock(
      url: clientURL.appendingPathComponent("verify"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 121" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"token\":\"123456\",\"type\":\"magiclink\"}" \
      	"http://localhost:54321/auth/v1/verify?redirect_to=https://supabase.com"
      """#
    }
    .register()

    let sut = makeSUT()

    try await sut.verifyOTP(
      email: "example@mail.com",
      token: "123456",
      type: .magiclink,
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  func testVerifyOTPUsingPhone() async throws {
    Mock(
      url: clientURL.appendingPathComponent("verify"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 114" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"phone\":\"+1 202-918-2132\",\"token\":\"123456\",\"type\":\"sms\"}" \
      	"http://localhost:54321/auth/v1/verify"
      """#
    }
    .register()

    let sut = makeSUT()

    try await sut.verifyOTP(
      phone: "+1 202-918-2132",
      token: "123456",
      type: .sms,
      captchaToken: "captcha-token"
    )
  }

  func testVerifyOTPUsingTokenHash() async throws {
    Mock(
      url: clientURL.appendingPathComponent("verify"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
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
    .register()

    let sut = makeSUT()

    try await sut.verifyOTP(
      tokenHash: "abc-def",
      type: .email
    )
  }

  func testUpdateUser() async throws {
    Mock(
      url: clientURL.appendingPathComponent("user"),
      statusCode: 200,
      data: [.put: MockData.user]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request PUT \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 228" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"data\":{\"custom_key\":\"custom_value\"},\"email\":\"example@mail.com\",\"nonce\":\"abcdef\",\"password\":\"another.pass\",\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.update(
      user: UserAttributes(
        email: "example@mail.com",
        phone: "+1 202-918-2132",
        password: "another.pass",
        nonce: "abcdef",
        data: ["custom_key": .string("custom_value")]
      )
    )
  }

  func testResetPasswordForEmail() async throws {
    Mock(
      url: clientURL.appendingPathComponent("recover"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 179" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"}}" \
      	"http://localhost:54321/auth/v1/recover?redirect_to=https://supabase.com"
      """#
    }
    .register()

    let sut = makeSUT()
    try await sut.resetPasswordForEmail(
      "example@mail.com",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  func testResendEmail() async throws {
    Mock(
      url: clientURL.appendingPathComponent("resend"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 107" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"email\":\"example@mail.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"type\":\"email_change\"}" \
      	"http://localhost:54321/auth/v1/resend?redirect_to=https://supabase.com"
      """#
    }
    .register()

    let sut = makeSUT()

    try await sut.resend(
      email: "example@mail.com",
      type: .emailChange,
      emailRedirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  func testResendPhone() async throws {
    Mock(
      url: clientURL.appendingPathComponent("resend"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data(#"{"message_id": "12345"}"#.utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 106" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"phone\":\"+1 202-918-2132\",\"type\":\"phone_change\"}" \
      	"http://localhost:54321/auth/v1/resend"
      """#
    }
    .register()

    let sut = makeSUT()

    let response = try await sut.resend(
      phone: "+1 202-918-2132",
      type: .phoneChange,
      captchaToken: "captcha-token"
    )

    expectNoDifference(response.messageId, "12345")
  }

  func testDeleteUser() async throws {
    let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    Mock(
      url: clientURL.appendingPathComponent("admin/users/\(id)"),
      statusCode: 204,
      data: [.delete: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request DELETE \
      	--header "Content-Length: 28" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"should_soft_delete\":false}" \
      	"http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }
    .register()

    let sut = makeSUT()
    try await sut.admin.deleteUser(id: id)
  }

  func testReauthenticate() async throws {
    Mock(
      url: clientURL.appendingPathComponent("reauthenticate"),
      statusCode: 200,
      data: [.get: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/reauthenticate"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.reauthenticate()
  }

  func testUnlinkIdentity() async throws {
    let identityId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    Mock(
      url: clientURL.appendingPathComponent("user/identities/\(identityId.uuidString)"),
      statusCode: 204,
      data: [.delete: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user/identities/E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.unlinkIdentity(
      UserIdentity(
        id: "5923044",
        identityId: identityId,
        userId: UUID(),
        identityData: [:],
        provider: "email",
        createdAt: Date(),
        lastSignInAt: Date(),
        updatedAt: Date()
      )
    )
  }

  func testSignInWithSSOUsingDomain() async throws {
    Mock(
      url: clientURL.appendingPathComponent("sso"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data(#"{"url":"https://supabase.com"}"#.utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 215" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"domain\":\"supabase.com\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"redirect_to\":\"https:\/\/supabase.com\"}" \
      	"http://localhost:54321/auth/v1/sso"
      """#
    }
    .register()

    let sut = makeSUT()

    let response = try await sut.signInWithSSO(
      domain: "supabase.com",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )

    expectNoDifference(response.url, URL(string: "https://supabase.com")!)
  }

  func testSignInWithSSOUsingProviderId() async throws {
    Mock(
      url: clientURL.appendingPathComponent("sso"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data(#"{"url":"https://supabase.com"}"#.utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 244" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"gotrue_meta_security\":{\"captcha_token\":\"captcha-token\"},\"provider_id\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\",\"redirect_to\":\"https:\/\/supabase.com\"}" \
      	"http://localhost:54321/auth/v1/sso"
      """#
    }
    .register()

    let sut = makeSUT()

    let response = try await sut.signInWithSSO(
      providerId: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )

    expectNoDifference(response.url, URL(string: "https://supabase.com")!)
  }

  func testMFAEnrollLegacy() async throws {
    Mock(
      url: clientURL.appendingPathComponent("factors"),
      statusCode: 200,
      data: [
        .post: Data(
          """
          {
            "id": "12345",
            "type": "totp"
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 69" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"factor_type\":\"totp\",\"friendly_name\":\"test\",\"issuer\":\"supabase.com\"}" \
      	"http://localhost:54321/auth/v1/factors"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.enroll(
      params: .totp(
        issuer: "supabase.com",
        friendlyName: "test"
      )
    )

    expectNoDifference(response.id, "12345")
    expectNoDifference(response.type, "totp")
  }

  func testMFAEnrollTotp() async throws {
    Mock(
      url: clientURL.appendingPathComponent("factors"),
      statusCode: 200,
      data: [
        .post: Data(
          """
          {
            "id": "12345",
            "type": "totp"
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 69" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"factor_type\":\"totp\",\"friendly_name\":\"test\",\"issuer\":\"supabase.com\"}" \
      	"http://localhost:54321/auth/v1/factors"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.enroll(
      params: .totp(
        issuer: "supabase.com",
        friendlyName: "test"
      )
    )

    expectNoDifference(response.id, "12345")
    expectNoDifference(response.type, "totp")
  }

  func testMFAEnrollPhone() async throws {
    Mock(
      url: clientURL.appendingPathComponent("factors"),
      statusCode: 200,
      data: [
        .post: Data(
          """
          {
            "id": "12345",
            "type": "phone"
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 72" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"factor_type\":\"phone\",\"friendly_name\":\"test\",\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/factors"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.enroll(
      params: .phone(
        friendlyName: "test",
        phone: "+1 202-918-2132"
      )
    )

    expectNoDifference(response.id, "12345")
    expectNoDifference(response.type, "phone")
  }

  func testMFAChallenge() async throws {
    let factorId = "123"

    Mock(
      url: clientURL.appendingPathComponent("factors/\(factorId)/challenge"),
      statusCode: 200,
      data: [
        .post: Data(
          """
          {
            "id": "12345",
            "type": "totp",
            "expires_at": 12345678
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/factors/123/challenge"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.challenge(params: .init(factorId: factorId))

    expectNoDifference(
      response,
      AuthMFAChallengeResponse(
        id: "12345",
        type: "totp",
        expiresAt: 12_345_678
      )
    )
  }

  func testMFAChallengeWithPhoneType() async throws {
    let factorId = "123"

    Mock(
      url: clientURL.appendingPathComponent("factors/\(factorId)/challenge"),
      statusCode: 200,
      data: [
        .post: Data(
          """
          {
            "id": "12345",
            "type": "phone",
            "expires_at": 12345678
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 17" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"channel\":\"sms\"}" \
      	"http://localhost:54321/auth/v1/factors/123/challenge"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.challenge(
      params: .init(
        factorId: factorId,
        channel: .sms
      )
    )

    expectNoDifference(
      response,
      AuthMFAChallengeResponse(
        id: "12345",
        type: "phone",
        expiresAt: 12_345_678
      )
    )
  }

  func testMFAVerify() async throws {
    let factorId = "123"

    Mock(
      url: clientURL.appendingPathComponent("factors/\(factorId)/verify"),
      statusCode: 200,
      data: [.post: MockData.session]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 56" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"challenge_id\":\"123\",\"code\":\"123456\",\"factor_id\":\"123\"}" \
      	"http://localhost:54321/auth/v1/factors/123/verify"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.mfa.verify(
      params: .init(
        factorId: factorId,
        challengeId: "123",
        code: "123456"
      )
    )
  }

  func testMFAUnenroll() async throws {
    Mock(
      url: clientURL.appendingPathComponent("factors/123"),
      statusCode: 204,
      data: [.delete: Data(#"{"factor_id":"123"}"#.utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request DELETE \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/factors/123"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let factorId = try await sut.mfa.unenroll(params: .init(factorId: "123")).factorId

    expectNoDifference(factorId, "123")
  }

  func testMFAChallengeAndVerify() async throws {
    let factorId = "123"
    let code = "456"

    Mock(
      url: clientURL.appendingPathComponent("factors/\(factorId)/challenge"),
      statusCode: 200,
      data: [
        .post: Data(
          """
          {
            "id": "12345",
            "type": "totp",
            "expires_at": 12345678
          }
          """.utf8
        )
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/factors/123/challenge"
      """#
    }
    .register()

    Mock(
      url: clientURL.appendingPathComponent("factors/\(factorId)/verify"),
      statusCode: 200,
      data: [
        .post: MockData.session
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer accesstoken" \
      	--header "Content-Length: 55" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"challenge_id\":\"12345\",\"code\":\"456\",\"factor_id\":\"123\"}" \
      	"http://localhost:54321/auth/v1/factors/123/verify"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.mfa.challengeAndVerify(
      params: MFAChallengeAndVerifyParams(
        factorId: factorId,
        code: code
      )
    )
  }

  func testMFAListFactors() async throws {
    let sut = makeSUT()

    var session = Session.validSession
    session.user.factors = [
      Factor(
        id: "1",
        friendlyName: nil,
        factorType: "totp",
        status: .verified,
        createdAt: Date(),
        updatedAt: Date()
      ),
      Factor(
        id: "2",
        friendlyName: nil,
        factorType: "totp",
        status: .unverified,
        createdAt: Date(),
        updatedAt: Date()
      ),
      Factor(
        id: "3",
        friendlyName: nil,
        factorType: "phone",
        status: .verified,
        createdAt: Date(),
        updatedAt: Date()
      ),
      Factor(
        id: "4",
        friendlyName: nil,
        factorType: "phone",
        status: .unverified,
        createdAt: Date(),
        updatedAt: Date()
      ),
    ]

    Dependencies[sut.clientID].sessionStorage.store(session)

    let factors = try await sut.mfa.listFactors()
    expectNoDifference(factors.totp.map(\.id), ["1"])
    expectNoDifference(factors.phone.map(\.id), ["3"])
  }

  func testGetAuthenticatorAssuranceLevel_whenAALAndVerifiedFactor_shouldReturnAAL2() async throws {
    var session = Session.validSession

    // access token with aal token
    session.accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJhYWwiOiJhYWwxIiwiYW1yIjpbeyJtZXRob2QiOiJ0b3RwIiwidGltZXN0YW1wIjoxNTE2MjM5MDIyfSx7Im1ldGhvZCI6InBob25lIiwidGltZXN0YW1wIjoxNTE2MjM5MDIyfV19.OQy2SmA1hcw9V5wrY-bvORjbFh5tWznLIfcMCqPu_6M"

    session.user.factors = [
      Factor(
        id: "1",
        friendlyName: nil,
        factorType: "totp",
        status: .verified,
        createdAt: Date(),
        updatedAt: Date()
      )
    ]

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(session)

    let aal = try await sut.mfa.getAuthenticatorAssuranceLevel()

    expectNoDifference(
      aal,
      AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: "aal1",
        nextLevel: "aal2",
        currentAuthenticationMethods: [
          AMREntry(
            method: "totp",
            timestamp: 1_516_239_022
          ),
          AMREntry(
            method: "phone",
            timestamp: 1_516_239_022
          ),
        ]
      )
    )
  }

  func testgetUserById() async throws {
    let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("admin/users/\(id)"),
      statusCode: 200,
      data: [.get: MockData.user]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B"
      """#
    }
    .register()

    let user = try await sut.admin.getUserById(id)

    expectNoDifference(user.id, id)
  }

  func testUpdateUserById() async throws {
    let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("admin/users/\(id)"),
      statusCode: 200,
      data: [.put: MockData.user]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request PUT \
      	--header "Content-Length: 63" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"phone\":\"1234567890\",\"user_metadata\":{\"full_name\":\"John Doe\"}}" \
      	"http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B"
      """#
    }
    .register()

    let attributes = AdminUserAttributes(
      phone: "1234567890",
      userMetadata: [
        "full_name": "John Doe"
      ]
    )

    let user = try await sut.admin.updateUserById(id, attributes: attributes)

    expectNoDifference(user.id, id)
  }

  func testCreateUser() async throws {
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("admin/users"),
      statusCode: 200,
      data: [.post: MockData.user]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 98" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"email\":\"test@example.com\",\"password\":\"password\",\"password_hash\":\"password\",\"phone\":\"1234567890\"}" \
      	"http://localhost:54321/auth/v1/admin/users"
      """#
    }
    .register()

    let attributes = AdminUserAttributes(
      email: "test@example.com",
      password: "password",
      passwordHash: "password",
      phone: "1234567890"
    )

    _ = try await sut.admin.createUser(attributes: attributes)
  }

  //  func testGenerateLink_signUp() async throws {
  //    let sut = makeSUT()
  //
  //    let user = User(fromMockNamed: "user")
  //    let encoder = JSONEncoder.supabase()
  //    encoder.keyEncodingStrategy = .convertToSnakeCase
  //
  //    let userData = try encoder.encode(user)
  //    var json = try JSONSerialization.jsonObject(with: userData, options: []) as! [String: Any]
  //
  //    json["action_link"] = "https://example.com/auth/v1/verify?type=signup&token={hashed_token}&redirect_to=https://example.com"
  //    json["email_otp"] = "123456"
  //    json["hashed_token"] = "hashed_token"
  //    json["redirect_to"] = "https://example.com"
  //    json["verification_type"] = "signup"
  //
  //    let responseData = try JSONSerialization.data(withJSONObject: json)
  //
  //    Mock(
  //      url: clientURL.appendingPathComponent("admin/generate_link"),
  //      statusCode: 200,
  //      data: [
  //        .post: responseData
  //      ]
  //    )
  //    .register()
  //
  //    let link = try await sut.admin.generateLink(
  //      params: .signUp(
  //        email: "test@example.com",
  //        password: "password",
  //        data: ["full_name": "John Doe"]
  //      )
  //    )
  //
  //    expectNoDifference(
  //      link.properties.actionLink.absoluteString,
  //      "https://example.com/auth/v1/verify?type=signup&token={hashed_token}&redirect_to=https://example.com".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
  //    )
  //  }

  func testInviteUserByEmail() async throws {
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("admin/invite"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: MockData.user]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 60" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"data\":{\"full_name\":\"John Doe\"},\"email\":\"test@example.com\"}" \
      	"http://localhost:54321/auth/v1/admin/invite?redirect_to=https://example.com"
      """#
    }
    .register()

    _ = try await sut.admin.inviteUserByEmail(
      "test@example.com",
      data: ["full_name": "John Doe"],
      redirectTo: URL(string: "https://example.com")
    )
  }

  func testRemoveSessionAndSignoutIfSessionNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("user"),
      statusCode: 403,
      data: [
        .get: Data(
          """
          {
            "error_code": "session_not_found",
            "message": "Session not found"
          }
          """.utf8
        )
      ]
    )
    .register()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.user()
          XCTFail("Expected failure")
        } catch {
          XCTAssertEqual(error as? AuthError, .sessionMissing)
        }
      },
      expectedEvents: [.initialSession, .signedOut]
    )

    XCTAssertNil(Dependencies[sut.clientID].sessionStorage.get())
  }

  func testRemoveSessionAndSignoutIfRefreshTokenNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("token").appendingQueryItems([
        URLQueryItem(name: "grant_type", value: "refresh_token")
      ]),
      statusCode: 403,
      data: [
        .post: Data(
          """
          {
            "error_code": "refresh_token_not_found",
            "message": "Invalid Refresh Token: Refresh Token Not Found"
          }
          """.utf8
        )
      ]
    )
    .register()

    Dependencies[sut.clientID].sessionStorage.store(.expiredSession)

    let expectedEvents = [AuthChangeEvent.signedOut, .initialSession]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.session
          XCTFail("Expected failure")
        } catch {
          XCTAssertEqual(error as? AuthError, .sessionMissing)
        }
      },
      expectedEvents: expectedEvents
    )

    XCTAssertNil(Dependencies[sut.clientID].sessionStorage.get())
  }

  func testRemoveSessionAndSignoutIfRefreshTokenNotFoundErrorReturned_withEmitLocalSessionAsInitialSession() async throws {
    let sut = makeSUT(emitLocalSessionAsInitialSession: true)

    Mock(
      url: clientURL.appendingPathComponent("token").appendingQueryItems([
        URLQueryItem(name: "grant_type", value: "refresh_token")
      ]),
      statusCode: 403,
      data: [
        .post: Data(
          """
          {
            "error_code": "refresh_token_not_found",
            "message": "Invalid Refresh Token: Refresh Token Not Found"
          }
          """.utf8
        )
      ]
    )
    .register()

    Dependencies[sut.clientID].sessionStorage.store(.expiredSession)

    let expectedEvents = [AuthChangeEvent.initialSession, .signedOut]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.session
          XCTFail("Expected failure")
        } catch {
          XCTAssertEqual(error as? AuthError, .sessionMissing)
        }
      },
      expectedEvents: expectedEvents
    )

    XCTAssertNil(Dependencies[sut.clientID].sessionStorage.get())
  }

  func testRefreshToken() async throws {
    let sut = makeSUT()

    Mock(
      url: clientURL.appendingPathComponent("token").appendingQueryItems([
        URLQueryItem(name: "grant_type", value: "refresh_token")
      ]),
      statusCode: 200,
      data: [.post: try AuthClient.Configuration.jsonEncoder.encode(Session.validSession)]
    )
    .register()

    Dependencies[sut.clientID].sessionStorage.store(.expiredSession)

    let expectedEvents = [AuthChangeEvent.tokenRefreshed, .initialSession]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        _ = try await sut.session
      },
      expectedEvents: expectedEvents
    )
  }

  func testRefreshToken_withEmitLocalSessionAsInitialSession() async throws {
    let sut = makeSUT(emitLocalSessionAsInitialSession: true)

    Mock(
      url: clientURL.appendingPathComponent("token").appendingQueryItems([
        URLQueryItem(name: "grant_type", value: "refresh_token")
      ]),
      statusCode: 200,
      data: [.post: try AuthClient.Configuration.jsonEncoder.encode(Session.validSession)]
    )
    .register()

    Dependencies[sut.clientID].sessionStorage.store(.expiredSession)

    let expectedEvents = [AuthChangeEvent.initialSession, .tokenRefreshed]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        _ = try await sut.session
      },
      expectedEvents: expectedEvents
    )
  }

  // MARK: - getClaims Tests

  func testGetClaims_withHS256JWT_shouldFallbackAndReturnClaims() async throws {
    // HS256 JWT (symmetric algorithm) - will use server-side verification
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    XCTAssertEqual(result.claims.sub, "1234567890")
    XCTAssertEqual(result.claims.iss, "http://localhost:54321/auth/v1")
    if case .string(let aud) = result.claims.aud {
      XCTAssertEqual(aud, "authenticated")
    } else {
      XCTFail("Expected string audience")
    }
    XCTAssertEqual(result.claims.role, "authenticated")
    XCTAssertEqual(result.header.alg, "HS256")
    XCTAssertNil(result.header.kid)
  }

  func testGetClaims_withoutJWT_shouldUseSessionAccessToken() async throws {
    // HS256 JWT from session
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

    var session = Session.validSession
    session.accessToken = jwt

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(session)

    let result = try await sut.getClaims()

    XCTAssertEqual(result.claims.sub, "1234567890")
    XCTAssertEqual(result.claims.role, "authenticated")
  }

  func testGetClaims_withProvidedJWKS_shouldStillFallbackForES256() async throws {
    // ES256 is not yet supported client-side, so it will fallback to server even with JWKS
    let jwt =
      "eyJhbGciOiJFUzI1NiIsImtpZCI6InRlc3Qta2lkIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.dummysignature"

    // JWK is Codable, no custom init needed
    let jwkDict: [String: Any] = [
      "kty": "EC",
      "kid": "test-kid",
      "alg": "ES256",
      "crv": "P-256",
      "x": "MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
      "y": "4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM",
    ]

    let jwkData = try JSONSerialization.data(withJSONObject: jwkDict)
    let jwk = try AuthClient.Configuration.jsonDecoder.decode(JWK.self, from: jwkData)
    let jwks = JWKS(keys: [jwk])

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt, options: GetClaimsOptions(jwks: jwks))

    XCTAssertEqual(result.claims.sub, "1234567890")
    XCTAssertEqual(result.claims.role, "authenticated")
  }

  func testGetClaims_withES256JWT_shouldFallbackToServerVerification() async throws {
    // ES256 JWT without kid - will fallback to server
    let jwt =
      "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.dummysignature"

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    XCTAssertEqual(result.claims.sub, "1234567890")
    XCTAssertEqual(result.claims.role, "authenticated")
  }

  func testGetClaims_withRS256JWT_whenJWKNotFound_shouldFallbackToServerVerification() async throws
  {
    // RS256 JWT with kid but key not in JWKS - will try to fetch JWKS, not find it, then fallback to server
    let jwt =
      "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2lkIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.dummysignature"

    // Mock JWKS endpoint with different kid
    let jwkDict: [String: Any] = [
      "kty": "RSA",
      "kid": "different-kid",
      "alg": "RS256",
      "n": "modulus",
      "e": "AQAB",
    ]
    let jwkData = try JSONSerialization.data(withJSONObject: jwkDict)
    let jwk = try AuthClient.Configuration.jsonDecoder.decode(JWK.self, from: jwkData)
    let jwks = JWKS(keys: [jwk])

    Mock(
      url: clientURL.appendingPathComponent(".well-known/jwks.json"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(jwks)]
    ).register()

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    XCTAssertEqual(result.claims.sub, "1234567890")
    XCTAssertEqual(result.claims.role, "authenticated")
  }

  func testGetClaims_withNoKidInHeader_shouldFallbackToServerVerification() async throws {
    // JWT without kid - cannot look up in JWKS
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5ODc2NTQzMjEiLCJpc3MiOiJodHRwOi8vbG9jYWxob3N0OjU0MzIxL2F1dGgvdjEiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.YT0NvH-jYKCiN-wrAVcMmTIxZkQ3OtqTVFjJAqGcRuw"

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    XCTAssertEqual(result.claims.sub, "987654321")
    XCTAssertEqual(result.claims.role, "authenticated")
  }

  func testGetClaims_withoutJWTAndNoSession_shouldThrowSessionMissing() async throws {
    let sut = makeSUT()

    do {
      _ = try await sut.getClaims()
      XCTFail("Expected sessionMissing error")
    } catch let error as AuthError {
      guard case .sessionMissing = error else {
        XCTFail("Expected sessionMissing error, got \(error)")
        return
      }
    } catch {
      XCTFail("Expected AuthError, got \(error)")
    }
  }

  func testGetClaims_withInvalidJWTStructure_shouldThrowJWTVerificationFailed() async throws {
    let invalidJWT = "invalid.jwt.token"

    let sut = makeSUT()

    do {
      _ = try await sut.getClaims(jwt: invalidJWT)
      XCTFail("Expected jwtVerificationFailed error")
    } catch let error as AuthError {
      guard case .jwtVerificationFailed(let message) = error else {
        XCTFail("Expected jwtVerificationFailed error, got \(error)")
        return
      }
      XCTAssertEqual(message, "Invalid JWT structure")
    } catch {
      XCTFail("Expected AuthError, got \(error)")
    }
  }

  func testGetClaims_withExpiredJWT_shouldThrowJWTVerificationFailed() async throws {
    // JWT with exp in the past
    let expiredJWT =
      "eyJhbGciOiJFUzI1NiIsImtpZCI6InRlc3Qta2lkIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MTUxNjIzOTAyMiwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.MEYCIQDmtLy0PF_lR7rJQHyKLmJKp1xFKECfVvGTBcXiVnz0jAIhAOoXZJ3kHSA2MqL1XhcUy8dWOZCr6zWCN_FXsP8qKfPR"

    let sut = makeSUT()

    do {
      _ = try await sut.getClaims(jwt: expiredJWT)
      XCTFail("Expected jwtVerificationFailed error")
    } catch let error as AuthError {
      guard case .jwtVerificationFailed(let message) = error else {
        XCTFail("Expected jwtVerificationFailed error, got \(error)")
        return
      }
      XCTAssertEqual(message, "JWT has expired")
    } catch {
      XCTFail("Expected AuthError, got \(error)")
    }
  }

  func testGetClaims_withExpiredJWTAndAllowExpired_shouldReturnClaims() async throws {
    // JWT with exp in the past but allowExpired option - falls back to server
    let expiredJWT =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MTUxNjIzOTAyMiwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.aN0HLYHkp7nKZp4xWvBaDqSrCFBxk2tq0KZc4BXGqYs"

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.getClaims(
      jwt: expiredJWT,
      options: GetClaimsOptions(allowExpired: true)
    )

    XCTAssertEqual(result.claims.sub, "1234567890")
    XCTAssertEqual(result.claims.exp, 1_516_239_022)
  }

  func testGetClaims_whenServerRejectsJWT_shouldThrowError() async throws {
    // HS256 JWT that will be verified server-side
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 401,
      data: [
        .get: try! AuthClient.Configuration.jsonEncoder.encode([
          "error": "invalid_token",
          "error_description": "Invalid JWT",
        ])
      ]
    ).register()

    let sut = makeSUT()

    do {
      _ = try await sut.getClaims(jwt: jwt)
      XCTFail("Expected error from server")
    } catch {
      // Expected to fail
    }
  }

  func testGetClaims_withComplexClaims_shouldDecodeAllFields() async throws {
    // JWT with multiple claim fields
    // HS256 so it falls back to server verification
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJuYmYiOjE1MTYyMzkwMjIsImp0aSI6InRlc3QtanRpIiwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJwaG9uZSI6IisxMjM0NTY3ODkwIn0.dBYm1Y-TfRjPsxw_gXqHB5zGHSH9hXS0OeFN_wL8HbA"

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    XCTAssertEqual(result.claims.sub, "1234567890")
    XCTAssertEqual(result.claims.iss, "http://localhost:54321/auth/v1")
    if case .string(let aud) = result.claims.aud {
      XCTAssertEqual(aud, "authenticated")
    } else {
      XCTFail("Expected string audience")
    }
    XCTAssertEqual(result.claims.exp, 9_999_999_999)
    XCTAssertEqual(result.claims.iat, 1_516_239_022)
    XCTAssertEqual(result.claims.nbf, 1_516_239_022)
    XCTAssertEqual(result.claims.jti, "test-jti")
    XCTAssertEqual(result.claims.role, "authenticated")
    XCTAssertEqual(result.claims.email, "test@example.com")
    XCTAssertEqual(result.claims.phone, "+1234567890")
  }

  func testGetClaims_withArrayAudience_shouldDecodeCorrectly() async throws {
    // JWT with audience as array
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjpbImF1dGhlbnRpY2F0ZWQiLCJzZXJ2aWNlLXJvbGUiXSwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.Jz-lHQoR2VsQ_vX8wKyN7mPxT4aU9cF1bYsHqGdWlIk"

    let user = User(fromMockNamed: "user")

    Mock(
      url: clientURL.appendingPathComponent("user"),
      ignoreQuery: true,
      contentType: .json,
      statusCode: 200,
      data: [.get: try! AuthClient.Configuration.jsonEncoder.encode(user)]
    ).register()

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    XCTAssertEqual(result.claims.sub, "1234567890")
    XCTAssertNotNil(result.claims.aud)
  }

  private func makeSUT(flowType: AuthFlowType = .pkce, emitLocalSessionAsInitialSession: Bool = false) -> AuthClient {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: sessionConfiguration)

    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = [.sortedKeys]

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: [
        "apikey":
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
      ],
      flowType: flowType,
      localStorage: storage,
      logger: nil,
      encoder: encoder,
      fetch: { request in
        try await session.data(for: request)
      },
      emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
    )

    let sut = AuthClient(configuration: configuration)

    Dependencies[sut.clientID].pkce.generateCodeVerifier = {
      "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
    }

    Dependencies[sut.clientID].pkce.generateCodeChallenge = { _ in
      "hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY"
    }

    return sut
  }

  /// Convenience method for testing auth state changes and asserting events
  /// - Parameters:
  ///   - sut: The AuthClient instance to monitor
  ///   - action: The async action to perform that should trigger events
  ///   - expectedEvents: Array of expected AuthChangeEvent values
  ///   - expectedSessions: Array of expected Session values (optional)
  @discardableResult
  private func assertAuthStateChanges<T>(
    sut: AuthClient,
    action: () async throws -> T,
    expectedEvents: [AuthChangeEvent],
    expectedSessions: [Session?]? = nil,
    timeout: TimeInterval = 2,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws -> T {
    let receivedEvents = LockIsolated([(event: AuthChangeEvent, session: Session?)]())
    let finished = LockIsolated(false)

    Task {
      for await change in sut.authStateChanges {
        if finished.value {
          XCTFail("Received event '\(change.event)' after it finished.", file: filePath, line: line)
        }
        receivedEvents.withValue { $0.append(change) }
      }
    }

    await Task.megaYield()

    let result = try await action()

    try await withTimeout(interval: timeout) {
      defer { finished.setValue(true) }
      while receivedEvents.count < expectedEvents.count {
        await Task.yield()
      }
    }

    await Task.megaYield()

    expectNoDifference(
      receivedEvents.value.map(\.event),
      expectedEvents,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )

    if let expectedSessions = expectedSessions {
      expectNoDifference(
        receivedEvents.value.map(\.session),
        expectedSessions,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
    }

    return result
  }
}

extension HTTPResponse {
  static func stub(
    _ body: String = "",
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> HTTPResponse {
    HTTPResponse(
      data: body.data(using: .utf8)!,
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: headers
      )!
    )
  }

  static func stub(
    fromFileName fileName: String,
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> HTTPResponse {
    HTTPResponse(
      data: json(named: fileName),
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: headers
      )!
    )
  }

  static func stub(
    _ value: some Encodable,
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> HTTPResponse {
    HTTPResponse(
      data: try! AuthClient.Configuration.jsonEncoder.encode(value),
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: headers
      )!
    )
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
}
