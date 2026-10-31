import ConcurrencyExtras
import Foundation
import Logging
import Testing

@testable import Auth

private actor RecordingStorage: AuthStorage {
  struct SaveFailure: Error {}

  private var values: [String: Data] = [:]
  private(set) var savedKeys: [String] = []
  private(set) var removedKeys: [String] = []
  private var failingSave: Int?
  private var saveCount = 0

  func failSave(number: Int) {
    failingSave = number
  }

  func load(key: String) async throws -> Data? {
    values[key]
  }

  func save(_ data: Data, key: String) async throws {
    saveCount += 1
    if saveCount == failingSave { throw SaveFailure() }
    savedKeys.append(key)
    values[key] = data
  }

  func remove(key: String) async throws {
    removedKeys.append(key)
    values[key] = nil
  }
}

@Suite
struct FlowStoreTests {
  private static let storageKey = "sb-test"

  private func makeStore(
    storage: RecordingStorage,
    clock: LockIsolated<Date>,
    pkce: PKCE = PKCE(
      generateCodeVerifier: { "verifier" },
      generateCodeChallenge: { "challenge-of-\($0)" }
    )
  ) -> FlowStore {
    FlowStore(
      storage: storage,
      storageKey: Self.storageKey,
      pkce: pkce,
      now: { clock.value },
      logger: Logger(label: "test")
    )
  }

  private func advance(_ clock: LockIsolated<Date>, by seconds: TimeInterval) {
    clock.withValue { $0 = $0.addingTimeInterval(seconds) }
  }

