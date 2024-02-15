//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import XCTest
@_spi(Internal) import _Helpers
import ConcurrencyExtras

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthClientTests: XCTestCase {
  var eventEmitter: MockEventEmitter!

  var sut: AuthClient!

  override func setUp() {
    super.setUp()

    eventEmitter = MockEventEmitter()
    sut = makeSUT()
  }

  override func tearDown() {
    super.tearDown()

    let completion = { [weak sut] in
      XCTAssertNil(sut, "sut should not leak")
    }

    defer { completion() }

    sut = nil
    eventEmitter = nil
  }

  func testOnAuthStateChanges() async {
    let session = Session.validSession

    let events = LockIsolated([AuthChangeEvent]())

    await withDependencies {
      $0.sessionManager.session = { @Sendable _ in session }
    } operation: {
      let handle = await sut.onAuthStateChange { event, _ in
        events.withValue {
          $0.append(event)
        }
      }
      addTeardownBlock { [weak handle] in
        XCTAssertNil(handle, "handle should be deallocated")
      }

      await Task.megaYield()

      XCTAssertEqual(events.value, [.initialSession])
    }
  }

  func testAuthStateChanges() async throws {
    let session = Session.validSession

    let events = ActorIsolated([AuthChangeEvent]())

    let (stream, continuation) = AsyncStream<Void>.makeStream()

    await withDependencies {
      $0.sessionManager.session = { @Sendable _ in session }
    } operation: {
      let authStateStream = await sut.authStateChanges

      let streamTask = Task {
        for await (event, _) in authStateStream {
          await events.withValue {
            $0.append(event)
          }

          continuation.yield()
        }
      }

      _ = await stream.first { _ in true }

      let events = await events.value
      XCTAssertEqual(events, [.initialSession])

      streamTask.cancel()
    }
  }

  func testSignOut() async throws {
    try await withDependencies {
      $0.api.execute = { _ in .stub() }
      $0.sessionManager = .live
      $0.sessionStorage = .inMemory
      try $0.sessionStorage.storeSession(StoredSession(session: .validSession))
    } operation: {
      try await sut.signOut()

      do {
        _ = try await sut.session
      } catch AuthError.sessionNotFound {
      } catch {
        XCTFail("Unexpected error.")
      }

      XCTAssertEqual(eventEmitter.emitReceivedParams.value.map(\.0), [.signedOut])
    }
  }

  func testSignOutWithOthersScopeShouldNotRemoveLocalSession() async throws {
    try await withDependencies {
      $0.api.execute = { _ in .stub() }
      $0.sessionManager = .live
      $0.sessionStorage = .inMemory
      try $0.sessionStorage.storeSession(StoredSession(session: .validSession))
    } operation: {
      try await sut.signOut(scope: .others)

      // Session should still be valid.
      _ = try await sut.session
    }
  }

  func testSignOutShouldRemoveSessionIfUserIsNotFound() async throws {
    try await withDependencies {
      $0.api.execute = { _ in throw AuthError.api(AuthError.APIError(code: 404)) }
      $0.sessionManager = .live
      $0.sessionStorage = .inMemory
      try $0.sessionStorage.storeSession(StoredSession(session: .validSession))
    } operation: {
      do {
        try await sut.signOut()
      } catch AuthError.api {
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      let emitedParams = eventEmitter.emitReceivedParams.value
      let emitedEvents = emitedParams.map(\.0)
      let emitedSessions = emitedParams.map(\.1)

      XCTAssertEqual(emitedEvents, [.signedOut])
      XCTAssertEqual(emitedSessions.count, 1)
      XCTAssertNil(emitedSessions[0])
      XCTAssertNil(try Dependencies.current.value!.sessionStorage.getSession())
    }
  }

  func testSignOutShouldRemoveSessionIfJWTIsInvalid() async throws {
    try await withDependencies {
      $0.api.execute = { _ in throw AuthError.api(AuthError.APIError(code: 401)) }
      $0.sessionManager = .live
      $0.sessionStorage = .inMemory
      try $0.sessionStorage.storeSession(StoredSession(session: .validSession))
    } operation: {
      do {
        try await sut.signOut()
      } catch AuthError.api {
      } catch {
        XCTFail("Unexpected error: \(error)")
      }

      let emitedParams = eventEmitter.emitReceivedParams.value
      let emitedEvents = emitedParams.map(\.0)
      let emitedSessions = emitedParams.map(\.1)

      XCTAssertEqual(emitedEvents, [.signedOut])
      XCTAssertEqual(emitedSessions.count, 1)
      XCTAssertNil(emitedSessions[0])
      XCTAssertNil(try Dependencies.current.value!.sessionStorage.getSession())
    }
  }

  private func makeSUT() -> AuthClient {
    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: ["Apikey": "dummy.api.key"],
      localStorage: Dependencies.localStorage,
      logger: nil
    )

    let sut = AuthClient(
      configuration: configuration,
      sessionManager: .mock,
      codeVerifierStorage: .mock,
      api: .mock,
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
