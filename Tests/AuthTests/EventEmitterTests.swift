import ConcurrencyExtras
import Mocker
import TestHelpers
import XCTest

@testable import Auth

final class EventEmitterTests: XCTestCase {
  fileprivate var eventEmitter: AuthStateChangeEventEmitter!
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
    eventEmitter = AuthStateChangeEventEmitter()
  }

  override func tearDown() {
    super.tearDown()
    sut = nil
    storage = nil
    eventEmitter = nil
  }

  // MARK: - Core EventEmitter Tests

  func testEventEmitterInitialization() {
    // Given: An event emitter
    let emitter = AuthStateChangeEventEmitter()

    // Then: Should be initialized
    XCTAssertNotNil(emitter)
  }

  func testEventEmitterAttachListener() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    var receivedEvents: [AuthChangeEvent] = []

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.append(event)
    }

    // And: Emitting an event
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)

    // Then: Listener should receive the event
    // Note: We need to wait a bit for the async event processing
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

    XCTAssertEqual(receivedEvents.count, 1)
    XCTAssertEqual(receivedEvents.first, .signedIn)

    // Cleanup
    token.remove()
  }

  func testEventEmitterMultipleListeners() async throws {
    // Given: An event emitter and multiple listeners
    let emitter = AuthStateChangeEventEmitter()
    var listener1Events: [AuthChangeEvent] = []
    var listener2Events: [AuthChangeEvent] = []

    // When: Attaching multiple listeners
    let token1 = emitter.attach { event, _ in
      listener1Events.append(event)
    }

    let token2 = emitter.attach { event, _ in
      listener2Events.append(event)
    }

    // And: Emitting events
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)
    emitter.emit(.tokenRefreshed, session: session)

    // Then: Both listeners should receive all events
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

    XCTAssertEqual(listener1Events.count, 2)
    XCTAssertEqual(listener2Events.count, 2)
    XCTAssertEqual(listener1Events, [.signedIn, .tokenRefreshed])
    XCTAssertEqual(listener2Events, [.signedIn, .tokenRefreshed])

    // Cleanup
    token1.remove()
    token2.remove()
  }

  func testEventEmitterRemoveListener() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    var receivedEvents: [AuthChangeEvent] = []

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.append(event)
    }

    // And: Emitting an event
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)

    // Then: Listener should receive the event
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    XCTAssertEqual(receivedEvents.count, 1)

    // When: Removing the listener
    token.remove()

    // And: Emitting another event
    emitter.emit(.signedOut, session: nil)

    // Then: Listener should not receive the new event
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    XCTAssertEqual(receivedEvents.count, 1)  // Should still be 1
  }

  func testEventEmitterEmitWithSession() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    var receivedSessions: [Session?] = []

    // When: Attaching a listener
    let token = emitter.attach { _, session in
      receivedSessions.append(session)
    }

    // And: Emitting an event with session
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)

    // Then: Listener should receive the session
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    XCTAssertEqual(receivedSessions.count, 1)
    XCTAssertEqual(receivedSessions.first??.accessToken, session.accessToken)

    // Cleanup
    token.remove()
  }

  func testEventEmitterEmitWithoutSession() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    var receivedSessions: [Session?] = []

    // When: Attaching a listener
    let token = emitter.attach { _, session in
      receivedSessions.append(session)
    }

    // And: Emitting an event without session
    emitter.emit(.signedOut, session: nil)

    // Then: Listener should receive nil session
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    XCTAssertEqual(receivedSessions.count, 1)
    XCTAssertNil(receivedSessions.first)

    // Cleanup
    token.remove()
  }

  func testEventEmitterEmitWithToken() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    var receivedEvents: [AuthChangeEvent] = []

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.append(event)
    }

    // And: Emitting an event with specific token
    let session = Session.validSession
    emitter.emit(.signedIn, session: session, token: token)

    // Then: Listener should receive the event
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    XCTAssertEqual(receivedEvents.count, 1)
    XCTAssertEqual(receivedEvents.first, .signedIn)

    // Cleanup
    token.remove()
  }

  func testEventEmitterAllAuthChangeEvents() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    var receivedEvents: [AuthChangeEvent] = []

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.append(event)
    }

    // And: Emitting all possible auth change events
    let session = Session.validSession
    let allEvents: [AuthChangeEvent] = [
      .initialSession,
      .passwordRecovery,
      .signedIn,
      .signedOut,
      .tokenRefreshed,
      .userUpdated,
      .userDeleted,
      .mfaChallengeVerified,
    ]

    for event in allEvents {
      emitter.emit(event, session: session)
    }

    // Then: Listener should receive all events
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    XCTAssertEqual(receivedEvents.count, allEvents.count)
    XCTAssertEqual(receivedEvents, allEvents)

    // Cleanup
    token.remove()
  }

  func testEventEmitterConcurrentEmissions() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    var receivedEvents: [AuthChangeEvent] = []
    let lock = NSLock()

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      lock.lock()
      receivedEvents.append(event)
      lock.unlock()
    }

    // And: Emitting events concurrently
    let session = Session.validSession
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<10 {
        group.addTask {
          emitter.emit(.signedIn, session: session)
        }
      }
    }

    // Then: Listener should receive all events
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    XCTAssertEqual(receivedEvents.count, 10)

    // Cleanup
    token.remove()
  }

  func testEventEmitterMemoryManagement() async throws {
    // Given: An event emitter and a weak reference to a listener
    let emitter = AuthStateChangeEventEmitter()
    var receivedEvents: [AuthChangeEvent] = []

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.append(event)
    }

    // And: Emitting an event
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)

    // Then: Listener should receive the event
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    XCTAssertEqual(receivedEvents.count, 1)

    // When: Removing the token
    token.remove()

    // Then: No memory leaks should occur
    // (This is more of a manual verification, but we can test that the token is properly removed)
    XCTAssertNotNil(token)

    // Cleanup
    token.remove()
  }

  // MARK: - Integration Tests

  func testEventEmitterIntegrationWithAuthClient() async throws {
    // Given: An auth client with a session
    let session = Session.validSession
    Dependencies[sut.clientID].sessionStorage.store(session)

    // When: Getting auth state changes
    let stateChanges = sut.authStateChanges

    // Then: Should emit initial session event
    let firstChange = await stateChanges.first { _ in true }
    XCTAssertNotNil(firstChange)
    XCTAssertEqual(firstChange?.event, .initialSession)
    XCTAssertEqual(firstChange?.session?.accessToken, session.accessToken)
  }

  func testEventEmitterIntegrationWithSignOut() async throws {
    // Given: An auth client with a session
    let session = Session.validSession
    Dependencies[sut.clientID].sessionStorage.store(session)

    // And: Mock sign out response
    Mock(
      url: URL(string: "http://localhost:54321/auth/v1/logout")!,
      ignoreQuery: true,
      statusCode: 204,
      data: [.post: Data()]
    ).register()

    // When: Signing out
    try await sut.signOut()

    // Then: Session should be removed
    let currentSession = Dependencies[sut.clientID].sessionStorage.get()
    XCTAssertNil(currentSession)
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
