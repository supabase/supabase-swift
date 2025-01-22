//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import Helpers
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

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  override func setUp() {
    super.setUp()
    storage = InMemoryLocalStorage()
  }

  override func tearDown() {
    super.tearDown()

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

    XCTAssertEqual(events.value, [.initialSession])

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

    sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }
    await Task.megaYield()

    try await sut.signOut()

    do {
      _ = try await sut.session
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        - AuthError.sessionMissing

        """
      }
    }

    let events = await eventsTask.value.map(\.event)
    XCTAssertEqual(events, [.initialSession, .signedOut])
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

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
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

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
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

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
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

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    try await sut.signInAnonymously()

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    XCTAssertEqual(events, [.initialSession, .signedIn])
    XCTAssertEqual(sessions, [nil, session])
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

    Dependencies[sut.clientID].pkce.generateCodeVerifier = {
      "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
    }

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

    XCTAssertEqual(events, [.initialSession, .signedIn])
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
          """.utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user/identities/authorize?code_challenge=fmVr5yVJ7LpFn9nLSHQNA_84o5r8lFy4bsH_UF_PArk&code_challenge_method=s256&provider=github&skip_http_redirect=true"
      """#
    }
    .register()

    Dependencies[sut.clientID].pkce.generateCodeChallenge = { _ in
      "fmVr5yVJ7LpFn9nLSHQNA_84o5r8lFy4bsH_UF_PArk"
    }
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
          """.utf8)
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Authorization: Bearer accesstoken" \
      	--header "X-Client-Info: auth-swift/0.0.0" \
      	--header "X-Supabase-Api-Version: 2024-01-01" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/auth/v1/user/identities/authorize?code_challenge=C8LR1RB8uGzS9GltM-Wif1p-AdVE-_fT5z0r6LV3Fps&code_challenge_method=s256&provider=github&skip_http_redirect=true"
      """#
    }
    .register()

    let sut = makeSUT()

    Dependencies[sut.clientID].pkce.generateCodeChallenge = { _ in
      "C8LR1RB8uGzS9GltM-Wif1p-AdVE-_fT5z0r6LV3Fps"
    }
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let receivedURL = LockIsolated<URL?>(nil)
    Dependencies[sut.clientID].urlOpener.open = { url in
      receivedURL.setValue(url)
    }

    try await sut.linkIdentity(provider: .github)

    XCTAssertEqual(receivedURL.value?.absoluteString, url)
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
    XCTAssertEqual(response.total, 669)
    XCTAssertEqual(response.nextPage, 2)
    XCTAssertEqual(response.lastPage, 14)
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
    XCTAssertEqual(response.total, 669)
    XCTAssertNil(response.nextPage)
    XCTAssertEqual(response.lastPage, 14)
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

  private func makeSUT() -> AuthClient {
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
      localStorage: storage,
      logger: nil,
      encoder: encoder,
      fetch: { request in
        try await session.data(for: request)
      }
    )

    let sut = AuthClient(configuration: configuration)

    return sut
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
    contentsOf: Bundle.module.url(forResource: "list-users-response", withExtension: "json")!)

  static let session = try! Data(
    contentsOf: Bundle.module.url(forResource: "session", withExtension: "json")!)

  static let anonymousSignInResponse = try! Data(
    contentsOf: Bundle.module.url(forResource: "anonymous-sign-in-response", withExtension: "json")!
  )
}
