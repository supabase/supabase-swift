//
//  SessionManagerTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import _Helpers
@testable import Auth
import ConcurrencyExtras
import CustomDump
import TestHelpers
import XCTest
import XCTestDynamicOverlay

final class SessionManagerTests: XCTestCase {
  let storage = InMemoryLocalStorage()
  var sessionRefresher = SessionRefresher(refreshSession: unimplemented("refreshSession"))
  lazy var sut = SessionManager(storage: storage, sessionRefresher: sessionRefresher)

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
    try storage.storeSession(.init(session: session))

    let returnedSession = try await sut.session()
    XCTAssertNoDifference(returnedSession, session)
  }

  func testSession_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    let currentSession = Session.expiredSession

    try storage.storeSession(.init(session: currentSession))

    let validSession = Session.validSession

    let refreshSessionCallCount = LockIsolated(0)

    let (refreshSessionStream, refreshSessionContinuation) = AsyncStream<Session>.makeStream()

    sessionRefresher.refreshSession = { _ in
      refreshSessionCallCount.withValue { $0 += 1 }
      return await refreshSessionStream.first { _ in true } ?? .empty
    }

    // Fire N tasks and call sut.session()
    let tasks = (0 ..< 10).map { _ in
      Task.detached {
        try await self.sut.session()
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
