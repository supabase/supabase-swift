import ConcurrencyExtras
import Foundation
import Testing

@testable import Auth

@Suite
struct SessionStoreTests {
  private let key = "sb-project-auth-token"
  private let receivedAt = Date(timeIntervalSince1970: 1_700_000_000)

  @Test
  func loadWithNothingStoredSignsOutWithSessionMissing() async throws {
    let store = SessionStore(storage: InMemoryAuthStorage(), key: key)
    var changes = store.changes().makeAsyncIterator()

    try await store.load()

    let initial = AuthChange(event: .initialSession, status: .signedOut(.sessionMissing))
    #expect(await changes.next() == initial)
    #expect(store.currentStatus == .signedOut(.sessionMissing))
  }

  @Test
  func loadRestoresTheStoredSessionAndItsReceiptTime() async throws {
    let storage = InMemoryAuthStorage()
    let stored = ReceivedSession(session: makeSession("stored"), receivedAt: receivedAt)
    try await storage.save(PersistedSessionCodec.encode(stored), key: key)
    let store = SessionStore(storage: storage, key: key, now: { Date.distantFuture })

    try await store.load()
    try await store.commit(.userUpdated(makeUser(email: "new@example.com"), event: .userUpdated))

    var expected = stored
    expected.session.user = makeUser(email: "new@example.com")
    #expect(store.currentSession == expected.session)
    #expect(try await storedSession(storage) == expected)
  }

  @Test
  func loadRemovesACorruptBlobAndSignsOut() async throws {
    let storage = InMemoryAuthStorage()
    try await storage.save(Data("not-json".utf8), key: key)
    let store = SessionStore(storage: storage, key: key)
    var changes = store.changes().makeAsyncIterator()

    try await store.load()

    let initial = AuthChange(event: .initialSession, status: .signedOut(.sessionMissing))
    #expect(await changes.next() == initial)
    #expect(try await storage.load(key: key) == nil)
  }

  @Test
  func unavailableStorageKeepsLoadingUntilALaterLoadSucceeds() async throws {
    let storage = TestAuthStorage()
    try await storage.save(PersistedSessionCodec.encode(received("stored")), key: key)
    storage.failure.setValue(AuthError(kind: .storageUnavailable, message: "locked"))
    let store = SessionStore(storage: storage, key: key)
    var changes = store.changes().makeAsyncIterator()

    let error = await #expect(throws: AuthError.self) { try await store.load() }
    #expect(error?.kind == .storageUnavailable)
    #expect(store.currentStatus == .loading)

    storage.failure.setValue(nil)
    try await store.load()

    let initial = AuthChange(event: .initialSession, status: .signedIn(makeSession("stored")))
    #expect(await changes.next() == initial)
  }

  @Test
  func subscriberAfterLoadStartsWithTheCurrentStatus() async throws {
    let store = try await loadedStore()
    try await store.commit(.signedIn(makeSession("a"), event: .signedIn))

    var changes = store.changes().makeAsyncIterator()
    try await store.commit(.signedOut(.userInitiated, event: .signedOut))

    let initial = AuthChange(event: .initialSession, status: .signedIn(makeSession("a")))
    let signedOut = AuthChange(event: .signedOut, status: .signedOut(.userInitiated))
    #expect(await changes.next() == initial)
    #expect(await changes.next() == signedOut)
  }

  @Test
  func concurrentCommitsEmitInTheOrderTheyWereStored() async throws {
    let storage = TestAuthStorage()
    let store = try await loadedStore(storage: storage)
    var changes = store.changes().makeAsyncIterator()
    _ = await changes.next()
    let fromGeneration = await store.generation

    await withTaskGroup(of: Void.self) { group in
      for index in 0..<20 {
        group.addTask {
          try? await store.commit(.signedIn(makeSession("sign-in-\(index)"), event: .signedIn))
        }
      }
      group.addTask {
        try? await store.commit(.refreshed(makeSession("refresh"), fromGeneration: fromGeneration))
      }
    }

    let storedOrder = try storage.savedAccessTokens()
    var emittedOrder: [String] = []
    for _ in storedOrder {
      guard case .signedIn(let session) = await changes.next()?.status else { break }
      emittedOrder.append(session.accessToken)
    }
    #expect(storedOrder.count >= 20)
    #expect(emittedOrder == storedOrder)
    #expect(store.currentSession?.accessToken == storedOrder.last)
    #expect(try await storedSession(storage)?.session == store.currentSession)
  }

