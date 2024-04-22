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
  var eventEmitter: Auth.EventEmitter!
  var sessionManager: SessionManager!

  var sessionStorage: SessionStorage!
  var codeVerifierStorage: CodeVerifierStorage!
  var api: APIClient!
  var sut: AuthClient!

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  override func setUp() {
    super.setUp()
    Current = .mock

    sessionStorage = .mock
    codeVerifierStorage = .mock
    eventEmitter = .mock
    sessionManager = .mock
    api = .mock
  }

  override func tearDown() {
    super.tearDown()

    let completion = { [weak sut] in
      XCTAssertNil(sut, "sut should not leak")
    }

    defer { completion() }

    sut = nil
    eventEmitter = nil
    sessionManager = nil
  }

  func testOnAuthStateChanges() async {
    eventEmitter = .live
    let session = Session.validSession
    sessionManager.session = { @Sendable _ in session }

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
    eventEmitter = .live
    let session = Session.validSession
    sessionManager.session = { @Sendable _ in session }

    sut = makeSUT()

    let stateChange = await sut.authStateChanges.first { _ in true }
    XCTAssertEqual(stateChange?.event, .initialSession)
    XCTAssertEqual(stateChange?.session, session)
  }

  func testSignOut() async throws {
    let emitReceivedEvents = LockIsolated<[AuthChangeEvent]>([])

    eventEmitter.emit = { @Sendable event, _, _ in
      emitReceivedEvents.withValue {
        $0.append(event)
      }
    }
    sessionManager.session = { @Sendable _ in .validSession }
    sessionManager.remove = { @Sendable in }
    api.execute = { @Sendable _ in .stub() }

    sut = makeSUT()

    try await sut.signOut()

    do {
      _ = try await sut.session
    } catch AuthError.sessionNotFound {
    } catch {
      XCTFail("Unexpected error.")
    }

    XCTAssertEqual(emitReceivedEvents.value, [.signedOut])
  }

  func testSignOutWithOthersScopeShouldNotRemoveLocalSession() async throws {
    let removeCalled = LockIsolated(false)
    sessionManager.remove = { @Sendable in removeCalled.setValue(true) }
    sessionManager.session = { @Sendable _ in .validSession }
    api.execute = { @Sendable _ in .stub() }

    sut = makeSUT()

    try await sut.signOut(scope: .others)

    XCTAssertFalse(removeCalled.value)
  }

  func testSignOutShouldRemoveSessionIfUserIsNotFound() async throws {
    let emitReceivedEvents = LockIsolated<[(AuthChangeEvent, Session?)]>([])

    eventEmitter.emit = { @Sendable event, session, _ in
      emitReceivedEvents.withValue {
        $0.append((event, session))
      }
    }

    let removeCallCount = LockIsolated(0)
    sessionManager.remove = { @Sendable in
      removeCallCount.withValue { $0 += 1 }
    }
    sessionManager.session = { @Sendable _ in .validSession }
    api.execute = { @Sendable _ in throw AuthError.api(AuthError.APIError(code: 404)) }

    sut = makeSUT()

    do {
      try await sut.signOut()
    } catch AuthError.api {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let emitedParams = emitReceivedEvents.value
    let emitedEvents = emitedParams.map(\.0)
    let emitedSessions = emitedParams.map(\.1)

    XCTAssertEqual(emitedEvents, [.signedOut])
    XCTAssertEqual(emitedSessions.count, 1)
    XCTAssertNil(emitedSessions[0])

    XCTAssertEqual(removeCallCount.value, 1)
  }

  func testSignOutShouldRemoveSessionIfJWTIsInvalid() async throws {
    let emitReceivedEvents = LockIsolated<[(AuthChangeEvent, Session?)]>([])

    eventEmitter.emit = { @Sendable event, session, _ in
      emitReceivedEvents.withValue {
        $0.append((event, session))
      }
    }

    let removeCallCount = LockIsolated(0)
    sessionManager.remove = { @Sendable in
      removeCallCount.withValue { $0 += 1 }
    }
    sessionManager.session = { @Sendable _ in .validSession }
    api.execute = { @Sendable _ in throw AuthError.api(AuthError.APIError(code: 401)) }

    sut = makeSUT()

    do {
      try await sut.signOut()
    } catch AuthError.api {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let emitedParams = emitReceivedEvents.value
    let emitedEvents = emitedParams.map(\.0)
    let emitedSessions = emitedParams.map(\.1)

    XCTAssertEqual(emitedEvents, [.signedOut])
    XCTAssertEqual(emitedSessions.count, 1)
    XCTAssertNil(emitedSessions[0])

    XCTAssertEqual(removeCallCount.value, 1)
  }

  func testSignInAnonymously() async throws {
    let emitReceivedEvents = LockIsolated<[(AuthChangeEvent, Session?)]>([])

    eventEmitter.emit = { @Sendable event, session, _ in
      emitReceivedEvents.withValue {
        $0.append((event, session))
      }
    }
    sessionManager.remove = { @Sendable in }
    sessionManager.update = { @Sendable _ in }

    api.execute = { @Sendable _ in
      .stub(
        """
        {
          "access_token" : "eyJhbGciOiJIUzI1NiIsImtpZCI6ImpIaU1GZmtNTzRGdVROdXUiLCJ0eXAiOiJKV1QifQ.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNzExOTk0NzEzLCJpYXQiOjE3MTE5OTExMTMsImlzcyI6Imh0dHBzOi8vYWp5YWdzaHV6bnV2anFoampmdG8uc3VwYWJhc2UuY28vYXV0aC92MSIsInN1YiI6ImJiZmE5MjU0LWM1ZDEtNGNmZi1iYTc2LTU2YmYwM2IwNWEwMSIsImVtYWlsIjoiIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnt9LCJ1c2VyX21ldGFkYXRhIjp7fSwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJhYWwiOiJhYWwxIiwiYW1yIjpbeyJtZXRob2QiOiJhbm9ueW1vdXMiLCJ0aW1lc3RhbXAiOjE3MTE5OTExMTN9XSwic2Vzc2lvbl9pZCI6ImMyODlmYTcwLWIzYWUtNDI1Yi05MDQxLWUyZjVhNzBlZTcyYSIsImlzX2Fub255bW91cyI6dHJ1ZX0.whBzmyMv3-AQSaiY6Fi-v_G68Q8oULhB7axImj9qOdw",
          "expires_at" : 1711994713,
          "expires_in" : 3600,
          "refresh_token" : "0xS9iJUWdXnWlCJtFiXk5A",
          "token_type" : "bearer",
          "user" : {
            "app_metadata" : {

            },
            "aud" : "authenticated",
            "created_at" : "2024-04-01T17:05:13.013312Z",
            "email" : "",
            "id" : "bbfa9254-c5d1-4cff-ba76-56bf03b05a01",
            "identities" : [

            ],
            "is_anonymous" : true,
            "last_sign_in_at" : "2024-04-01T17:05:13.018294975Z",
            "phone" : "",
            "role" : "authenticated",
            "updated_at" : "2024-04-01T17:05:13.022041Z",
            "user_metadata" : {

            }
          }
        }
        """,
        code: 200
      )
    }

    let sut = makeSUT()

    try await sut.signInAnonymously()

    let events = emitReceivedEvents.value.map(\.0)

    XCTAssertEqual(events, [.signedIn])
  }

  func testSignInWithOAuth() async throws {
    let emitReceivedEvents = LockIsolated<[(AuthChangeEvent, Session?)]>([])

    eventEmitter.emit = { @Sendable event, session, _ in
      emitReceivedEvents.withValue {
        $0.append((event, session))
      }
    }

    sessionStorage = .live
    codeVerifierStorage = .live
    sessionManager = .live

    api.execute = { @Sendable _ in
      .stub(
        """
        {
          "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6Imd1aWxoZXJtZTJAZ3Jkcy5kZXYiLCJwaG9uZSI6IiIsImFwcF9tZXRhZGF0YSI6eyJwcm92aWRlciI6ImVtYWlsIiwicHJvdmlkZXJzIjpbImVtYWlsIl19LCJ1c2VyX21ldGFkYXRhIjp7fSwicm9sZSI6ImF1dGhlbnRpY2F0ZWQifQ.4lMvmz2pJkWu1hMsBgXP98Fwz4rbvFYl4VA9joRv6kY",
          "token_type": "bearer",
          "expires_in": 3600,
          "refresh_token": "GGduTeu95GraIXQ56jppkw",
          "user": {
            "id": "f33d3ec9-a2ee-47c4-80e1-5bd919f3d8b8",
            "aud": "authenticated",
            "role": "authenticated",
            "email": "guilherme@binaryscraping.co",
            "email_confirmed_at": "2022-03-30T10:33:41.018575157Z",
            "phone": "",
            "last_sign_in_at": "2022-03-30T10:33:41.021531328Z",
            "app_metadata": {
              "provider": "email",
              "providers": [
                "email"
              ]
            },
            "user_metadata": {},
            "identities": [
              {
                "id": "f33d3ec9-a2ee-47c4-80e1-5bd919f3d8b8",
                "user_id": "f33d3ec9-a2ee-47c4-80e1-5bd919f3d8b8",
                "identity_id": "859f402d-b3de-4105-a1b9-932836d9193b",
                "identity_data": {
                  "sub": "f33d3ec9-a2ee-47c4-80e1-5bd919f3d8b8"
                },
                "provider": "email",
                "last_sign_in_at": "2022-03-30T10:33:41.015557063Z",
                "created_at": "2022-03-30T10:33:41.015612Z",
                "updated_at": "2022-03-30T10:33:41.015616Z"
              }
            ],
            "created_at": "2022-03-30T10:33:41.005433Z",
            "updated_at": "2022-03-30T10:33:41.022688Z"
          }
        }
        """
      )
    }

    let sut = makeSUT()

    try await sut.signInWithOAuth(
      provider: .google,
      redirectTo: URL(string: "supabase://auth-callback")
    ) { (url: URL) in
      URL(string: "supabase://auth-callback?code=12345") ?? url
    }

    XCTAssertEqual(emitReceivedEvents.value.map(\.0), [.signedIn])
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
    api.execute = { @Sendable _ in
      .stub(
        """
        {
          "url" : "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
        }
        """
      )
    }

    sessionManager.session = { @Sendable _ in .validSession }
    codeVerifierStorage = .live
    let sut = makeSUT()

    let response = try await sut.getLinkIdentityURL(provider: .github)

    XCTAssertNoDifference(
      response,
      OAuthResponse(
        provider: .github,
        url: URL(string: "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt")!
      )
    )
  }

  private func makeSUT() -> AuthClient {
    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: ["Apikey": "dummy.api.key"],
      localStorage: InMemoryLocalStorage(),
      logger: nil
    )

    let sut = AuthClient(
      configuration: configuration,
      sessionManager: sessionManager,
      codeVerifierStorage: codeVerifierStorage,
      api: api,
      eventEmitter: eventEmitter,
      sessionStorage: sessionStorage,
      logger: nil
    )

    return sut
  }
}

extension Response {
  static func stub(_ body: String = "", code: Int = 200) -> Response {
    Response(
      data: body.data(using: .utf8)!,
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: nil
      )!
    )
  }
}
