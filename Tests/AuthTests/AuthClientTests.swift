//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import HTTPTypes
import InlineSnapshotTesting
import TestHelpers
import XCTest

@testable import Auth
@testable import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct Response {
  var data: Data
  var response: HTTPResponse
}

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
    sut = makeSUT { _, _ in
      .stub()
    }

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
    sut = makeSUT { _, _ in
      .stub()
    }

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.signOut(scope: .others)

    let sessionRemoved = Dependencies[sut.clientID].sessionStorage.get() == nil
    XCTAssertFalse(sessionRemoved)
  }

  func testSignOutShouldRemoveSessionIfUserIsNotFound() async throws {
    sut = makeSUT { _, _ in
      throw AuthError.api(
        message: "",
        errorCode: .unknown,
        underlyingData: Data(),
        underlyingResponse: HTTPResponse(status: .init(code: 404))
      )
    }

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
    sut = makeSUT { _, _ in
      throw AuthError.api(
        message: "",
        errorCode: .invalidCredentials,
        underlyingData: Data(),
        underlyingResponse: HTTPResponse(status: .init(code: 401))
      )
    }

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
    sut = makeSUT { _, _ in
      throw AuthError.api(
        message: "",
        errorCode: .invalidCredentials,
        underlyingData: Data(),
        underlyingResponse: HTTPResponse(status: .init(code: 403))
      )
    }

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

    let sut = makeSUT { _, _ in
      .stub(fromFileName: "anonymous-sign-in-response")
    }

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
    let sut = makeSUT { _, _ in
      .stub(fromFileName: "session")
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
    let sut = makeSUT { _, _ in
      .stub(
        """
        {
          "url" : "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
        }
        """
      )
    }

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.getLinkIdentityURL(provider: .github)

    expectNoDifference(
      response,
      OAuthResponse(
        provider: .github,
        url: URL(string: "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt")!
      )
    )
  }

  func testLinkIdentity() async throws {
    let url = "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
    let sut = makeSUT { _, _ in
      .stub(
        """
        {
          "url" : "\(url)"
        }
        """
      )
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
    let sut = makeSUT { _, _ in
      .stub(
        fromFileName: "list-users-response",
        headers: [
          "X-Total-Count": "669",
          "Link": "</admin/users?page=2&per_page=>; rel=\"next\", </admin/users?page=14&per_page=>; rel=\"last\"",
        ]
      )
    }

    let response = try await sut.admin.listUsers()
    XCTAssertEqual(response.total, 669)
    XCTAssertEqual(response.nextPage, 2)
    XCTAssertEqual(response.lastPage, 14)
  }

  func testAdminListUsers_noNextPage() async throws {
    let sut = makeSUT { _, _ in
      .stub(
        fromFileName: "list-users-response",
        headers: [
          "X-Total-Count": "669",
          "Link": "</admin/users?page=14&per_page=>; rel=\"last\"",
        ]
      )
    }

    let response = try await sut.admin.listUsers()
    XCTAssertEqual(response.total, 669)
    XCTAssertNil(response.nextPage)
    XCTAssertEqual(response.lastPage, 14)
  }

  private func makeSUT(
    fetch: ((HTTPRequest, Data?) async throws -> Response)? = nil
  ) -> AuthClient {
    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: ["Apikey": "dummy.api.key"],
      localStorage: storage,
      logger: nil,
      fetch: { request, body in
        guard let fetch else {
          throw UnimplementedError()
        }

        let response = try await fetch(request, body)
        return (response.data, response.response)
      }
    )

    let sut = AuthClient(configuration: configuration)

    return sut
  }
}

extension Response {
  static func stub(
    _ body: String = "",
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> Self {
    .init(
      data: Data(body.utf8),
      response: HTTPResponse(
        status: .init(code: code),
        headerFields: .init(headers ?? [:])
      )
    )
  }

  static func stub(
    fromFileName fileName: String,
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> Self {
    .init(
      data: json(named: fileName),
      response: HTTPResponse(
        status: .init(code: code),
        headerFields: .init(headers ?? [:])
      )
    )
  }

  static func stub(
    _ value: some Encodable,
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> Self {
    .init(
      data: try! AuthClient.Configuration.jsonEncoder.encode(value),
      response: HTTPResponse(
        status: .init(code: code),
        headerFields: .init(headers ?? [:])
      )
    )
  }
}