  @Test
  func refreshFromTheCurrentGenerationApplies() async throws {
    let storage = InMemoryAuthStorage()
    let store = try await loadedStore(storage: storage, now: { receivedAt })
    try await store.commit(.signedIn(makeSession("a"), event: .signedIn))
    var changes = store.changes().makeAsyncIterator()
    _ = await changes.next()

    try await store.commit(.refreshed(makeSession("b"), fromGeneration: await store.generation))

    let refreshed = AuthChange(event: .tokenRefreshed, status: .signedIn(makeSession("b")))
    #expect(await changes.next() == refreshed)
    #expect(try await storedSession(storage) == received("b"))
  }

  @Test
  func staleRefreshAfterSignOutIsDiscarded() async throws {
    let storage = InMemoryAuthStorage()
    let store = try await loadedStore(storage: storage)
    try await store.commit(.signedIn(makeSession("a"), event: .signedIn))
    let fromGeneration = await store.generation
    var changes = store.changes().makeAsyncIterator()
    _ = await changes.next()

    try await store.commit(.signedOut(.userInitiated, event: .signedOut))
    let discarded = await #expect(throws: AuthError.self) {
      try await store.commit(.refreshed(makeSession("b"), fromGeneration: fromGeneration))
    }
    #expect(discarded?.kind == .refreshDiscarded)

    #expect(store.currentStatus == .signedOut(.userInitiated))
    #expect(try await storage.load(key: key) == nil)
    try await store.commit(.signedIn(makeSession("c"), event: .signedIn))
    let signedOut = AuthChange(event: .signedOut, status: .signedOut(.userInitiated))
    let signedIn = AuthChange(event: .signedIn, status: .signedIn(makeSession("c")))
    #expect(await changes.next() == signedOut)
    #expect(await changes.next() == signedIn)
  }

  @Test
  func failedStorageWriteLeavesTheStateUnchangedAndRethrows() async throws {
    let storage = TestAuthStorage()
    let store = try await loadedStore(storage: storage)
    try await store.commit(.signedIn(makeSession("a"), event: .signedIn))
    let generation = await store.generation
    var changes = store.changes().makeAsyncIterator()
    _ = await changes.next()

    storage.failure.setValue(AuthError(kind: .storageUnavailable, message: "locked"))
    let saveError = await #expect(throws: AuthError.self) {
      try await store.commit(.signedIn(makeSession("b"), event: .signedIn))
    }
    let removeError = await #expect(throws: AuthError.self) {
      try await store.commit(.signedOut(.userInitiated, event: .signedOut))
    }
    #expect(saveError?.kind == .storageUnavailable)
    #expect(removeError?.kind == .storageUnavailable)

    #expect(store.currentSession == makeSession("a"))
    #expect(await store.generation == generation)
    storage.failure.setValue(nil)
    #expect(try await storedSession(storage)?.session == makeSession("a"))
    try await store.commit(.signedIn(makeSession("c"), event: .signedIn))
    let signedIn = AuthChange(event: .signedIn, status: .signedIn(makeSession("c")))
    #expect(await changes.next() == signedIn)
  }

  @Test
  func userUpdateMergesIntoTheSessionCurrentAtCommit() async throws {
    let storage = InMemoryAuthStorage()
    let store = try await loadedStore(storage: storage, now: { receivedAt })
    try await store.commit(.signedIn(makeSession("a"), event: .signedIn))
    try await store.commit(.refreshed(makeSession("b"), fromGeneration: await store.generation))

    let user = makeUser(email: "new@example.com")
    try await store.commit(.userUpdated(user, event: .userUpdated))

    var expected = received("b")
    expected.session.user = user
    #expect(store.currentSession == expected.session)
    #expect(try await storedSession(storage) == expected)
  }

  @Test
  func userUpdateWhileSignedOutThrowsSessionMissing() async throws {
    let store = try await loadedStore()

    let error = await #expect(throws: AuthError.self) {
      try await store.commit(.userUpdated(makeUser(email: "new@example.com"), event: .userUpdated))
    }
    #expect(error?.kind == .sessionMissing)
    #expect(store.currentStatus == .signedOut(.sessionMissing))
  }

  @Test
  func commitWhileLoadingIsTheInitialSession() async throws {
    let store = SessionStore(storage: InMemoryAuthStorage(), key: key)
    var changes = store.changes().makeAsyncIterator()

    try await store.commit(.signedIn(makeSession("a"), event: .signedIn))
    try await store.load()

    let initial = AuthChange(event: .initialSession, status: .signedIn(makeSession("a")))
    #expect(await changes.next() == initial)
    #expect(store.currentSession == makeSession("a"))
  }

  @Test
  func twoClientsForOneProjectShareTheStore() async throws {
    let url = URL(string: "https://project.supabase.co/auth/v1")!
    let storageKey = "sb-\(UUID())-auth-token"
    let firstStorage = InMemoryAuthStorage()
    let first = SessionStore.shared(url: url, storageKey: storageKey, storage: firstStorage)
    let second = SessionStore.shared(
      url: url, storageKey: storageKey, storage: InMemoryAuthStorage())
    let otherProject = SessionStore.shared(
      url: URL(string: "https://other.supabase.co/auth/v1")!,
      storageKey: storageKey,
      storage: InMemoryAuthStorage()
    )
    try await first.load()
    var secondChanges = second.changes().makeAsyncIterator()
    _ = await secondChanges.next()

    try await first.commit(.signedIn(makeSession("a"), event: .signedIn))
    try await second.commit(.signedOut(.userInitiated, event: .signedOut))

    let signedIn = AuthChange(event: .signedIn, status: .signedIn(makeSession("a")))
    let signedOut = AuthChange(event: .signedOut, status: .signedOut(.userInitiated))
    #expect(await secondChanges.next() == signedIn)
    #expect(await secondChanges.next() == signedOut)
    #expect(first.currentStatus == .signedOut(.userInitiated))
    #expect(otherProject.currentStatus == .loading)
  }

  @Test
  func releasingTheStoreFinishesItsStreams() async throws {
    var store: SessionStore? = try await loadedStore()
    var changes = try #require(store).changes().makeAsyncIterator()
    _ = await changes.next()

    store = nil

    #expect(await changes.next() == nil)
  }

  private func loadedStore(
    storage: any AuthStorage = InMemoryAuthStorage(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) async throws -> SessionStore {
    let store = SessionStore(storage: storage, key: key, now: now)
    try await store.load()
    return store
  }

  private func received(_ token: String) -> ReceivedSession {
    ReceivedSession(session: makeSession(token), receivedAt: receivedAt)
  }

  private func storedSession(_ storage: any AuthStorage) async throws -> ReceivedSession? {
    try await storage.load(key: key).map { try PersistedSessionCodec.decode($0).session }
  }
}

