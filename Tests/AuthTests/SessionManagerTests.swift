//
//  SessionManagerTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

@testable import Auth
import ConcurrencyExtras
import CustomDump
import Helpers
import TestHelpers
import XCTest
import XCTestDynamicOverlay

final class SessionManagerTests: XCTestCase {
  var http: HTTPClientMock!

  let clientID = AuthClientID()

  var sut: SessionManager {
    Dependencies[clientID].sessionManager
  }

  override func setUp() {
    super.setUp()

    http = HTTPClientMock()

    Dependencies[clientID] = .init(
      configuration: .init(
        url: clientURL,
        localStorage: InMemoryLocalStorage(),
        logger: nil,
        autoRefreshToken: false
      ),
      http: http,
      api: APIClient(clientID: clientID),
      sessionStorage: SessionStorage.live(clientID: clientID),
      sessionManager: SessionManager.live(clientID: clientID)
    )
  }

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  func testSession_shouldFailWithSessionNotFound() async {
    do {
      _ = try await sut.session()
      XCTFail("Expected a \(AuthError.sessionNotFound) failure")
    } catch AuthError.sessionNotFound {
    } catch {
      XCTFail("Unexpected error \(error)")
    }
  }

  func testSession_shouldReturnValidSession() async throws {
    let session = Session.validSession
    try Dependencies[clientID].sessionStorage.store(session)

    let returnedSession = try await sut.session()
    XCTAssertNoDifference(returnedSession, session)
  }

  func testSession_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    let currentSession = Session.expiredSession
    try Dependencies[clientID].sessionStorage.store(currentSession)

    let validSession = Session.validSession

    let refreshSessionCallCount = LockIsolated(0)

    let (refreshSessionStream, refreshSessionContinuation) = AsyncStream<Session>.makeStream()

    http.when(
      { $0.url.path.contains("/token") },
      return: { _ in
        refreshSessionCallCount.withValue { $0 += 1 }
        let session = await refreshSessionStream.first(where: { _ in true })!
        return .stub(session)
      }
    )

    // Fire N tasks and call sut.session()
    let tasks = (0 ..< 10).map { _ in
      Task.detached { [weak self] in
        try await self?.sut.session()
      }
    }

    await Task.megaYield()

    refreshSessionContinuation.yield(validSession)
    refreshSessionContinuation.finish()

    // Await for all tasks to complete.
    var result: [Result<Session?, Error>] = []
    for task in tasks {
      let value = await task.result
      result.append(value)
    }

    // Verify that refresher and storage was called only once.
    XCTAssertEqual(refreshSessionCallCount.value, 1)
    XCTAssertEqual(try result.map { try $0.get() }, (0 ..< 10).map { _ in validSession })
  }
}
