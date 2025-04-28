//
//  SessionManagerTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import Helpers
import InlineSnapshotTesting
import TestHelpers
import XCTest
import XCTestDynamicOverlay

@testable import Auth

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
        autoRefreshToken: false
      ),
      http: http,
      api: APIClient(clientID: clientID),
      codeVerifierStorage: .mock,
      sessionStorage: SessionStorage.live(clientID: clientID),
      sessionManager: SessionManager.live(clientID: clientID)
    )
  }

  #if !os(Windows) && !os(Linux) && !os(Android)
    override func invokeTest() {
      withMainSerialExecutor {
        super.invokeTest()
      }
    }
  #endif

  func testSession_shouldFailWithSessionNotFound() async {
    do {
      _ = try await sut.session()
      XCTFail("Expected a \(AuthError.sessionMissing) failure")
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        - AuthError.sessionMissing

        """
      }
    }
  }

  func testSession_shouldReturnValidSession() async throws {
    let session = Session.validSession
    Dependencies[clientID].sessionStorage.store(session)

    let returnedSession = try await sut.session()
    expectNoDifference(returnedSession, session)
  }

  func testSession_shouldRefreshSession_whenCurrentSessionExpired() async throws {
    let currentSession = Session.expiredSession
    Dependencies[clientID].sessionStorage.store(currentSession)

    let validSession = Session.validSession

    let refreshSessionCallCount = LockIsolated(0)

    let (refreshSessionStream, refreshSessionContinuation) = AsyncStream<Session>.makeStream()

    await http.when(
      { $0.url.path.contains("/token") },
      return: { _ in
        refreshSessionCallCount.withValue { $0 += 1 }
        let session = await refreshSessionStream.first(where: { _ in true })!
        return .stub(session)
      }
    )

    // Fire N tasks and call sut.session()
    let tasks = (0..<10).map { _ in
      Task { [weak self] in
        try await self?.sut.session()
      }
    }

    await Task.yield()

    refreshSessionContinuation.yield(validSession)
    refreshSessionContinuation.finish()

    // Await for all tasks to complete.
    var result: [Result<Session?, Error>] = []
    for task in tasks {
      let value = await task.result
      result.append(value)
    }

    // Verify that refresher and storage was called only once.
    expectNoDifference(refreshSessionCallCount.value, 1)
    expectNoDifference(
      try result.map { try $0.get()?.accessToken },
      (0..<10).map { _ in validSession.accessToken }
    )
  }

  func testRefreshSession_shouldNotRemoveSession_whenErrorIsURLErrorCancelled() async throws {
    let currentSession = Session.validSession
    Dependencies[clientID].sessionStorage.store(currentSession)

    await http.when(
      { $0.url.path.contains("/token") },
      return: { _ in
        throw URLError(.cancelled)
      }
    )

    do {
      _ = try await sut.refreshSession(currentSession.refreshToken)
      XCTFail("Expected a \(URLError.cancelled) failure")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .cancelled)
    }

    XCTAssertNotNil(Dependencies[clientID].sessionStorage.get())
  }

  func testRefreshSession_shouldNotRemoveSession_whenErrorIsCancellationError() async throws {
    let currentSession = Session.validSession
    Dependencies[clientID].sessionStorage.store(currentSession)

    await http.when(
      { $0.url.path.contains("/token") },
      return: { _ in
        throw CancellationError()
      }
    )

    do {
      _ = try await sut.refreshSession(currentSession.refreshToken)
      XCTFail("Expected a \(CancellationError.self) failure")
    } catch is CancellationError {
      // no-op
    }

    XCTAssertNotNil(Dependencies[clientID].sessionStorage.get())
  }
}