private func makeSession(_ accessToken: String) -> Session {
  Session(
    accessToken: accessToken,
    tokenType: "bearer",
    expiresIn: 3600,
    expiresAt: 1_700_003_600,
    refreshToken: "refresh-\(accessToken)",
    user: makeUser(email: "user@example.com")
  )
}

private func makeUser(email: String) -> User {
  User(
    id: UUID(uuidString: "859F402D-B3DE-4105-A1B9-932836D9193B")!,
    appMetadata: [:],
    userMetadata: [:],
    audience: "authenticated",
    email: email,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

/// Wraps ``InMemoryAuthStorage``: records each save, and throws `failure` from every call while
/// it is set. An earlier save returns later than a later one, so commits that overlap would
/// finish out of order.
private final class TestAuthStorage: AuthStorage {
  private let storage = InMemoryAuthStorage()
  let failure = LockIsolated<AuthError?>(nil)
  private let saves = LockIsolated<[Data]>([])

  func load(key: String) async throws -> Data? {
    if let failure = failure.value { throw failure }
    return try await storage.load(key: key)
  }

  func save(_ data: Data, key: String) async throws {
    if let failure = failure.value { throw failure }
    let count = saves.withValue {
      $0.append(data)
      return $0.count
    }
    try await storage.save(data, key: key)
    for _ in stride(from: count, to: 25, by: 1) {
      await Task.yield()
    }
  }

  func remove(key: String) async throws {
    if let failure = failure.value { throw failure }
    try await storage.remove(key: key)
  }

  func savedAccessTokens() throws -> [String] {
    try saves.value.map { try PersistedSessionCodec.decode($0).session.session.accessToken }
  }
}
