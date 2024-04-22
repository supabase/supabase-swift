//
//  SessionManagerTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import _Helpers
import ConcurrencyExtras
import XCTest
import XCTestDynamicOverlay

@testable import Auth

final class SessionManagerTests: XCTestCase {
  override func setUp() {
    super.setUp()

    Current = .mock
  }

  func testSession_shouldFailWithSessionNotFound() async {
    Current.sessionStorage.getSession = { nil }

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
    Current.sessionStorage.getSession = {
      .validSession
    }

    let sut = SessionManager.live

    let session = try await sut.session()
    XCTAssertEqual(session, .validSession)
  }

  func testSession_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    let currentSession = Session.expiredSession
    let validSession = Session.validSession

    let storeSessionCallCount = LockIsolated(0)
    let refreshSessionCallCount = LockIsolated(0)

    let (refreshSessionStream, refreshSessionContinuation) = AsyncStream<Session>.makeStream()

    Current.sessionStorage.getSession = {
      currentSession
    }
    Current.sessionStorage.storeSession = { _ in
      storeSessionCallCount.withValue {
        $0 += 1
      }
    }
//    Current.sessionRefresher.refreshSession = { _ in
//      refreshSessionCallCount.withValue { $0 += 1 }
//      return await refreshSessionStream.first { _ in true } ?? .empty
//    }

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
    XCTAssertEqual(storeSessionCallCount.value, 1)
    XCTAssertEqual(try result.map { try $0.get() }, (0 ..< 10).map { _ in validSession })
  }
}
