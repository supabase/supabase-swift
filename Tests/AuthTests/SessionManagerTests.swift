//
//  SessionManagerTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import XCTest
import XCTestDynamicOverlay
@_spi(Internal) import _Helpers
import ConcurrencyExtras

@testable import Auth

final class SessionManagerTests: XCTestCase {
  override func setUp() {
    super.setUp()

    Dependencies.current.setValue(.mock)
  }

  func testSession_shouldFailWithSessionNotFound() async {
    await withDependencies {
      $0.sessionStorage.getSession = { nil }
    } operation: {
      let sut = SessionManager.live

      do {
        _ = try await sut.session()
        XCTFail("Expected a \(AuthError.sessionNotFound) failure")
      } catch AuthError.sessionNotFound {
      } catch {
        XCTFail("Unexpected error \(error)")
      }
    }
  }

  func testSession_shouldReturnValidSession() async throws {
    try await withDependencies {
      $0.sessionStorage.getSession = {
        .init(session: .validSession)
      }
    } operation: {
      let sut = SessionManager.live

      let session = try await sut.session()
      XCTAssertEqual(session, .validSession)
    }
  }

  func testSession_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    let currentSession = Session.expiredSession
    let validSession = Session.validSession

    let storeSessionCallCount = LockIsolated(0)
    let refreshSessionCallCount = ActorIsolated(0)

    let (refreshSessionStream, refreshSessionContinuation) = AsyncStream<Session>.makeStream()

    try await withDependencies {
      $0.sessionStorage.getSession = {
        .init(session: currentSession)
      }
      $0.sessionStorage.storeSession = { _ in
        storeSessionCallCount.withValue {
          $0 += 1
        }
      }
      $0.sessionRefresher.refreshSession = { _ in
        await refreshSessionCallCount.withValue { $0 += 1 }
        return await refreshSessionStream.first { _ in true } ?? .empty
      }
    } operation: {
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
      let refreshSessionCallCount = await refreshSessionCallCount.value
      XCTAssertEqual(refreshSessionCallCount, 1)
      XCTAssertEqual(storeSessionCallCount.value, 1)
      XCTAssertEqual(try result.map { try $0.get() }, (0 ..< 10).map { _ in validSession })
    }
  }
}
