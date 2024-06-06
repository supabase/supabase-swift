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

  override func setUp() {
    super.setUp()

    http = HTTPClientMock()

    Current = .init(
      configuration: .init(
        url: clientURL,
        localStorage: InMemoryLocalStorage(),
        logger: nil,
        autoRefreshToken: false
      ),
      http: http
    )
  }

  override func invokeTest() {
    withMainSerialExecutor {
      super.invokeTest()
    }
  }

  func testSession_shouldFailWithSessionNotFound() async {
    let sut = SessionManager.live

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
    try Current.configuration.localStorage.storeSession(session)

    let sut = SessionManager.live

    let returnedSession = try await sut.session()
    XCTAssertNoDifference(returnedSession, session)
  }

  func testSession_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    let currentSession = Session.expiredSession
    try Current.configuration.localStorage.storeSession(currentSession)

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

    let sut = SessionManager.live

    // Fire N tasks and call sut.session()
    let tasks = (0 ..< 10).map { _ in
      Task.detached {
        try await sut.session()
      }
    }

    await Task.megaYield()

    refreshSessionContinuation.yield(validSession)
    refreshSessionContinuation.finish()

    // Await for all tasks to complete.
    var result: [Result<Session, Error>] = []
    for task in tasks {
      let value = await task.result
      result.append(value)
    }

    // Verify that refresher and storage was called only once.
    XCTAssertEqual(refreshSessionCallCount.value, 1)
    XCTAssertEqual(try result.map { try $0.get() }, (0 ..< 10).map { _ in validSession })
  }
}
