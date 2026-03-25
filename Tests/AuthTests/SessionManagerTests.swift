//
//  SessionManagerTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import TestHelpers
import XCTest
import XCTestDynamicOverlay

@testable import Auth

final class SessionManagerTests: XCTestCase {
  var http: HTTPClientMock!

  let clientID = AuthClientID()

  var sut: SessionStateMachine {
    Dependencies[clientID].sessionMachine
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
      sessionMachine: SessionStateMachine(clientID: clientID)
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
      _ = try await sut.validSession()
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

    let returnedSession = try await sut.validSession()
    expectNoDifference(returnedSession, session)
  }

  func testRefreshCancellation_shouldRestoreUsableState() async throws {
    // Store a session that will trigger a refresh when validSession() is called.
    let currentSession = Session.expiredSession
    Dependencies[clientID].sessionStorage.store(currentSession)

    await http.when(
      { $0.url.path.contains("/token") },
      return: { _ in
        // Block until the task is cancelled; Task.sleep throws CancellationError on cancellation.
        try await Task.sleep(nanoseconds: NSEC_PER_SEC * 60)
        return .stub(Session.validSession)
      }
    )

    let sut = sut
    let refreshTask = Task {
      try await sut.validSession()
    }

    await Task.yield()

    // Cancel the in-flight refresh by removing the session.
    await sut.remove()

    // The task should have failed (CancellationError).
    do {
      _ = try await refreshTask.value
      XCTFail("Expected failure after cancellation")
    } catch {
      // Expected: any error (CancellationError) is acceptable.
    }

    // State must be cleanly unauthenticated – not stuck in .refreshing.
    do {
      _ = try await sut.validSession()
      XCTFail("Expected sessionMissing error after cancellation")
    } catch AuthError.sessionMissing {
      // Expected: state is clean.
    }

    // Recovery: a new session can be stored and retrieved (auto-refresh can proceed).
    await sut.update(Session.validSession)
    let session = try await sut.validSession()
    expectNoDifference(session, Session.validSession)
  }

  func testRefreshFailure_storageAndStateConsistentAndRecoverable() async throws {
    // Store a session that will trigger a refresh when validSession() is called.
    let currentSession = Session.expiredSession
    Dependencies[clientID].sessionStorage.store(currentSession)

    struct RefreshError: Error {}
    await http.when(
      { $0.url.path.contains("/token") },
      return: { _ in throw RefreshError() }
    )

    // validSession() triggers a refresh that fails.
    do {
      _ = try await sut.validSession()
      XCTFail("Expected refresh error")
    } catch is RefreshError {
      // Expected: the refresh error is propagated.
    }

    // State is unauthenticated after failure – validSession() throws sessionMissing.
    do {
      _ = try await sut.validSession()
      XCTFail("Expected sessionMissing after refresh failure")
    } catch AuthError.sessionMissing {
      // Expected: storage and state are consistent.
    }

    // Auto-refresh recovery: update with a new session allows validSession() to succeed.
    let newSession = Session.validSession
    await sut.update(newSession)
    let session = try await sut.validSession()
    expectNoDifference(session, newSession)
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

    // Fire N tasks and call sut.validSession()
    let tasks = (0..<10).map { _ in
      Task { [weak self] in
        try await self?.sut.validSession()
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
}
