import ConcurrencyExtras
import CustomDump
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

/// The session a client reads from ``AuthClient/Configuration/localStorage`` when it is created.
@Suite
struct StoredSessionTests {
  private let key = uniqueStorageKey()

  @Test
  func currentSessionRightAfterInitIsTheStoredSession() throws {
    let localStorage = InMemoryLocalStorage()
    try localStorage.store(
      key: key, value: PersistedSessionCodec.encode(ReceivedSession(session: .valid)))

    let sut = makeSUT(localStorage)

    expectNoDifference(sut.currentSession, .valid)
    expectNoDifference(sut.currentUser, Session.valid.user)
  }

  @Test
  func currentSessionRightAfterInitIsNilWhenNothingIsStored() {
    #expect(makeSUT(InMemoryLocalStorage()).currentSession == nil)
  }

  @Test
  func storedSessionLoadsBackUnchanged() async throws {
    let localStorage = InMemoryLocalStorage()
    try await makeSUT(localStorage).seedSession(.valid)

    // Another project URL, so the client gets its own store and reads storage.
    let relaunched = makeSUT(localStorage, url: URL(string: "http://127.0.0.1")!)
    expectNoDifference(relaunched.currentSession, .valid)
    let stored = try #require(try localStorage.retrieve(key: key))
    #expect(try PersistedSessionCodec.decode(stored).isCurrentSchema)
  }

  @Test(arguments: PersistedSessionFixtures.v2Shapes)
  func rewritesAV2ShapeAsSchema1(fixture: String) throws {
    let localStorage = InMemoryLocalStorage()
    try localStorage.store(key: key, value: json(named: fixture))

    expectNoDifference(
      makeSUT(localStorage).currentSession, PersistedSessionFixtures.expectedSession)

    let stored = try #require(try localStorage.retrieve(key: key))
    expectNoDifference(
      String(decoding: stored, as: UTF8.self),
      String(decoding: json(named: PersistedSessionFixtures.schema1), as: UTF8.self)
    )
  }

  @Test
  func movesASessionFromTheLegacyKey() throws {
    let localStorage = InMemoryLocalStorage()
    try localStorage.store(
      key: PersistedSessionLoader.legacyKey,
      value: json(named: "persisted-session-v2-camel-case")
    )

    expectNoDifference(
      makeSUT(localStorage).currentSession, PersistedSessionFixtures.expectedSession)

    #expect(try localStorage.retrieve(key: PersistedSessionLoader.legacyKey) == nil)
    let stored = try #require(try localStorage.retrieve(key: key))
    #expect(try PersistedSessionCodec.decode(stored).isCurrentSchema)
  }

  @Test
  func readsStorageOnceAtInit() throws {
    let localStorage = InMemoryLocalStorage()
    let sut = makeSUT(localStorage)
    #expect(sut.currentSession == nil)

    try localStorage.store(
      key: key, value: PersistedSessionCodec.encode(ReceivedSession(session: .valid)))

    #expect(sut.currentSession == nil)
  }

  @Test
  func corruptedDataReadsAsNoSessionAndIsRemoved() async throws {
    let localStorage = InMemoryLocalStorage()
    try localStorage.store(key: key, value: Data("not-valid-json".utf8))

    let sut = makeSUT(localStorage)

    #expect(sut.currentSession == nil)
    let error = await #expect(throws: AuthError.self) { try await sut.session }
    #expect(error?.kind == .sessionMissing)
    #expect(try localStorage.retrieve(key: key) == nil)
  }

  @Test
  func unreadableStorageSurfacesOnSessionInsteadOfSigningOut() async throws {
    let localStorage = FailingLocalStorage()
    try localStorage.store(
      key: key, value: PersistedSessionCodec.encode(ReceivedSession(session: .valid)))
    localStorage.failsReads.setValue(true)

    let sut = makeSUT(localStorage)

    #expect(sut.currentSession == nil)
    #expect(sut.dependencies.sessionStore.currentStatus == .loading)
    let error = await #expect(throws: AuthError.self) { try await sut.session }
    #expect(error?.kind == .storageUnavailable)

    localStorage.failsReads.setValue(false)
    let session = try await sut.session
    expectNoDifference(session, .valid)
  }

  @Test
  func signInWhoseSessionCannotBeSavedThrows() async throws {
    let localStorage = FailingLocalStorage()
    localStorage.failsWrites.setValue(true)
    let transport = RecordingTransport { _, _ in
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(Session.valid))
    }
    let sut = makeSUT(localStorage, http: .init(transport: transport))

    let error = await #expect(throws: AuthError.self) {
      try await sut.signIn(email: "user@example.com", password: "secret")
    }

    #expect(error?.kind == .storageUnavailable)
    #expect(sut.currentSession == nil)
  }

  private func makeSUT(
    _ localStorage: any AuthLocalStorage,
    url: URL = URL(string: "http://localhost")!,
    http: HTTPClientConfiguration = .init()
  ) -> AuthClient {
    AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: key,
        localStorage: localStorage,
        http: http,
        automaticallyRefreshesToken: false
      )
    )
  }
}

/// Throws from every read while `failsReads` is set, as a locked Keychain does, and from every
/// write while `failsWrites` is set.
private final class FailingLocalStorage: AuthLocalStorage {
  private let storage = InMemoryLocalStorage()
  let failsReads = LockIsolated(false)
  let failsWrites = LockIsolated(false)

  func store(key: String, value: Data) throws {
    if failsWrites.value {
      throw AuthError(kind: .storageUnavailable, message: "locked")
    }
    try storage.store(key: key, value: value)
  }

  func retrieve(key: String) throws -> Data? {
    if failsReads.value {
      throw AuthError(kind: .storageUnavailable, message: "locked")
    }
    return try storage.retrieve(key: key)
  }

  func remove(key: String) throws {
    try storage.remove(key: key)
  }
}
