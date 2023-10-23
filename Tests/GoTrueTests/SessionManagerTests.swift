//
//  File.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import XCTest

@testable import GoTrue

final class SessionManagerTests: XCTestCase {

  func testSession_shouldFailWithSessionNotFound() async {
    let mock = SessionStorageMock()
    let sut = DefaultSessionManager(storage: mock)

    do {
      _ = try await sut.session()
      XCTFail("Expected a \(GoTrueError.sessionNotFound) failure")
    } catch GoTrueError.sessionNotFound {
    } catch {
      XCTFail("Unexpected error \(error)")
    }
  }

  func testSession_shouldReturnValidSession() async throws {
    let mock = SessionStorageMock()
    mock.session = .success(.init(session: .validSession))

    let sut = DefaultSessionManager(storage: mock)

    let session = try await sut.session()
    XCTAssertEqual(session, .validSession)
  }

  func testSession_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    let currentSession = Session.expiredSession
    let validSession = Session.validSession

    let mock = SessionStorageMock()
    mock.session = .success(.init(session: currentSession))

    let sut = DefaultSessionManager(storage: mock)

    let sessionRefresher = SessionRefresherMock()
    sessionRefresher.refreshSessionHandler = { refreshToken in
      return validSession
    }

    await sut.setSessionRefresher(sessionRefresher)

    // Fire N tasks and call sut.session()
    let tasks = (0..<10).map { _ in
      Task.detached {
        try await sut.session()
      }
    }

    // Await for all tasks to complete.
    var result: [Result<Session, Error>] = []
    for task in tasks {
      let value = await task.result
      result.append(value)
    }

    // Verify that refresher and storage was called only once.
    XCTAssertEqual(sessionRefresher.refreshSessionCallCount, 1)
    XCTAssertEqual(mock.storeSessionCallCount, 1)
    XCTAssertEqual(try result.map { try $0.get() }, (0..<10).map { _ in validSession })
  }
}

class SessionStorageMock: SessionStorage {
  var session: Result<StoredSession, Error>?

  func getSession() throws -> StoredSession? {
    try session?.get()
  }

  var storeSessionCallCount = 0
  func storeSession(_ session: StoredSession) throws {
    storeSessionCallCount += 1
    self.session = .success(session)
  }

  func deleteSession() {
    session = nil
  }
}

class SessionRefresherMock: SessionRefresher {
  var refreshSessionCallCount = 0
  var refreshSessionHandler: ((String) async throws -> Session)!
  func refreshSession(refreshToken: String) async throws -> Session {
    refreshSessionCallCount += 1
    return try await refreshSessionHandler(refreshToken)
  }
}
