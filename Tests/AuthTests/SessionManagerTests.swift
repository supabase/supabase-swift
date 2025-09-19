//
//  SessionManagerTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import Mocker
import TestHelpers
import XCTest

@testable import Auth

final class SessionManagerTests: XCTestCase {
  fileprivate var sessionManager: SessionManager!
  fileprivate var storage: InMemoryLocalStorage!
  fileprivate var sut: AuthClient!

  #if !os(Windows) && !os(Linux) && !os(Android)
    override func invokeTest() {
      withMainSerialExecutor {
        super.invokeTest()
      }
    }
  #endif

  override func setUp() {
    super.setUp()
    storage = InMemoryLocalStorage()
    sut = makeSUT()
  }

  override func tearDown() {
    super.tearDown()
    Mocker.removeAll()
    sut = nil
    storage = nil
    sessionManager = nil
  }

  // MARK: - Core SessionManager Tests

  func testSessionManagerInitialization() {
    // Given: A client ID
    let clientID = sut.clientID

    // When: Creating a session manager
    let manager = SessionManager.live(clientID: clientID)

    // Then: Should be initialized
    XCTAssertNotNil(manager)
  }

  func testSessionManagerUpdateAndRemove() async throws {
    // Given: A session manager
    let manager = SessionManager.live(clientID: sut.clientID)
    let session = Session.validSession

    // When: Updating session
    await manager.update(session)

    // Then: Session should be stored
    let storedSession = await sut.clientID.sessionStorage.get()
    XCTAssertEqual(storedSession?.accessToken, session.accessToken)

    // When: Removing session
    await manager.remove()

    // Then: Session should be removed
    let removedSession = await sut.clientID.sessionStorage.get()
    XCTAssertNil(removedSession)
  }

  func testSessionManagerWithValidSession() async throws {
    // Given: A valid session in storage
    let session = Session.validSession
    await sut.clientID.sessionStorage.store(session)

    // When: Getting session
    let manager = SessionManager.live(clientID: sut.clientID)
    let result = try await manager.session()

    // Then: Should return the same session
    XCTAssertEqual(result.accessToken, session.accessToken)
  }

  func testSessionManagerWithMissingSession() async throws {
    // Given: No session in storage
    await sut.clientID.sessionStorage.delete()

    // When: Getting session
    let manager = SessionManager.live(clientID: sut.clientID)

    // Then: Should throw session missing error
    do {
      _ = try await manager.session()
      XCTFail("Expected error to be thrown")
    } catch {
      if case .sessionMissing = error as? AuthError {
        // Expected error
      } else {
        XCTFail("Expected sessionMissing error, got: \(error)")
      }
    }
  }

