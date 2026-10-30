import ConcurrencyExtras
import Foundation
import IssueReporting
import TestHelpers
import Testing

@testable import Auth

@Suite
struct LockedStorageTests {
  private static let refreshAfter = 3600 - Refresher.refreshLeadTime.timeInterval

  private let key = uniqueStorageKey()

  @Test
  func twoFailedLoadsEmitNothingAndTheThirdEmitsOneInitialSession() async throws {
    let storage = LockedAuthStorage(failingLoads: 2)
    let stored = ReceivedSession(session: makeSession("stored"), receivedAt: Date())
    try await storage.save(PersistedSessionCodec.encode(stored), key: key)
    let store = SessionStore(storage: storage, key: key)
    var changes = store.changes().makeAsyncIterator()

    for _ in 0..<2 {
      let error = await #expect(throws: AuthError.self) { try await store.load() }
      #expect(error?.kind == .storageUnavailable)
      #expect(store.currentStatus == .loading)
    }
    try await store.load()
    try await store.commit(.signedOut(.userInitiated, event: .signedOut))

    let initial = AuthChange(event: .initialSession, status: .signedIn(makeSession("stored")))
    let signedOut = AuthChange(event: .signedOut, status: .signedOut(.userInitiated))
    #expect(await changes.next() == initial)
    #expect(await changes.next() == signedOut)
  }

  @Test
  func failedSaveOfARefreshKeepsTheSessionAndSignsNothingOut() async throws {
    let storage = LockedAuthStorage()
    let store = SessionStore(storage: storage, key: key)
    try await store.load()
    try await store.commit(.signedIn(makeSession("a"), event: .signedIn))
    var changes = store.changes().makeAsyncIterator()
    _ = await changes.next()

    storage.failsSaves.setValue(true)
    let error = await #expect(throws: AuthError.self) {
      try await store.refresh("refresh-a") { _ in makeSession("b") }
    }

    #expect(error?.kind == .storageUnavailable)
    #expect(store.currentStatus == .signedIn(makeSession("a")))
    let saved = try await storage.load(key: key).map { try PersistedSessionCodec.decode($0) }
    #expect(saved?.session.session == makeSession("a"))
    try await store.commit(.signedOut(.userInitiated, event: .signedOut))
    let signedOut = AuthChange(event: .signedOut, status: .signedOut(.userInitiated))
    #expect(await changes.next() == signedOut)
  }

  @Test(arguments: [true, false])
  func lockedStorageAtLaunchLoadsWhenProtectedDataBecomesAvailable(
    observesAppLifecycle: Bool
  ) async throws {
    let world = World()
    let issued = world.issueSession()
    let storage = LockedLocalStorage()
    try storage.store(
      key: key,
      value: PersistedSessionCodec.encode(ReceivedSession(session: issued, receivedAt: world.now()))
    )
    storage.isLocked.setValue(true)
    let (events, lifecycle) = AsyncStream.makeStream(of: AppLifecycleEvent.self)
    lifecycle.yield(.foreground)
    let client = makeClient(
      world, storage: storage, observesAppLifecycle: observesAppLifecycle, lifecycle: events)
    let store = client.dependencies.sessionStore
    var changes = store.changes().makeAsyncIterator()

    #expect(await waitUntil { await client.dependencies.autoRefresh.isRegistered })
    #expect(await waitUntil { storage.failedReads.value >= 2 })
    #expect(store.currentStatus == .loading)
    await world.advance(to: Self.refreshAfter + 60)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    storage.isLocked.setValue(false)
    lifecycle.yield(.protectedDataDidBecomeAvailable)

    try #require(await waitUntil { store.currentStatus != .loading })
    #expect(await changes.next() == AuthChange(event: .initialSession, status: .signedIn(issued)))
    #expect(await world.refreshCount(settledAt: 1) == 1)
    #expect(await changes.next()?.event == .tokenRefreshed)
  }

  #if canImport(Security)
    @Test
    func missingEntitlementIsReportedAndKeepsTheClientLoading() async throws {
      let entitlementError = KeychainError(code: .init(rawValue: errSecMissingEntitlement))
      let storage = KeychainLocalStorage(
        keychain: FakeKeychain(readError: entitlementError),
        legacyKeychains: []
      )
      let reporter = RecordingIssueReporter()

      let client = withIssueReporters([reporter]) {
        makeClient(World(), storage: storage)
      }

      #expect(await waitUntil { reporter.messages.value.count == 1 })
      #expect(reporter.messages.value.first?.contains("keychain-access-groups") == true)
      let error = await #expect(throws: AuthError.self) { try await client.session }
      #expect(error?.kind == .storageMisconfigured)
      #expect(error?.message.contains("keychain-access-groups") == true)
      #expect(client.dependencies.sessionStore.currentStatus == .loading)
    }

    @Test
    func missingEntitlementOnlyOnWritesIsReportedOnceAtTheFirstSignIn() async throws {
      let entitlementError = KeychainError(code: .init(rawValue: errSecMissingEntitlement))
      let storage = KeychainLocalStorage(
        keychain: FakeKeychain(writeError: entitlementError, deleteError: entitlementError),
        legacyKeychains: []
      )
      let reporter = RecordingIssueReporter()
      let client = withIssueReporters([reporter]) {
        makeClient(World(), storage: storage)
      }
      let store = client.dependencies.sessionStore

      try #require(await waitUntil { store.currentStatus != .loading })
      #expect(store.currentStatus == .signedOut(.sessionMissing))
      #expect(reporter.messages.value.isEmpty)

      for _ in 0..<2 {
        let error = await #expect(throws: AuthError.self) {
          try await withIssueReporters([reporter]) {
            try await client.signIn(email: "user@example.com", password: "secret")
          }
        }
        #expect(error?.kind == .storageMisconfigured)
      }
      #expect(reporter.messages.value.count == 1)
      #expect(reporter.messages.value.first?.contains("keychain-access-groups") == true)
    }

    @Test
    func missingEntitlementOnTheRemoveOfASignOutIsReported() async throws {
      let entitlementError = KeychainError(code: .init(rawValue: errSecMissingEntitlement))
      let world = World()
      let stored = ReceivedSession(session: world.issueSession(), receivedAt: world.now())
      let storage = KeychainLocalStorage(
        keychain: FakeKeychain(
          items: [key: try PersistedSessionCodec.encode(stored)],
          deleteError: entitlementError
        ),
        legacyKeychains: []
      )
      let reporter = RecordingIssueReporter()
      let client = withIssueReporters([reporter]) { makeClient(world, storage: storage) }

      let error = await #expect(throws: AuthError.self) {
        try await withIssueReporters([reporter]) { try await client.signOut(scope: .local) }
      }

      #expect(error?.kind == .storageMisconfigured)
      #expect(reporter.messages.value.count == 1)
    }

    @Test
    func missingEntitlementOnACodeVerifierWriteIsReported() async throws {
      let entitlementError = KeychainError(code: .init(rawValue: errSecMissingEntitlement))
      let storage = KeychainLocalStorage(
        keychain: FakeKeychain(writeError: entitlementError),
        legacyKeychains: []
      )
      let reporter = RecordingIssueReporter()
      let client = withIssueReporters([reporter]) { makeClient(World(), storage: storage) }

      await #expect(throws: CancellationError.self) {
        try await withIssueReporters([reporter]) {
          try await client.signInWithOAuth(provider: .github) { _ in throw CancellationError() }
        }
      }

      #expect(reporter.messages.value.count == 1)
    }
  #endif

  private func makeClient(
    _ world: World,
    storage: any AuthLocalStorage,
    observesAppLifecycle: Bool = true,
    lifecycle: AsyncStream<AppLifecycleEvent> = AsyncStream {
      $0.yield(.foreground)
      $0.finish()
    }
  ) -> AuthClient {
    var platform = AuthPlatform.live
    platform.hasBackgroundState = true
    platform.lifecycleEvents = { lifecycle }
    return AuthClient(
      configuration: AuthClient.Configuration(
        url: clientURL,
        storageKey: key,
        localStorage: storage,
        http: HTTPClientConfiguration(transport: world.http),
        autoRefresh: .automatic,
        observesAppLifecycle: observesAppLifecycle,
        clock: world.clock
      ),
      date: world.now,
      pkce: .live,
      platform: platform
    )
  }
}

