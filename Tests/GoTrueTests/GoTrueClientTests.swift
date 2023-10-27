//
//  GoTrueClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import XCTest
@_spi(Internal) import _Helpers

@testable import GoTrue

final class GoTrueClientTests: XCTestCase {

  fileprivate var sessionManager: SessionManagerMock!
  fileprivate var codeVerifierStorage: CodeVerifierStorageMock!
  fileprivate var eventEmitter: DefaultEventEmitter!
  fileprivate var api: APIClient!

  func testOnAuthStateChange() async throws {
    let session = Session.validSession

    let sut = makeSUT()
    sessionManager.sessionResult = .success(session)

    let events = ActorIsolated([AuthChangeEvent]())
    let expectation = self.expectation(description: "onAuthStateChangeEnd")

    let authStateStream = await sut.onAuthStateChange()

    let streamTask = Task {
      for await event in authStateStream {
        events.withValue {
          $0.append(event)
        }

        expectation.fulfill()
      }
    }

    await fulfillment(of: [expectation])

    XCTAssertEqual(events.value, [.signedIn])

    streamTask.cancel()
  }

  private func makeSUT(fetch: GoTrueClient.FetchHandler? = nil) -> GoTrueClient {
    sessionManager = SessionManagerMock()
    codeVerifierStorage = CodeVerifierStorageMock()
    eventEmitter = DefaultEventEmitter()

    let configuration = GoTrueClient.Configuration(
      url: clientURL,
      headers: ["apikey": "dummy.api.key"],
      fetch: { request in
        if let fetch {
          return try await fetch(request)
        }

        throw UnimplementedError()
      }
    )

    api = APIClient()

    let sut = GoTrueClient(
      configuration: configuration,
      sessionManager: sessionManager,
      codeVerifierStorage: codeVerifierStorage,
      api: api,
      eventEmitter: eventEmitter,
      sessionStorage: .mock
    )

    addTeardownBlock { [weak sut] in
      XCTAssertNil(sut, "sut should be deallocated.")
    }

    return sut
  }
}

private final class SessionManagerMock: SessionManager, @unchecked Sendable {
  private let lock = NSRecursiveLock()

  var sessionRefresher: SessionRefresher?
  func setSessionRefresher(_ refresher: GoTrue.SessionRefresher?) async {
    lock.withLock {
      sessionRefresher = refresher
    }
  }

  var sessionResult: Result<Session, Error>!
  func session() async throws -> GoTrue.Session {
    try sessionResult.get()
  }

  func update(_ session: GoTrue.Session) async throws {}

  func remove() async {}
}

final class CodeVerifierStorageMock: CodeVerifierStorage {
  var codeVerifier: String?
  func getCodeVerifier() throws -> String? {
    codeVerifier
  }

  func storeCodeVerifier(_ code: String) throws {
    codeVerifier = code
  }

  func deleteCodeVerifier() throws {
    codeVerifier = nil
  }
}
