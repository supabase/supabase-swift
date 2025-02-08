////
////  SessionManagerTests.swift
////
////
////  Created by Guilherme Souza on 23/10/23.
////
//
//import ConcurrencyExtras
//import CustomDump
//import Helpers
//import InlineSnapshotTesting
//import Mocker
//import TestHelpers
//import XCTest
//import XCTestDynamicOverlay
//
//@testable import Auth
//
//final class SessionManagerTests: XCTestCase {
//  var client: AuthClient!
//  var sut: SessionManager!
//
//  override func setUp() {
//    super.setUp()
//
//    let configuration = URLSessionConfiguration.default
//    configuration.protocolClasses = [MockingURLProtocol.self]
//    let session = URLSession(configuration: configuration)
//    client = AuthClient(
//      configuration: AuthClient.Configuration(
//        localStorage: InMemoryLocalStorage(),
//        fetch: { try await session.data(for: $0) }
//      )
//    )
//
//    sut = SessionManager.live(client: client)
//  }
//
//  override func invokeTest() {
//    withMainSerialExecutor {
//      super.invokeTest()
//    }
//  }
//
//  func testSession_shouldFailWithSessionNotFound() async {
//    do {
//      _ = try await sut.session()
//      XCTFail("Expected a \(AuthError.sessionMissing) failure")
//    } catch {
//      assertInlineSnapshot(of: error, as: .dump) {
//        """
//        - AuthError.sessionMissing
//
//        """
//      }
//    }
//  }
//
//  func testSession_shouldReturnValidSession() async throws {
//    let session = Session.validSession
//    client.sessionStorage.store(session)
//
//    let returnedSession = try await sut.session()
//    expectNoDifference(returnedSession, session)
//  }
//
//  func testSession_shouldRefreshSession_whenCurrentSessionExpired() async throws {
//    let currentSession = Session.expiredSession
//    client.sessionStorage.store(currentSession)
//
//    let validSession = Session.validSession
//
//    let refreshSessionCallCount = LockIsolated(0)
//
//    let (refreshSessionStream, refreshSessionContinuation) = AsyncStream<Session>.makeStream()
//
//    var mock = Mock(
//      url: URL(string: "http://localhost")!,
//      statusCode: 200,
//      data: [.post: Data()]
//    )
//
//    mock.onRequestHandler = OnRequestHandler(callback: {
//      refreshSessionCallCount.withValue { $0 += 1 }
//    })
//
//    mock.register()
//    //
//    //    await http.when(
//    //      { $0.url.path.contains("/token") },
//    //      return: { _ in
//    //
//    //        let session = await refreshSessionStream.first(where: { _ in true })!
//    //        return .stub(session)
//    //      }
//    //    )
//
//    // Fire N tasks and call sut.session()
//    let tasks = (0..<10).map { _ in
//      Task { [weak self] in
//        try await self?.sut.session()
//      }
//    }
//
//    await Task.yield()
//
//    refreshSessionContinuation.yield(validSession)
//    refreshSessionContinuation.finish()
//
//    // Await for all tasks to complete.
//    var result: [Result<Session?, Error>] = []
//    for task in tasks {
//      let value = await task.result
//      result.append(value)
//    }
//
//    // Verify that refresher and storage was called only once.
//    XCTAssertEqual(refreshSessionCallCount.value, 1)
//    XCTAssertEqual(try result.map { try $0.get() }, (0..<10).map { _ in validSession })
//  }
//}
