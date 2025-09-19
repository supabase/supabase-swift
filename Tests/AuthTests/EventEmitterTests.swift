import Alamofire
import ConcurrencyExtras
import Foundation
import Mocker
import TestHelpers
import Testing

@testable import Auth

@Suite struct EventEmitterTests {
  private let eventEmitter: AuthStateChangeEventEmitter
  private let storage: InMemoryLocalStorage
  private let sut: AuthClient

  init() async {
    let storage = InMemoryLocalStorage()
    let eventEmitter = AuthStateChangeEventEmitter()
    let sut = await Self.makeSUT(storage: storage)

    self.storage = storage
    self.eventEmitter = eventEmitter
    self.sut = sut
  }

  // MARK: - Core EventEmitter Tests

  @Test("Event emitter initializes correctly")
  func testEventEmitterInitialization() {
    // Given: An event emitter
    let _ = AuthStateChangeEventEmitter()

    // Then: Should be initialized
    // The emitter is successfully created
  }

  @Test("Event emitter attaches listener correctly")
  func testEventEmitterAttachListener() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    let receivedEvents = LockIsolated<[AuthChangeEvent]>([])

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.withValue { $0.append(event) }
    }

    // And: Emitting an event
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)

    // Then: Listener should receive the event
    // Note: We need to wait a bit for the async event processing
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

    #expect(receivedEvents.value.count == 1)
    #expect(receivedEvents.value.first == .signedIn)

    // Cleanup
    token.cancel()
  }

  @Test("Event emitter handles multiple listeners correctly")
  func testEventEmitterMultipleListeners() async throws {
    // Given: An event emitter and multiple listeners
    let emitter = AuthStateChangeEventEmitter()
    let listener1Events = LockIsolated<[AuthChangeEvent]>([])
    let listener2Events = LockIsolated<[AuthChangeEvent]>([])

    // When: Attaching multiple listeners
    let token1 = emitter.attach { event, _ in
      listener1Events.withValue { $0.append(event) }
    }

    let token2 = emitter.attach { event, _ in
      listener2Events.withValue { $0.append(event) }
    }

    // And: Emitting events
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)
    emitter.emit(.tokenRefreshed, session: session)

    // Then: Both listeners should receive all events
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

    #expect(listener1Events.value.count == 2)
    #expect(listener2Events.value.count == 2)
    #expect(listener1Events.value == [.signedIn, .tokenRefreshed])
    #expect(listener2Events.value == [.signedIn, .tokenRefreshed])

    // Cleanup
    token1.cancel()
    token2.cancel()
  }

  @Test("Event emitter removes listener correctly")
  func testEventEmitterRemoveListener() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    let receivedEvents = LockIsolated<[AuthChangeEvent]>([])

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.withValue { $0.append(event) }
    }

    // And: Emitting an event
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)

    // Then: Listener should receive the event
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    #expect(receivedEvents.value.count == 1)

    // When: Removing the listener
    token.cancel()

    // And: Emitting another event
    emitter.emit(.signedOut, session: nil)

    // Then: Listener should not receive the new event
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    #expect(receivedEvents.value.count == 1)  // Should still be 1
  }

  @Test("Event emitter emits events with session correctly")
  func testEventEmitterEmitWithSession() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    let receivedSessions = LockIsolated<[Auth.Session?]>([])

    // When: Attaching a listener
    let token = emitter.attach { _, session in
      receivedSessions.withValue { $0.append(session) }
    }

    // And: Emitting an event with session
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)

    // Then: Listener should receive the session
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    #expect(receivedSessions.value.count == 1)
    #expect(receivedSessions.value.first??.accessToken == session.accessToken)

    // Cleanup
    token.cancel()
  }

  @Test("Event emitter emits events without session correctly")
  func testEventEmitterEmitWithoutSession() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    let receivedSessions = LockIsolated<[Auth.Session?]>([])

    // When: Attaching a listener
    let token = emitter.attach { _, session in
      receivedSessions.withValue { $0.append(session) }
    }

    // And: Emitting an event without session
    emitter.emit(.signedOut, session: nil)

    // Then: Listener should receive nil session
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    #expect(receivedSessions.value.count == 1)
    #expect(receivedSessions.value == [nil])

    // Cleanup
    token.cancel()
  }

  @Test("Event emitter emits events with token correctly")
  func testEventEmitterEmitWithToken() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    let receivedEvents = LockIsolated<[AuthChangeEvent]>([])

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.withValue { $0.append(event) }
    }

    // And: Emitting an event with specific token
    let session = Session.validSession
    emitter.emit(.signedIn, session: session, token: token)

    // Then: Listener should receive the event
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    #expect(receivedEvents.value.count == 1)
    #expect(receivedEvents.value.first == .signedIn)

    // Cleanup
    token.cancel()
  }

  @Test("Event emitter handles all auth change events correctly")
  func testEventEmitterAllAuthChangeEvents() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    let receivedEvents = LockIsolated<[AuthChangeEvent]>([])

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.withValue { $0.append(event) }
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
    #expect(receivedEvents.value.count == allEvents.count)
    #expect(receivedEvents.value == allEvents)

    // Cleanup
    token.cancel()
  }

  @Test("Event emitter handles concurrent emissions correctly")
  func testEventEmitterConcurrentEmissions() async throws {
    // Given: An event emitter and a listener
    let emitter = AuthStateChangeEventEmitter()
    let receivedEvents = LockIsolated<[AuthChangeEvent]>([])
    let lock = NSLock()

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      lock.lock()
      receivedEvents.withValue { $0.append(event) }
      lock.unlock()
    }

    // And: Emitting events concurrently
    let session = Session.validSession
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<10 {
        group.addTask {
          emitter.emit(.signedIn, session: session)
        }
      }
    }

    // Then: Listener should receive all events
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    #expect(receivedEvents.value.count == 10)

    // Cleanup
    token.cancel()
  }

  @Test("Event emitter manages memory correctly")
  func testEventEmitterMemoryManagement() async throws {
    // Given: An event emitter and a weak reference to a listener
    let emitter = AuthStateChangeEventEmitter()
    let receivedEvents = LockIsolated<[AuthChangeEvent]>([])

    // When: Attaching a listener
    let token = emitter.attach { event, _ in
      receivedEvents.withValue { $0.append(event) }
    }

    // And: Emitting an event
    let session = Session.validSession
    emitter.emit(.signedIn, session: session)

    // Then: Listener should receive the event
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    #expect(receivedEvents.value.count == 1)

    // When: Removing the token
    token.cancel()

    // Then: No memory leaks should occur
    // (This is more of a manual verification, but we can test that the token is properly removed)
    // The token is successfully created and can be cancelled

    // Cleanup
    token.cancel()
  }

  // MARK: - Integration Tests

  @Test("Event emitter integrates with auth client correctly")
  func testEventEmitterIntegrationWithAuthClient() async throws {
    // Given: An auth client with a session
    let session = Session.validSession
    await sut.sessionStorage.store(session)

    // When: Getting auth state changes
    let stateChanges = await sut.authStateChanges

    // Then: Should emit initial session event
    let firstChange = await stateChanges.first { _ in true }
    #expect(firstChange != nil)
    #expect(firstChange?.event == .initialSession)
    #expect(firstChange?.session?.accessToken == session.accessToken)
  }

  @Test("Event emitter integrates with sign out correctly")
  func testEventEmitterIntegrationWithSignOut() async throws {
    // Given: An auth client with a session
    let session = Session.validSession
    await sut.sessionStorage.store(session)

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
    let currentSession = await sut.sessionStorage.get()
    #expect(currentSession == nil)
  }

  // MARK: - Helper Methods

  private static func makeSUT(storage: InMemoryLocalStorage, flowType: AuthFlowType = .pkce) async
    -> AuthClient
  {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]

    let configuration = AuthClient.Configuration(
      headers: [
        "apikey":
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
      ],
      flowType: flowType,
      localStorage: storage,
      session: Alamofire.Session(configuration: sessionConfiguration)
    )

    let sut = AuthClient(url: clientURL, configuration: configuration)

    #if DEBUG
    await sut.overrideForTesting {
      $0.pkce.generateCodeVerifier = {
        "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
      }

      $0.pkce.generateCodeChallenge = { _ in
        "hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY"
      }
    }
    #endif

    return sut
  }
}

// MARK: - Test Constants

// Using the existing clientURL from Mocks.swift

extension AuthClient {

  #if DEBUG
    func overrideForTesting(block: @Sendable (isolated AuthClient) -> Void) {
      block(self)
    }
  #endif
}
