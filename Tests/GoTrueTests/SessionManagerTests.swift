//
//  File.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import XCTest
import XCTestDynamicOverlay
@_spi(Internal) import _Helpers

@testable import GoTrue

final class SessionManagerTests: XCTestCase {
  override func setUp() {
    super.setUp()

    Dependencies.current.setValue(.mock)
  }

  func testSession_shouldFailWithSessionNotFound() async {
    await withDependencies {
      $0.sessionStorage.getSession = { nil }
    } operation: {
      let sut = DefaultSessionManager()

      do {
        _ = try await sut.session()
        XCTFail("Expected a \(GoTrueError.sessionNotFound) failure")
      } catch GoTrueError.sessionNotFound {
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
      let sut = DefaultSessionManager()

      let session = try await sut.session()
      XCTAssertEqual(session, .validSession)
    }
  }

  func testSession_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    let currentSession = Session.expiredSession
    let validSession = Session.validSession

    let storeSessionCallCount = ActorIsolated(0)
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
      $0.sessionRefresher.refreshSession = { refreshToken in
        refreshSessionCallCount.withValue { $0 += 1 }
        return await refreshSessionStream.first { _ in true } ?? .empty
      }
    } operation: {
      let sut = DefaultSessionManager()

      // Fire N tasks and call sut.session()
      let tasks = (0..<10).map { _ in
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
      XCTAssertEqual(try result.map { try $0.get() }, (0..<10).map { _ in validSession })
    }
  }
}

extension EventEmitter {
  static let mock = Self(
    attachListener: unimplemented("attachListener"), emit: unimplemented("emit"))
}

extension SessionStorage {
  static let mock = Self(
    getSession: unimplemented("getSession"),
    storeSession: unimplemented("storeSession"),
    deleteSession: unimplemented("deleteSession")
  )
}

extension SessionRefresher {
  static let mock = Self(refreshSession: unimplemented("refreshSession"))
}

extension Dependencies {
  static let mock = Dependencies(
    configuration: GoTrueClient.Configuration(url: clientURL),
    sessionManager: DefaultSessionManager(),
    api: APIClient(),
    eventEmitter: .mock,
    sessionStorage: .mock,
    sessionRefresher: .mock
  )
}

func withDependencies(_ mutation: (inout Dependencies) -> Void, operation: () async throws -> Void)
  async rethrows
{
  let current = Dependencies.current.value ?? .mock
  var copy = current
  mutation(&copy)
  Dependencies.current.withValue { $0 = copy }
  defer { Dependencies.current.setValue(current) }
  try await operation()
}
