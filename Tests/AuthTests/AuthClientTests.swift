//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

@testable import _Helpers
@testable import Auth
import ConcurrencyExtras
import CustomDump
import TestHelpers
import XCTest

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
    try storage.storeSession(.init(session: session))

    sut = makeSUT()

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
    sut = makeSUT()

    let session = Session.validSession
    try storage.storeSession(.init(session: session))

    let stateChange = await sut.authStateChanges.first { _ in true }
    XCTAssertNoDifference(stateChange?.event, .initialSession)
    XCTAssertNoDifference(stateChange?.session, session)
  }

  func testSignOut() async throws {
    sut = makeSUT { _ in
      .stub()
    }

    try storage.storeSession(.init(session: .validSession))

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }
    await Task.megaYield()

    try await sut.signOut()

    do {
      _ = try await sut.session
    } catch AuthError.sessionNotFound {
    } catch {
      XCTFail("Unexpected error.")
    }

    let events = await eventsTask.value.map(\.event)
    XCTAssertEqual(events, [.initialSession, .signedOut])
  }

  func testSignOutWithOthersScopeShouldNotRemoveLocalSession() async throws {
    sut = makeSUT { _ in
      .stub()
    }

    try storage.storeSession(.init(session: .validSession))

    try await sut.signOut(scope: .others)

    let sessionRemoved = try storage.getSession() == nil
    XCTAssertFalse(sessionRemoved)
  }

  func testSignOutShouldRemoveSessionIfUserIsNotFound() async throws {
    sut = makeSUT { _ in
      throw AuthError.api(AuthError.APIError(code: 404))
    }

    let validSession = Session.validSession
    try storage.storeSession(.init(session: validSession))

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    do {
      try await sut.signOut()
    } catch AuthError.api {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    XCTAssertNoDifference(events, [.initialSession, .signedOut])
    XCTAssertNoDifference(sessions, [.validSession, nil])

    let sessionRemoved = try storage.getSession() == nil
    XCTAssertTrue(sessionRemoved)
  }

  func testSignOutShouldRemoveSessionIfJWTIsInvalid() async throws {
    sut = makeSUT { _ in
      throw AuthError.api(AuthError.APIError(code: 401))
    }

    let validSession = Session.validSession
    try storage.storeSession(.init(session: validSession))

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    do {
      try await sut.signOut()
    } catch AuthError.api {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    XCTAssertNoDifference(events, [.initialSession, .signedOut])
    XCTAssertNoDifference(sessions, [validSession, nil])

    let sessionRemoved = try storage.getSession() == nil
    XCTAssertTrue(sessionRemoved)
  }

  func testSignOutShouldRemoveSessionIf403Returned() async throws {
    sut = makeSUT { _ in
      throw AuthError.api(AuthError.APIError(code: 403))
    }

    let validSession = Session.validSession
    try storage.storeSession(.init(session: validSession))

    let eventsTask = Task {
      await sut.authStateChanges.prefix(2).collect()
    }

    await Task.megaYield()

    do {
      try await sut.signOut()
    } catch AuthError.api {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let events = await eventsTask.value.map(\.event)
    let sessions = await eventsTask.value.map(\.session)

    XCTAssertNoDifference(events, [.initialSession, .signedOut])
    XCTAssertNoDifference(sessions, [validSession, nil])

    let sessionRemoved = try storage.getSession() == nil
    XCTAssertTrue(sessionRemoved)
  }

  func testSignInAnonymously() async throws {
    let session = Session(fromMockNamed: "anonymous-sign-in-response")

    let sut = makeSUT { _ in
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
    let sut = makeSUT { _ in
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

  func testSignInWithOAuthWithInvalidRedirecTo() async {
    let sut = makeSUT()

    do {
      try await sut.signInWithOAuth(
        provider: .google,
        redirectTo: nil,
        launchFlow: { _ in
          XCTFail("Should not call launchFlow.")
          return URL(string: "https://supabase.com")!
        }
      )
    } catch let error as AuthError {
      XCTAssertEqual(error, .invalidRedirectScheme)
    } catch {
      XCTFail("Unexcpted error: \(error)")
    }
  }

  func testGetLinkIdentityURL() async throws {
    let sut = makeSUT { _ in
      .stub(
        """
        {
          "url" : "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
        }
        """
      )
    }

    try storage.storeSession(.init(session: .validSession))

    let response = try await sut.getLinkIdentityURL(provider: .github)

    XCTAssertNoDifference(
      response,
      OAuthResponse(
        provider: .github,
        url: URL(string: "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt")!
      )
    )
  }

  private func makeSUT(
    fetch: ((URLRequest) async throws -> HTTPResponse)? = nil
  ) -> AuthClient {
    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: ["Apikey": "dummy.api.key"],
      localStorage: storage,
      logger: nil,
      fetch: { request in
        guard let fetch else {
          throw UnimplementedError()
        }

        let response = try await fetch(request)
        return (response.data, response.underlyingResponse)
      }
    )

    let sut = AuthClient(configuration: configuration)

    return sut
  }
}

extension HTTPResponse {
  static func stub(_ body: String = "", code: Int = 200) -> HTTPResponse {
    HTTPResponse(
      data: body.data(using: .utf8)!,
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: nil
      )!
    )
  }

  static func stub(fromFileName fileName: String, code: Int = 200) -> HTTPResponse {
    HTTPResponse(
      data: json(named: fileName),
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: nil
      )!
    )
  }
}