  func testSessionManagerWithExpiredSession() async throws {
    // Given: An expired session
    var expiredSession = Session.validSession
    expiredSession.expiresAt = Date().timeIntervalSince1970 - 3600  // 1 hour ago
    await sut.clientID.sessionStorage.store(expiredSession)

    // And: A mock refresh response
    let refreshedSession = Session.validSession
    let refreshResponse = try AuthClient.Configuration.jsonEncoder.encode(refreshedSession)

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: refreshResponse]
    ).register()

    // When: Getting session
    let manager = SessionManager.live(clientID: sut.clientID)
    let result = try await manager.session()

    // Then: Should return refreshed session
    XCTAssertEqual(result.accessToken, refreshedSession.accessToken)
  }

  func testSessionManagerRefreshSession() async throws {
    // Given: A mock refresh response
    let refreshedSession = Session.validSession
    let refreshResponse = try AuthClient.Configuration.jsonEncoder.encode(refreshedSession)

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: refreshResponse]
    ).register()

    // When: Refreshing session
    let manager = SessionManager.live(clientID: sut.clientID)
    let result = try await manager.refreshSession("refresh_token")

    // Then: Should return refreshed session
    XCTAssertEqual(result.accessToken, refreshedSession.accessToken)
  }

  func testSessionManagerRefreshSessionFailure() async throws {
    // Given: A mock error response
    let errorResponse = """
      {
        "error": "invalid_grant",
        "error_description": "Invalid refresh token"
      }
      """.data(using: .utf8)!

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 400,
      data: [.post: errorResponse]
    ).register()

    // When: Refreshing session
    let manager = SessionManager.live(clientID: sut.clientID)

    // Then: Should throw error
    do {
      _ = try await manager.refreshSession("invalid_token")
      XCTFail("Expected error to be thrown")
    } catch {
      // The error is wrapped in Alamofire's responseValidationFailed, but contains our AuthError
      let errorMessage = String(describing: error)
      XCTAssertTrue(
        errorMessage.contains("Invalid refresh token")
          || errorMessage.contains("invalid_grant") || error is AuthError,
        "Unexpected error: \(error)")
    }
  }

  func testSessionManagerAutoRefreshStartStop() async throws {
    // Given: A session manager
    let manager = SessionManager.live(clientID: sut.clientID)

    // When: Starting auto refresh
    await manager.startAutoRefresh()

    // Then: Should not crash
    XCTAssertNotNil(manager)

    // When: Stopping auto refresh
    await manager.stopAutoRefresh()

    // Then: Should not crash
    XCTAssertNotNil(manager)
  }

  func testSessionManagerConcurrentRefresh() async throws {
    // Given: A mock refresh response with delay
    let refreshedSession = Session.validSession
    let refreshResponse = try AuthClient.Configuration.jsonEncoder.encode(refreshedSession)

    var mock = Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: refreshResponse]
    )
    mock.delay = DispatchTimeInterval.milliseconds(50)
    mock.register()

    // When: Multiple concurrent refresh calls
    let manager = SessionManager.live(clientID: sut.clientID)
    async let refresh1 = manager.refreshSession("token1")
    async let refresh2 = manager.refreshSession("token2")

    // Then: Both should succeed
    let (result1, result2) = try await (refresh1, refresh2)
    XCTAssertEqual(result1.accessToken, result2.accessToken)
    XCTAssertEqual(result1.accessToken, refreshedSession.accessToken)
  }

  // MARK: - Integration Tests

  func testSessionManagerIntegrationWithAuthClient() async throws {
    // Given: A valid session
    let session = Session.validSession
    await sut.clientID.sessionStorage.store(session)

    // When: Getting session through auth client
    let result = try await sut.session

    // Then: Should return the same session
    XCTAssertEqual(result.accessToken, session.accessToken)
  }

  func testSessionManagerIntegrationWithExpiredSession() async throws {
    // Given: An expired session
    var expiredSession = Session.validSession
    expiredSession.expiresAt = Date().timeIntervalSince1970 - 3600
    await sut.clientID.sessionStorage.store(expiredSession)

    // And: A mock refresh response
    let refreshedSession = Session.validSession
    let refreshResponse = try AuthClient.Configuration.jsonEncoder.encode(refreshedSession)

    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/token")!,
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: refreshResponse]
    ).register()

    // When: Getting session through auth client
    let result = try await sut.session

    // Then: Should return refreshed session
    XCTAssertEqual(result.accessToken, refreshedSession.accessToken)
  }

  // MARK: - Helper Methods

  private func makeSUT(flowType: AuthFlowType = .pkce) -> AuthClient {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]

    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = [.sortedKeys]

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: [
        "apikey":
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
      ],
      flowType: flowType,
      localStorage: storage,
      logger: nil,
      encoder: encoder,
      session: .init(configuration: sessionConfiguration)
    )

    let sut = AuthClient(configuration: configuration)

    await sut.clientID.pkce.generateCodeVerifier = {
      "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
    }

    await sut.clientID.pkce.generateCodeChallenge = { _ in
      "hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY"
    }

    return sut
  }
}
