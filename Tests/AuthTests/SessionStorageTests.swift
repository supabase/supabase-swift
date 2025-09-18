import ConcurrencyExtras
import Mocker
import TestHelpers
import XCTest

@testable import Auth

final class SessionStorageTests: XCTestCase {
  fileprivate var sessionStorage: SessionStorage!
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
    sessionStorage = SessionStorage.live(clientID: sut.clientID)
  }

  override func tearDown() {
    super.tearDown()
    sut = nil
    storage = nil
    sessionStorage = nil
  }

  // MARK: - Core SessionStorage Tests

  func testSessionStorageInitialization() {
    // Given: A client ID
    let clientID = sut.clientID

    // When: Creating a session storage
    let storage = SessionStorage.live(clientID: clientID)

    // Then: Should be initialized
    XCTAssertNotNil(storage)
  }

  func testSessionStorageStoreAndGet() async throws {
    // Given: A session
    let session = Session.validSession

    // When: Storing the session
    sessionStorage.store(session)

    // Then: Should retrieve the same session
    let retrievedSession = sessionStorage.get()
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, session.accessToken)
    XCTAssertEqual(retrievedSession?.refreshToken, session.refreshToken)
    XCTAssertEqual(retrievedSession?.user.id, session.user.id)
  }

  func testSessionStorageDelete() async throws {
    // Given: A stored session
    let session = Session.validSession
    sessionStorage.store(session)
    XCTAssertNotNil(sessionStorage.get())

    // When: Deleting the session
    sessionStorage.delete()

    // Then: Should return nil
    let retrievedSession = sessionStorage.get()
    XCTAssertNil(retrievedSession)
  }

  func testSessionStorageUpdate() async throws {
    // Given: A stored session
    let originalSession = Session.validSession
    sessionStorage.store(originalSession)

    // When: Updating with a new session
    var updatedSession = Session.validSession
    updatedSession.accessToken = "new_access_token"
    sessionStorage.store(updatedSession)

    // Then: Should retrieve the updated session
    let retrievedSession = sessionStorage.get()
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, "new_access_token")
    XCTAssertNotEqual(retrievedSession?.accessToken, originalSession.accessToken)
  }

  func testSessionStorageWithExpiredSession() async throws {
    // Given: An expired session
    var expiredSession = Session.validSession
    expiredSession.expiresAt = Date().timeIntervalSince1970 - 3600  // 1 hour ago
    sessionStorage.store(expiredSession)

    // When: Getting the session
    let retrievedSession = sessionStorage.get()

    // Then: Should still return the session (storage doesn't validate expiration)
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, expiredSession.accessToken)
    XCTAssertTrue(retrievedSession?.isExpired == true)
  }

  func testSessionStorageWithValidSession() async throws {
    // Given: A valid session
    var validSession = Session.validSession
    validSession.expiresAt = Date().timeIntervalSince1970 + 3600  // 1 hour from now
    sessionStorage.store(validSession)

    // When: Getting the session
    let retrievedSession = sessionStorage.get()

    // Then: Should return the valid session
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, validSession.accessToken)
    XCTAssertTrue(retrievedSession?.isExpired == false)
  }

  func testSessionStorageWithNilSession() async throws {
    // Given: No session stored
    sessionStorage.delete()

    // When: Getting the session
    let retrievedSession = sessionStorage.get()

    // Then: Should return nil
    XCTAssertNil(retrievedSession)
  }

  func testSessionStoragePersistence() async throws {
    // Given: A session
    let session = Session.validSession

    // When: Storing the session
    sessionStorage.store(session)

    // And: Creating a new session storage instance
    let newSessionStorage = SessionStorage.live(clientID: sut.clientID)

    // Then: Should still retrieve the session (persistence through localStorage)
    let retrievedSession = newSessionStorage.get()
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, session.accessToken)
  }

  func testSessionStorageConcurrentAccess() async throws {
    // Given: A session storage
    let session = Session.validSession

    // When: Accessing storage concurrently
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<10 {
        group.addTask {
          self.sessionStorage.store(session)
        }
      }
    }

    // Then: Should still work correctly
    let retrievedSession = sessionStorage.get()
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, session.accessToken)
  }

  func testSessionStorageWithDifferentClientIDs() async throws {
    // Given: Two different auth clients with separate storage
    let storage1 = InMemoryLocalStorage()
    let storage2 = InMemoryLocalStorage()

    let sut1 = makeSUTWithStorage(storage1)
    let sut2 = makeSUTWithStorage(storage2)

    // And: Two session storage instances
    let sessionStorage1 = SessionStorage.live(clientID: sut1.clientID)
    let sessionStorage2 = SessionStorage.live(clientID: sut2.clientID)

    // When: Storing sessions in different storages
    var session1 = Session.validSession
    var session2 = Session.expiredSession

    // Make sure they have different access tokens
    session1.accessToken = "access_token_1"
    session2.accessToken = "access_token_2"

    sessionStorage1.store(session1)
    sessionStorage2.store(session2)

    // Then: Each storage should have its own session
    let retrieved1 = sessionStorage1.get()
    let retrieved2 = sessionStorage2.get()

    XCTAssertNotNil(retrieved1)
    XCTAssertNotNil(retrieved2)
    XCTAssertEqual(retrieved1?.accessToken, session1.accessToken)
    XCTAssertEqual(retrieved2?.accessToken, session2.accessToken)
    XCTAssertNotEqual(retrieved1?.accessToken, retrieved2?.accessToken)
  }

  func testSessionStorageDeleteAll() async throws {
    // Given: Multiple sessions stored
    let session1 = Session.validSession
    let session2 = Session.expiredSession

    sessionStorage.store(session1)
    sessionStorage.delete()
    sessionStorage.store(session2)

    // When: Deleting all sessions
    sessionStorage.delete()

    // Then: Should return nil
    let retrievedSession = sessionStorage.get()
    XCTAssertNil(retrievedSession)
  }

  func testSessionStorageWithLargeSession() async throws {
    // Given: A session with large user metadata
    var session = Session.validSession
    var largeMetadata: [String: AnyJSON] = [:]

    // Create large metadata
    for i in 0..<1000 {
      largeMetadata["key_\(i)"] = .string("value_\(i)")
    }

    session.user.userMetadata = largeMetadata
    sessionStorage.store(session)

    // When: Getting the session
    let retrievedSession = sessionStorage.get()

    // Then: Should handle large sessions correctly
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, session.accessToken)
    XCTAssertEqual(retrievedSession?.user.userMetadata.count, largeMetadata.count)
  }

  func testSessionStorageWithSpecialCharacters() async throws {
    // Given: A session with special characters in tokens
    var session = Session.validSession
    session.accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    session.refreshToken = "refresh_token_with_special_chars_!@#$%^&*()_+-=[]{}|;':\",./<>?"

    sessionStorage.store(session)

    // When: Getting the session
    let retrievedSession = sessionStorage.get()

    // Then: Should handle special characters correctly
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, session.accessToken)
    XCTAssertEqual(retrievedSession?.refreshToken, session.refreshToken)
  }

  // MARK: - Integration Tests

  func testSessionStorageIntegrationWithAuthClient() async throws {
    // Given: An auth client
    let session = Session.validSession

    // When: Storing session through auth client dependencies
    Dependencies[sut.clientID].sessionStorage.store(session)

    // Then: Should be accessible through session storage
    let retrievedSession = sessionStorage.get()
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, session.accessToken)
  }

  func testSessionStorageIntegrationWithSessionManager() async throws {
    // Given: A session manager
    let sessionManager = SessionManager.live(clientID: sut.clientID)
    let session = Session.validSession

    // When: Updating session through session manager
    await sessionManager.update(session)

    // Then: Should be accessible through session storage
    let retrievedSession = sessionStorage.get()
    XCTAssertNotNil(retrievedSession)
    XCTAssertEqual(retrievedSession?.accessToken, session.accessToken)
  }

  func testSessionStorageIntegrationWithSignOut() async throws {
    // Given: A stored session
    let session = Session.validSession
    sessionStorage.store(session)
    XCTAssertNotNil(sessionStorage.get())

    // And: Mock sign out response
    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/logout")!,
      ignoreQuery: true,
      statusCode: 204,
      data: [.post: Data()]
    ).register()

    // When: Signing out
    try await sut.signOut()

    // Then: Session should be removed from storage
    let retrievedSession = sessionStorage.get()
    XCTAssertNil(retrievedSession)
  }

  // MARK: - Helper Methods

  private func makeSUT(flowType: AuthFlowType = .pkce) -> AuthClient {
    return makeSUTWithStorage(storage, flowType: flowType)
  }

  private func makeSUTWithStorage(_ storage: InMemoryLocalStorage, flowType: AuthFlowType = .pkce)
    -> AuthClient
  {
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

    Dependencies[sut.clientID].pkce.generateCodeVerifier = {
      "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
    }

    Dependencies[sut.clientID].pkce.generateCodeChallenge = { _ in
      "hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY"
    }

    return sut
  }
}

// MARK: - Test Constants

// Using the existing clientURL from Mocks.swift