private func makeSession(_ name: String) -> Session {
  Session(
    accessToken: name,
    tokenType: "bearer",
    expiresIn: 3600,
    expiresAt: 1_700_003_600,
    refreshToken: "refresh-\(name)",
    user: User(fromMockNamed: "user")
  )
}

private final class LockedAuthStorage: AuthStorage {
  private let storage = InMemoryAuthStorage()
  private let failingLoads: LockIsolated<Int>
  let failsSaves = LockIsolated(false)

  init(failingLoads: Int = 0) {
    self.failingLoads = LockIsolated(failingLoads)
  }

  func load(key: String) async throws -> Data? {
    let fails = failingLoads.withValue { remaining in
      guard remaining > 0 else { return false }
      remaining -= 1
      return true
    }
    if fails { throw AuthError(kind: .storageUnavailable, message: "locked") }
    return try await storage.load(key: key)
  }

  func save(_ data: Data, key: String) async throws {
    if failsSaves.value { throw AuthError(kind: .storageUnavailable, message: "locked") }
    try await storage.save(data, key: key)
  }

  func remove(key: String) async throws {
    try await storage.remove(key: key)
  }
}

final class LockedLocalStorage: AuthLocalStorage {
  private let storage = InMemoryLocalStorage()
  let isLocked = LockIsolated(false)
  let failedReads = LockIsolated(0)

  func store(key: String, value: Data) throws {
    try storage.store(key: key, value: value)
  }

  func retrieve(key: String) throws -> Data? {
    if isLocked.value {
      failedReads.withValue { $0 += 1 }
      throw AuthError(kind: .storageUnavailable, message: "locked")
    }
    return try storage.retrieve(key: key)
  }

  func remove(key: String) throws {
    try storage.remove(key: key)
  }
}

private final class RecordingIssueReporter: IssueReporter {
  let messages = LockIsolated<[String]>([])

  func reportIssue(
    _ message: @autoclosure () -> String?,
    severity: IssueSeverity,
    fileID: StaticString,
    filePath: StaticString,
    line: UInt,
    column: UInt
  ) {
    let message = message() ?? ""
    messages.withValue { $0.append(message) }
  }
}
