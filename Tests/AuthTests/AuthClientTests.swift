//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

@testable import _Helpers
import ConcurrencyExtras
import TestHelpers
import XCTest

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthClientTests: XCTestCase {
  var eventEmitter: Auth.EventEmitter!
  var sessionManager: SessionManager!

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
      codeVerifierStorage: .mock,
      api: api,
      eventEmitter: eventEmitter,
      sessionStorage: .mock,
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
