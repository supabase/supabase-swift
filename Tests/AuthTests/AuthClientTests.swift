//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import InlineSnapshotTesting
import Mocker
import SnapshotTestingCustomDump
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite final class AuthClientTests {
  deinit {
    Mocker.removeAll()
  }

  @Test("Auth client initializes with correct configuration")
  func testAuthClientInitialization() async {
    let client = await makeSUT()
    let config = await client.configuration

    assertInlineSnapshot(of: config.headers, as: .customDump) {
      """
      [
        "X-Client-Info": "auth-swift/0.0.0",
        "X-Supabase-Api-Version": "2024-01-01",
        "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
      ]
      """
    }

    let client2 = await makeSUT()
    let clientID1 = await client.clientID
    let clientID2 = await client2.clientID

    #expect(clientID1 < clientID2, "Should increase client IDs")
  }

  @Test("Auth state changes are properly emitted")
  func testOnAuthStateChanges() async throws {
    let session = Session.validSession
    let sut = await makeSUT()
    await sut.sessionStorage.store(session)

    let events = LockIsolated([AuthChangeEvent]())

    let handle = await sut.onAuthStateChange { event, _ in
      events.withValue {
        $0.append(event)
      }
    }

    expectNoDifference(events.value, [.initialSession])

    handle.remove()
  }

  @Test("Auth state changes stream works correctly")
  func testAuthStateChanges() async throws {
    let session = Session.validSession
    let sut = await makeSUT()
    await sut.sessionStorage.store(session)

    let stateChange = await sut.authStateChanges.first { _ in true }
    expectNoDifference(stateChange?.event, .initialSession)
    expectNoDifference(stateChange?.session, session)
  }

  @Test("Sign out works correctly and emits proper events")
  func testSignOut() async throws {
    Mock(
      url: clientURL.appendingPathComponent("logout"),
      ignoreQuery: true,
      statusCode: 204,
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

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

  @Test("Sign out with others scope should not remove local session")
  func testSignOutWithOthersScopeShouldNotRemoveLocalSession() async throws {
    Mock(
      url: clientURL.appendingPathComponent("logout").appendingQueryItems([
        URLQueryItem(name: "scope", value: "others")
      ]),
      statusCode: 204,
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

    try await sut.signOut(scope: .others)

    let sessionRemoved = await sut.sessionStorage.get() == nil
    #expect(!sessionRemoved)
  }

  @Test("Sign out should remove session if user is not found")
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

    let sut = await makeSUT()

    let validSession = Session.validSession
    await sut.sessionStorage.store(validSession)

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    try await sut.signOut()

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    expectNoDifference(events, [.initialSession, .signedOut])
    expectNoDifference(sessions, [.validSession, nil])

    let sessionRemoved = await sut.sessionStorage.get() == nil
    #expect(sessionRemoved)
  }

  @Test("Sign out should remove session if JWT is invalid")
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

    let sut = await makeSUT()

    let validSession = Session.validSession
    await sut.sessionStorage.store(validSession)

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    try await sut.signOut()

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    expectNoDifference(events, [.initialSession, .signedOut])
    expectNoDifference(sessions, [validSession, nil])

    let sessionRemoved = await sut.sessionStorage.get() == nil
    #expect(sessionRemoved)
  }

  @Test("Sign out should remove session if 403 is returned")
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

    let sut = await makeSUT()

    let validSession = Session.validSession
    await sut.sessionStorage.store(validSession)

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    try await sut.signOut()

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    expectNoDifference(events, [.initialSession, .signedOut])
    expectNoDifference(sessions, [validSession, nil])

    let sessionRemoved = await sut.sessionStorage.get() == nil
    #expect(sessionRemoved)
  }

  @Test("Sign in anonymously works correctly")
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

    let sut = await makeSUT()

    try await assertAuthStateChanges(
      sut: sut,
      action: { try await sut.signInAnonymously() },
      expectedEvents: [.initialSession, .signedIn],
      expectedSessions: [nil, session]
    )

    let currentSession = await sut.currentSession
    let currentUser = await sut.currentUser
    expectNoDifference(currentSession, session)
    expectNoDifference(currentUser, session.user)
  }

  @Test("Sign in with OAuth works correctly")
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

    let sut = await makeSUT()

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

  @Test("Get link identity URL works correctly")
  func testGetLinkIdentityURL() async throws {
    let url =
      "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
    let sut = await makeSUT()

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

    await sut.sessionStorage.store(.validSession)

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

  @Test("Link identity works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

    let receivedURL = LockIsolated<URL?>(nil)

    await sut.overrideForTesting {
      $0.urlOpener.open = { url in
        receivedURL.setValue(url)
      }
    }

    try await sut.linkIdentity(provider: .github)

    expectNoDifference(receivedURL.value?.absoluteString, url)
  }

  @Test("Link identity with ID token works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

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

    let currentSession = await sut.currentSession
    expectNoDifference(currentSession, updatedSession)
  }

  @Test("Admin list users works correctly")
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

    let sut = await makeSUT()

    let response = try await sut.admin.listUsers()
    expectNoDifference(response.total, 669)
    expectNoDifference(response.nextPage, 2)
    expectNoDifference(response.lastPage, 14)
  }

  @Test("Admin list users with no next page works correctly")
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

    let sut = await makeSUT()

    let response = try await sut.admin.listUsers()
    expectNoDifference(response.total, 669)
    #expect(response.nextPage == nil)
    expectNoDifference(response.lastPage, 14)
  }

  @Test("Session from URL with error works correctly")
  func testSessionFromURL_withError() async throws {
    let sut = await makeSUT()

    await sut.setCodeVerifier("code-verifier")

    let url = URL(
      string:
        "https://my.redirect.com?error=server_error&error_code=422&error_description=Identity+is+already+linked+to+another+user#error=server_error&error_code=422&error_description=Identity+is+already+linked+to+another+user"
    )!

    do {
      try await sut.session(from: url)
      Issue.record("Expect failure")
    } catch {
      assertInlineSnapshot(of: error, as: .customDump) {
        """
        AuthError.pkceGrantCodeExchange(
          message: "Identity is already linked to another user",
          error: "server_error",
          code: "422"
        )
        """
      }
    }
  }

  @Test("Sign up with email and password works correctly")
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

    let sut = await makeSUT()

    try await sut.signUp(
      email: "example@mail.com",
      password: "the.pass",
      data: ["custom_key": .string("custom_value")],
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "dummy-captcha"
    )
  }

  @Test("Sign up with phone and password works correctly")
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

    let sut = await makeSUT()

    try await sut.signUp(
      phone: "+1 202-918-2132",
      password: "the.pass",
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  @Test("Sign in with email and password works correctly")
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

    let sut = await makeSUT()

    try await sut.signIn(
      email: "example@mail.com",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  @Test("Sign in with phone and password works correctly")
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

    let sut = await makeSUT()

    try await sut.signIn(
      phone: "+1 202-918-2132",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  @Test("Sign in with ID token works correctly")
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

    let sut = await makeSUT()

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

  @Test("Sign in with OTP using email works correctly")
  func testSignInWithOTPUsingEmail() async throws {
    Mock(
      url: clientURL.appendingPathComponent("otp"),
      ignoreQuery: true,
      statusCode: 204,
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

    let sut = await makeSUT()

    try await sut.signInWithOTP(
      email: "example@mail.com",
      redirectTo: URL(string: "https://supabase.com"),
      shouldCreateUser: true,
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  @Test("Sign in with OTP using phone works correctly")
  func testSignInWithOTPUsingPhone() async throws {
    Mock(
      url: clientURL.appendingPathComponent("otp"),
      ignoreQuery: true,
      statusCode: 204,
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

    let sut = await makeSUT()

    try await sut.signInWithOTP(
      phone: "+1 202-918-2132",
      shouldCreateUser: true,
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  @Test("Get OAuth sign in URL works correctly")
  func testGetOAuthSignInURL() async throws {
    let sut = await makeSUT(flowType: .implicit)
    let url = try await sut.getOAuthSignInURL(
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

  @Test("Refresh session works correctly")
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

    let sut = await makeSUT()
    try await sut.refreshSession(refreshToken: "refresh-token")
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
    @Test("Session from URL works correctly")
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
        	--header "Authorization: Bearer accesstoken" \
        	--header "X-Client-Info: auth-swift/0.0.0" \
        	--header "X-Supabase-Api-Version: 2024-01-01" \
        	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
        	"http://localhost:54321/auth/v1/user"
        """#
      }
      .register()

      let sut = await makeSUT(flowType: .implicit)

      let currentDate = Date()

      await sut.overrideForTesting {
        $0.date = { currentDate }
      }

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

  @Test("Session with URL implicit flow works correctly")
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
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }
    .register()

    let sut = await makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
    )!
    try await sut.session(from: url)
  }

  @Test("Session with URL implicit flow handles invalid URL correctly")
  func testSessionWithURL_implicitFlow_invalidURL() async throws {
    let sut = await makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#invalid_key=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
    )!

    do {
      try await sut.session(from: url)
      Issue.record("Expected an error to be thrown, but none was thrown")
    } catch let AuthError.implicitGrantRedirect(message) {
      expectNoDifference(message, "Not a valid implicit grant flow URL: \(url)")
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test("Session with URL implicit flow handles errors correctly")
  func testSessionWithURL_implicitFlow_error() async throws {
    let sut = await makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#error_description=Invalid+code&error=invalid_grant"
    )!

    do {
      try await sut.session(from: url)
      Issue.record("Expected an error to be thrown, but none was thrown")
    } catch let AuthError.implicitGrantRedirect(message) {
      expectNoDifference(message, "Invalid code")
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test("Session with URL implicit flow recovery type works correctly")
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
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }
    .register()

    let sut = await makeSUT(flowType: .implicit)

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

  @Test("Session with URL PKCE flow handles errors correctly")
  func testSessionWithURL_pkceFlow_error() async throws {
    let sut = await makeSUT()

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
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test("Session with URL PKCE flow handles errors without description correctly")
  func testSessionWithURL_pkceFlow_error_noErrorDescription() async throws {
    let sut = await makeSUT()

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
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test("Session from URL with missing component handles correctly")
  func testSessionFromURLWithMissingComponent() async {
    let sut = await makeSUT()

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

  @Test("Set session with future expiration date works correctly")
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

    let sut = await makeSUT()
    await sut.sessionStorage.store(.validSession)

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  @Test("Set session with expired token works correctly")
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

    let sut = await makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

    try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  @Test("Verify OTP using email works correctly")
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

    let sut = await makeSUT()

    try await sut.verifyOTP(
      email: "example@mail.com",
      token: "123456",
      type: .magiclink,
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test("Verify OTP using phone works correctly")
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

    let sut = await makeSUT()

    try await sut.verifyOTP(
      phone: "+1 202-918-2132",
      token: "123456",
      type: .sms,
      captchaToken: "captcha-token"
    )
  }

  @Test("Verify OTP using token hash works correctly")
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

    let sut = await makeSUT()

    try await sut.verifyOTP(
      tokenHash: "abc-def",
      type: .email
    )
  }

  @Test("Update user works correctly")
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
      	--header "Content-Length: 258" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"code_challenge\":\"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY\",\"code_challenge_method\":\"s256\",\"data\":{\"custom_key\":\"custom_value\"},\"email\":\"example@mail.com\",\"email_change_token\":\"123456\",\"nonce\":\"abcdef\",\"password\":\"another.pass\",\"phone\":\"+1 202-918-2132\"}" \
      	"http://localhost:54321/auth/v1/user"
      """#
    }
    .register()

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

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

  @Test("Reset password for email works correctly")
  func testResetPasswordForEmail() async throws {
    Mock(
      url: clientURL.appendingPathComponent("recover"),
      ignoreQuery: true,
      statusCode: 204,
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

    let sut = await makeSUT()
    try await sut.resetPasswordForEmail(
      "example@mail.com",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test("Resend email works correctly")
  func testResendEmail() async throws {
    Mock(
      url: clientURL.appendingPathComponent("resend"),
      ignoreQuery: true,
      statusCode: 204,
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

    let sut = await makeSUT()

    try await sut.resend(
      email: "example@mail.com",
      type: .emailChange,
      emailRedirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test("Resend phone works correctly")
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

    let sut = await makeSUT()

    let response = try await sut.resend(
      phone: "+1 202-918-2132",
      type: .phoneChange,
      captchaToken: "captcha-token"
    )

    expectNoDifference(response.messageId, "12345")
  }

  @Test("Delete user works correctly")
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

    let sut = await makeSUT()
    try await sut.admin.deleteUser(id: id)
  }

  @Test("Reauthenticate works correctly")
  func testReauthenticate() async throws {
    Mock(
      url: clientURL.appendingPathComponent("reauthenticate"),
      statusCode: 204,
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

    try await sut.reauthenticate()
  }

  @Test("Unlink identity works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

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

  @Test("Sign in with SSO using domain works correctly")
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

    let sut = await makeSUT()

    let response = try await sut.signInWithSSO(
      domain: "supabase.com",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )

    expectNoDifference(response.url, URL(string: "https://supabase.com")!)
  }

  @Test("Sign in with SSO using provider ID works correctly")
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

    let sut = await makeSUT()

    let response = try await sut.signInWithSSO(
      providerId: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )

    expectNoDifference(response.url, URL(string: "https://supabase.com")!)
  }

  @Test("MFA enroll legacy works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

    let response = try await sut.mfa.enroll(
      params: MFATotpEnrollParams(
        issuer: "supabase.com",
        friendlyName: "test"
      )
    )

    expectNoDifference(response.id, "12345")
    expectNoDifference(response.type, "totp")
  }

  @Test("MFA enroll TOTP works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

    let response = try await sut.mfa.enroll(
      params: .totp(
        issuer: "supabase.com",
        friendlyName: "test"
      )
    )

    expectNoDifference(response.id, "12345")
    expectNoDifference(response.type, "totp")
  }

  @Test("MFA enroll phone works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

    let response = try await sut.mfa.enroll(
      params: .phone(
        friendlyName: "test",
        phone: "+1 202-918-2132"
      )
    )

    expectNoDifference(response.id, "12345")
    expectNoDifference(response.type, "phone")
  }

  @Test("MFA challenge works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

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

  @Test("MFA challenge with phone type works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

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

  @Test("MFA verify works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

    try await sut.mfa.verify(
      params: .init(
        factorId: factorId,
        challengeId: "123",
        code: "123456"
      )
    )
  }

  @Test("MFA unenroll works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

    let factorId = try await sut.mfa.unenroll(params: .init(factorId: "123")).factorId

    expectNoDifference(factorId, "123")
  }

  @Test("MFA challenge and verify works correctly")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(.validSession)

    try await sut.mfa.challengeAndVerify(
      params: MFAChallengeAndVerifyParams(
        factorId: factorId,
        code: code
      )
    )
  }

  @Test("MFA list factors works correctly")
  func testMFAListFactors() async throws {
    let sut = await makeSUT()

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

    await sut.sessionStorage.store(session)

    let factors = try await sut.mfa.listFactors()
    expectNoDifference(factors.totp.map(\.id), ["1"])
    expectNoDifference(factors.phone.map(\.id), ["3"])
  }

  @Test("Get authenticator assurance level when AAL and verified factor should return AAL2")
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

    let sut = await makeSUT()

    await sut.sessionStorage.store(session)

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

  @Test("Get user by ID works correctly")
  func testgetUserById() async throws {
    let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let sut = await makeSUT()

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

  @Test("Update user by ID works correctly")
  func testUpdateUserById() async throws {
    let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let sut = await makeSUT()

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

  @Test("Create user works correctly")
  func testCreateUser() async throws {
    let sut = await makeSUT()

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
  //    let sut = await makeSUT()
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

  @Test("Invite user by email works correctly")
  func testInviteUserByEmail() async throws {
    let sut = await makeSUT()

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

  private func makeSUT(flowType: AuthFlowType = .pkce) async -> AuthClient {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]

    let encoder = JSONEncoder.supabase()
    encoder.outputFormatting = [.sortedKeys]

    let configuration = AuthClient.Configuration(
      headers: [
        "apikey":
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
      ],
      flowType: flowType,
      localStorage: InMemoryLocalStorage(),
      logger: nil,
      session: .init(configuration: sessionConfiguration)
    )

    let sut = AuthClient(url: clientURL, configuration: configuration)

    await sut.overrideForTesting {
      $0.pkce.generateCodeVerifier = {
        "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
      }

      $0.pkce.generateCodeChallenge = { _ in
        "hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY"
      }
    }

    return sut
  }

  /// Convenience method for testing auth state changes and asserting events
  /// - Parameters:
  ///   - sut: The AuthClient instance to monitor
  ///   - action: The async action to perform that should trigger events
  ///   - expectedEvents: Array of expected AuthChangeEvent values
  ///   - expectedSessions: Array of expected Session values (optional)
  private func assertAuthStateChanges<T>(
    sut: AuthClient,
    action: () async throws -> T,
    expectedEvents: [AuthChangeEvent],
    expectedSessions: [Session?]? = nil,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws -> T {
    let eventsTask = Task {
      await sut.authStateChanges.prefix(expectedEvents.count).collect()
    }

    await Task.megaYield()

    let result = try await action()

    let authStateChanges = await eventsTask.value
    let events = authStateChanges.map(\.event)
    let sessions = authStateChanges.map(\.session)

    expectNoDifference(
      events, expectedEvents, fileID: fileID, filePath: filePath, line: line, column: column)

    if let expectedSessions = expectedSessions {
      expectNoDifference(
        sessions, expectedSessions, fileID: fileID, filePath: filePath, line: line, column: column)
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
}