  @Test func startWritesTheRecordThenTheIndexBeforeReturning() async throws {
    let storage = RecordingStorage()
    let store = makeStore(storage: storage, clock: LockIsolated(Date(timeIntervalSince1970: 1000)))

    let (flow, challenge) = try await store.start(purpose: .signIn, redirectTo: nil)

    let recordKey = PendingFlowRecord.key(id: flow.id, storageKey: Self.storageKey)
    #expect(
      await storage.savedKeys == [recordKey, PendingFlowIndex.key(storageKey: Self.storageKey)])
    let data = try #require(try await storage.load(key: recordKey))
    #expect(try PendingFlowRecord.decode(data).verifier == "verifier")
    #expect(flow.verifier == "verifier")
    #expect(challenge.codeChallenge == "challenge-of-verifier")
    #expect(challenge.codeChallengeMethod == "s256")
  }

  @Test func theChallengeMethodIsPlainWhenTheChallengeEqualsTheVerifier() async throws {
    let store = makeStore(
      storage: RecordingStorage(),
      clock: LockIsolated(Date()),
      pkce: PKCE(generateCodeVerifier: { "same" }, generateCodeChallenge: { $0 })
    )
    let (_, challenge) = try await store.start(purpose: .signIn, redirectTo: nil)
    #expect(challenge.codeChallengeMethod == "plain")
  }

  @Test func startThrowsWhenTheIndexWriteFails() async throws {
    let storage = RecordingStorage()
    await storage.failSave(number: 2)
    let store = makeStore(storage: storage, clock: LockIsolated(Date()))

    await #expect(throws: (any Error).self) {
      try await store.start(purpose: .signIn, redirectTo: nil)
    }
  }

  @Test func aSixthFlowEvictsTheOldest() async throws {
    let storage = RecordingStorage()
    let clock = LockIsolated(Date(timeIntervalSince1970: 1000))
    let store = makeStore(storage: storage, clock: clock)

    var ids: [UUID] = []
    for _ in 0..<6 {
      ids.append(try await store.start(purpose: .signIn, redirectTo: nil).flow.id)
      advance(clock, by: 1)
    }

    #expect(try await store.flow(id: ids[0]) == nil)
    #expect(
      await storage.removedKeys == [PendingFlowRecord.key(id: ids[0], storageKey: Self.storageKey)])
    #expect(try await store.flow(id: ids[5]) != nil)
  }

  @Test func anExpiredFlowIsNotReturned() async throws {
    let clock = LockIsolated(Date(timeIntervalSince1970: 1000))
    let store = makeStore(storage: RecordingStorage(), clock: clock)
    let flow = try await store.start(purpose: .signIn, redirectTo: nil).flow

    advance(clock, by: 3600)

    #expect(try await store.flow(id: flow.id) == nil)
    #expect(try await store.pendingFlows().isEmpty)
  }

  @Test func removeDeletesTheRecordAndTheIndexEntry() async throws {
    let storage = RecordingStorage()
    let store = makeStore(storage: storage, clock: LockIsolated(Date()))
    let flow = try await store.start(purpose: .signIn, redirectTo: nil).flow

    try await store.remove(id: flow.id)

    #expect(try await store.flow(id: flow.id) == nil)
    #expect(try await store.pendingFlows().isEmpty)
    #expect(
      await storage.removedKeys == [PendingFlowRecord.key(id: flow.id, storageKey: Self.storageKey)]
    )
    let indexData = try #require(
      try await storage.load(key: PendingFlowIndex.key(storageKey: Self.storageKey)))
    #expect(try PendingFlowIndex.decode(indexData).flows.isEmpty)
  }

  @Test func legacyVerifierKeysAreNotRead() async throws {
    let storage = RecordingStorage()
    try await storage.save(Data("legacy".utf8), key: "\(Self.storageKey)-code-verifier")
    let store = makeStore(storage: storage, clock: LockIsolated(Date()))

    #expect(try await store.pendingFlows().isEmpty)
  }

  @Test func pendingFlowsListsTheLiveFlowsNewestFirst() async throws {
    let clock = LockIsolated(Date(timeIntervalSince1970: 1000))
    let store = makeStore(storage: RecordingStorage(), clock: clock)
    let first = try await store.start(purpose: .signIn, redirectTo: nil).flow
    advance(clock, by: 1)
    let second = try await store.start(purpose: .recovery, redirectTo: nil).flow
    advance(clock, by: 1)
    let third = try await store.start(purpose: .emailChange, redirectTo: nil).flow
    try await store.remove(id: second.id)

    #expect(try await store.pendingFlows() == [third, first])
  }

  @Test func anIndexThatFailsToDecodeIsEmptyAndIsOverwritten() async throws {
    let storage = RecordingStorage()
    let indexKey = PendingFlowIndex.key(storageKey: Self.storageKey)
    try await storage.save(Data("not json".utf8), key: indexKey)
    let store = makeStore(storage: storage, clock: LockIsolated(Date()))

    #expect(try await store.pendingFlows().isEmpty)

    let flow = try await store.start(purpose: .signIn, redirectTo: nil).flow

    #expect(try await storedIndexIDs(storage) == [flow.id])
    #expect(try await store.pendingFlows().first == flow)
  }

  @Test func aRecordThatFailsToDecodeIsSkipped() async throws {
    let storage = RecordingStorage()
    let clock = LockIsolated(Date(timeIntervalSince1970: 1000))
    let store = makeStore(storage: storage, clock: clock)
    let older = try await store.start(purpose: .signIn, redirectTo: nil).flow
    advance(clock, by: 1)
    let newer = try await store.start(purpose: .recovery, redirectTo: nil).flow
    try await storage.save(
      Data("not json".utf8), key: PendingFlowRecord.key(id: newer.id, storageKey: Self.storageKey))

    #expect(try await store.pendingFlows() == [older])
  }

  private func storedIndexIDs(_ storage: RecordingStorage) async throws -> Set<UUID> {
    let data = try #require(
      try await storage.load(key: PendingFlowIndex.key(storageKey: Self.storageKey)))
    return Set(try PendingFlowIndex.decode(data).flows.map(\.id))
  }

  @Test func concurrentStartsKeepEveryIndexEntry() async throws {
    let storage = RecordingStorage()
    let store = makeStore(storage: storage, clock: LockIsolated(Date()))

    let ids = try await withThrowingTaskGroup(of: UUID.self) { group in
      for _ in 0..<5 {
        group.addTask { try await store.start(purpose: .signIn, redirectTo: nil).flow.id }
      }
      return try await group.reduce(into: Set<UUID>()) { $0.insert($1) }
    }

    #expect(ids.count == 5)
    #expect(try await storedIndexIDs(storage) == ids)
  }

  @Test func concurrentStartAndRemoveLeaveAConsistentIndex() async throws {
    let storage = RecordingStorage()
    let store = makeStore(storage: storage, clock: LockIsolated(Date()))
    let existing = try await store.start(purpose: .signIn, redirectTo: nil).flow.id

    async let started = store.start(purpose: .recovery, redirectTo: nil).flow.id
    async let removed: Void = store.remove(id: existing)
    let newID = try await started
    try await removed

    #expect(try await storedIndexIDs(storage) == [newID])
  }
}
