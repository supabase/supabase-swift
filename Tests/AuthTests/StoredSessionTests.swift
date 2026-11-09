import ConcurrencyExtras
import CustomDump
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

/// The session a client reads from ``AuthClient/Configuration/storage`` when it is created.
@Suite
struct StoredSessionTests {
  private let key = uniqueStorageKey()

  @Test
  func currentSessionAfterInitializationIsTheStoredSession() async throws {
    let localStorage = InMemoryTestStorage()
    try localStorage.store(
      key: key, value: PersistedSessionCodec.encode(Session.valid))

    let sut = try makeSUT(localStorage)
    await sut.initialization()

    expectNoDifference(sut.currentSession, .valid)
    expectNoDifference(sut.currentUser, Session.valid.user)
  }

  @Test
  func currentSessionAfterInitializationIsNilWhenNothingIsStored() async throws {
    let sut = try makeSUT(InMemoryTestStorage())
    await sut.initialization()

    #expect(sut.currentSession == nil)
  }

  @Test
  func storedSessionLoadsBackUnchanged() async throws {
    let localStorage = InMemoryTestStorage()
    try await makeSUT(localStorage).seedSession(.valid)

    // Another project URL, so the client gets its own store and reads storage.
    let relaunched = try makeSUT(localStorage, url: URL(string: "http://127.0.0.1")!)
    await relaunched.initialization()
    expectNoDifference(relaunched.currentSession, .valid)
    let stored = try #require(localStorage.retrieve(key: key))
    #expect(try PersistedSessionCodec.decode(stored).isCurrentSchema)
  }

  @Test(arguments: PersistedSessionFixtures.v2Shapes)
  func rewritesAV2ShapeAsSchema1(fixture: String) async throws {
    let localStorage = InMemoryTestStorage()
    try localStorage.store(key: key, value: json(named: fixture))

    let sut = try makeSUT(localStorage)
    await sut.initialization()

    expectNoDifference(sut.currentSession, PersistedSessionFixtures.expectedSession)

    let stored = try #require(localStorage.retrieve(key: key))
    expectNoDifference(
      String(decoding: stored, as: UTF8.self),
      String(decoding: json(named: PersistedSessionFixtures.schema1), as: UTF8.self)
    )
  }

  @Test
  func movesASessionFromTheLegacyKey() async throws {
    let localStorage = InMemoryTestStorage()
    try localStorage.store(
      key: PersistedSessionLoader.legacyKey,
      value: json(named: "persisted-session-v2-camel-case")
    )

    let sut = try makeSUT(localStorage)
    await sut.initialization()

    expectNoDifference(sut.currentSession, PersistedSessionFixtures.expectedSession)
    #expect(localStorage.retrieve(key: PersistedSessionLoader.legacyKey) == nil)
    let stored = try #require(localStorage.retrieve(key: key))
    #expect(try PersistedSessionCodec.decode(stored).isCurrentSchema)
  }

  @Test
  func readsStorageOnceAtInit() async throws {
    let localStorage = InMemoryTestStorage()
    let sut = try makeSUT(localStorage)
    await sut.initialization()
    #expect(sut.currentSession == nil)

    try localStorage.store(
      key: key, value: PersistedSessionCodec.encode(Session.valid))

    #expect(sut.currentSession == nil)
  }

  @Test
  func corruptedDataReadsAsNoSessionAndIsRemoved() async throws {
    let localStorage = InMemoryTestStorage()
    try localStorage.store(key: key, value: Data("not-valid-json".utf8))

    let sut = try makeSUT(localStorage)
    await sut.initialization()

    #expect(sut.currentSession == nil)
    let error = await #expect(throws: AuthError.self) { try await sut.session() }
    #expect(error?.kind == .sessionMissing)
    #expect(localStorage.retrieve(key: key) == nil)
  }

  @Test
  func unreadableStorageSurfacesOnSessionInsteadOfSigningOut() async throws {
    let localStorage = FailingLocalStorage()
    try localStorage.store(
      key: key, value: PersistedSessionCodec.encode(Session.valid))
    localStorage.failsReads.setValue(true)

    let sut = try makeSUT(localStorage)

    #expect(sut.currentSession == nil)
    #expect(sut.dependencies.sessionStore.currentStatus == .loading)
    let error = await #expect(throws: AuthError.self) { try await sut.session() }
    #expect(error?.kind == .storageUnavailable)

    localStorage.failsReads.setValue(false)
    let session = try await sut.session()
    expectNoDifference(session, .valid)
  }

  @Test
  func signInWhoseSessionCannotBeSavedThrows() async throws {
    let localStorage = FailingLocalStorage()
    localStorage.failsWrites.setValue(true)
    let transport = RecordingTransport { _, _ in
      (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(Session.valid))
    }
    let sut = try makeSUT(localStorage, http: .init(transport: transport))

    let error = await #expect(throws: AuthError.self) {
      try await sut.signIn(email: "user@example.com", password: "secret")
    }

    #expect(error?.kind == .storageUnavailable)
    #expect(sut.currentSession == nil)
  }

  private func makeSUT(
    _ localStorage: any AuthStorage,
    url: URL = URL(string: "http://localhost")!,
    http: HTTPClientConfiguration = .init()
  ) throws -> AuthClient {
    try AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: key,
        storage: localStorage,
        autoRefresh: .manual,
        http: http
      )
    )
  }
}

/// Throws from every read while `failsReads` is set, as a locked Keychain does, and from every
/// write while `failsWrites` is set.
private final class FailingLocalStorage: AuthStorage {
  private let storage = InMemoryTestStorage()
  let failsReads = LockIsolated(false)
  let failsWrites = LockIsolated(false)

  func store(key: String, value: Data) {
    storage.store(key: key, value: value)
  }

  func save(_ data: Data, key: String) async throws {
    if failsWrites.value {
      throw AuthError(kind: .storageUnavailable, message: "locked")
    }
    storage.store(key: key, value: data)
  }

  func load(key: String) async throws -> Data? {
    if failsReads.value {
      throw AuthError(kind: .storageUnavailable, message: "locked")
    }
    return storage.retrieve(key: key)
  }

  func remove(key: String) async throws {
    try await storage.remove(key: key)
  }
}
