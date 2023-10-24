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

  func testInitialization() async throws {
    let session = Session.validSession

    let sut = makeSUT()
    sessionManager.sessionResult = .success(session)

    var events: [(AuthChangeEvent, Session?)] = []
    let handle = sut.onAuthStateChange {
      events.append(($0, $1))
    }

    await sut.initialization()

    XCTAssertIdentical(sessionManager.sessionRefresher, sut)

    XCTAssertEqual(events.count, 2)
    XCTAssertEqual(events.map(\.0), [.signedIn, .signedIn])
    XCTAssertEqual(events.map(\.1), [session, session])

    handle.unsubscribe()
  }

  func testOnAuthStateChange() async throws {
    let session = Session.validSession

    let sut = makeSUT()
    sessionManager.sessionResult = .success(session)

    await sut.initialization()

    var event: (AuthChangeEvent, Session?)?
    let expectation = self.expectation(description: "onAuthStateChange")

    let handle = sut.onAuthStateChange {
      event = ($0, $1)
      expectation.fulfill()
    }

    var listeners = await sut.authChangeListeners.value
    XCTAssertNotNil(listeners[handle.id])

    var tasks = await sut.initialSessionTasks.value
    XCTAssertNotNil(tasks[handle.id])

    await fulfillment(of: [expectation])

    XCTAssertEqual(event?.0, .signedIn)
    XCTAssertEqual(event?.1, session)

    handle.unsubscribe()

    listeners = await sut.authChangeListeners.value
    XCTAssertNil(listeners[handle.id])

    tasks = await sut.initialSessionTasks.value
    XCTAssertNil(tasks[handle.id])
  }

  private func makeSUT(fetch: GoTrueClient.FetchHandler? = nil) -> GoTrueClient {
    sessionManager = SessionManagerMock()
    let sut = GoTrueClient(
      configuration: GoTrueClient.Configuration(
        url: clientURL,
        headers: ["apikey": "dummy.api.key"],
        fetch: { request in
          if let fetch {
            return try await fetch(request)
          }

          throw UnimplementedError()
        }
      ),
      sessionManager: sessionManager
    )

    addTeardownBlock { [weak sut] in
      XCTAssertNil(sut, "sut should be deallocated.")
    }

    return sut
  }
}

private final class SessionManagerMock: SessionManager, @unchecked Sendable {
  private let lock = NSRecursiveLock()

  weak var sessionRefresher: SessionRefresher?
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
