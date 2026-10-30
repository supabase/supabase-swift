import Foundation
import Logging

/// Stores each pending PKCE flow as its own record, with an index of the live flows.
///
/// Every call reads storage again, because two clients can share one storage.
actor FlowStore {
  private let storage: any AuthStorage
  private let storageKey: String
  private let pkce: PKCE
  private let now: @Sendable () -> Date
  private let logger: Logging.Logger
  private var lastIndexUpdate: Task<Void, Never>?

  init(
    storage: any AuthStorage,
    storageKey: String,
    pkce: PKCE,
    now: @escaping @Sendable () -> Date,
    logger: Logging.Logger
  ) {
    self.storage = storage
    self.storageKey = storageKey
    self.pkce = pkce
    self.now = now
    self.logger = logger
  }

  /// Saves a new flow and returns it with the challenge to send to the server.
  ///
  /// The record is written before the index, so an index entry never points at a missing record.
  func start(
    purpose: PendingFlowRecord.Purpose,
    redirectTo: URL?
  ) async throws -> (flow: PendingFlowRecord, challenge: PKCEChallenge) {
    let verifier = pkce.generateCodeVerifier()
    let challenge = pkce.generateCodeChallenge(verifier)
    let startedAt = now()
    let flow = PendingFlowRecord(
      id: UUID(), verifier: verifier, purpose: purpose, redirectTo: redirectTo,
      createdAt: startedAt)

    try await storage.save(try flow.encoded(), key: recordKey(flow.id))

    let dropped = try await updateIndex { index in
      index.insert(PendingFlowIndex.Entry(id: flow.id, createdAt: startedAt), now: startedAt)
    }

    for id in dropped {
      do {
        try await storage.remove(key: recordKey(id))
      } catch {
        logger.error("Failure removing a dropped flow record: \(error.localizedDescription)")
      }
    }

    return (
      flow,
      PKCEChallenge(
        codeChallenge: challenge,
        codeChallengeMethod: verifier == challenge ? "plain" : "s256")
    )
  }

  func flow(id: UUID) async throws -> PendingFlowRecord? {
    guard let data = try await storage.load(key: recordKey(id)) else { return nil }
    let record = try PendingFlowRecord.decode(data)
    return PendingFlowRecord.isExpired(createdAt: record.createdAt, at: now()) ? nil : record
  }

  func newest() async throws -> PendingFlowRecord? {
    for entry in try await loadIndex().flows.reversed() {
      if let record = try await flow(id: entry.id) {
        return record
      }
    }
    return nil
  }

  func remove(id: UUID) async throws {
    try await updateIndex { $0.remove(id: id) }
    try await storage.remove(key: recordKey(id))
  }

  private func recordKey(_ id: UUID) -> String {
    PendingFlowRecord.key(id: id, storageKey: storageKey)
  }

  /// Runs the index read-modify-write one update at a time.
  ///
  /// The actor is reentrant across the storage awaits, so without this two updates could read the
  /// same index and the second save would drop the first one's change.
  private func updateIndex<Result: Sendable>(
    _ change: @escaping @Sendable (inout PendingFlowIndex) -> Result
  ) async throws -> Result {
    let previous = lastIndexUpdate
    let update = Task { () throws -> Result in
      await previous?.value
      var index = try await self.loadIndex()
      let result = change(&index)
      try await self.storage.save(
        try index.encoded(), key: PendingFlowIndex.key(storageKey: self.storageKey))
      return result
    }
    lastIndexUpdate = Task { _ = await update.result }
    return try await update.value
  }

  private func loadIndex() async throws -> PendingFlowIndex {
    guard let data = try await storage.load(key: PendingFlowIndex.key(storageKey: storageKey))
    else { return PendingFlowIndex() }
    return try PendingFlowIndex.decode(data)
  }
}
