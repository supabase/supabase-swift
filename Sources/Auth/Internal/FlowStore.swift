import ConcurrencyExtras
import Foundation
import Logging

/// Stores each pending PKCE flow as its own record, with an index of the live flows.
///
/// Every call reads storage again, because two clients can share one storage. Index updates run
/// one at a time for each storage key in the process. Another process, such as an app extension
/// that shares the Keychain, can still overwrite an index update, so ``start(purpose:redirectTo:)``
/// reads the index again after its update and repeats a lost one.
actor FlowStore {
  /// How many times ``start(purpose:redirectTo:)`` writes its index entry before it gives up.
  static let maximumIndexAttempts = 3

  private let storage: any AuthStorage
  private let storageKey: String
  private let pkce: PKCE
  private let now: @Sendable () -> Date
  private let logger: Logging.Logger
  private let indexUpdates: FlowIndexUpdateQueue

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
    self.indexUpdates = .queue(storageKey: storageKey)
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
    let flow = PendingFlowRecord(
      id: UUID(), verifier: verifier, purpose: purpose, redirectTo: redirectTo, createdAt: now())

    try await storage.save(try flow.encoded(), key: recordKey(flow.id))

    let dropped = try await insertIndexEntry(
      PendingFlowIndex.Entry(id: flow.id, createdAt: flow.createdAt))

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

  /// The live flows, newest first. Expired records and records that fail to decode are skipped.
  func pendingFlows() async throws -> [PendingFlowRecord] {
    var flows: [PendingFlowRecord] = []
    for entry in try await loadIndex().flows.reversed() {
      if let record = try await liveFlow(id: entry.id) {
        flows.append(record)
      }
    }
    return flows
  }

  func remove(id: UUID) async throws {
    try await updateIndex { $0.remove(id: id) }
    try await storage.remove(key: recordKey(id))
  }

  /// Removes every flow. A record that fails to remove is logged, as a dropped one is.
  func removeAll() async throws {
    let removed = try await updateIndex { index in
      defer { index = PendingFlowIndex() }
      return index.flows.map(\.id)
    }
    for id in removed {
      do {
        try await storage.remove(key: recordKey(id))
      } catch {
        logger.error("Failure removing a pending flow record: \(error.localizedDescription)")
      }
    }
  }

  /// Like ``flow(id:)``, but a record that fails to decode is logged and skipped.
  private func liveFlow(id: UUID) async throws -> PendingFlowRecord? {
    do {
      return try await flow(id: id)
    } catch is DecodingError {
      logger.warning("Skipping a pending flow record that fails to decode.")
      return nil
    }
  }

  private func recordKey(_ id: UUID) -> String {
    PendingFlowRecord.key(id: id, storageKey: storageKey)
  }

  /// Inserts `entry`, then reads the index again and repeats the insert when another process
  /// overwrote it. A lost entry would leave a record that no prune removes.
  ///
  /// - Returns: The IDs of the flows the inserts dropped.
  private func insertIndexEntry(_ entry: PendingFlowIndex.Entry) async throws -> [UUID] {
    var dropped: [UUID] = []
    for _ in 0..<Self.maximumIndexAttempts {
      dropped += try await updateIndex { index in
        index.flows.contains { $0.id == entry.id } ? [] : index.insert(entry, now: entry.createdAt)
      }
      if try await loadIndex().flows.contains(where: { $0.id == entry.id }) {
        return dropped
      }
    }
    logger.warning("Another client keeps overwriting the pending flow index.")
    return dropped
  }

  /// Runs the index read-modify-write one update at a time for the storage key.
  ///
  /// The actor is reentrant across the storage awaits, and other clients in the process can share
  /// the storage key. Without this, two updates could read the same index and the second save
  /// would drop the first one's change.
  private func updateIndex<Result: Sendable>(
    _ change: @escaping @Sendable (inout PendingFlowIndex) -> Result
  ) async throws -> Result {
    try await indexUpdates.run {
      var index = try await self.loadIndex()
      let result = change(&index)
      try await self.storage.save(
        try index.encoded(), key: PendingFlowIndex.key(storageKey: self.storageKey))
      return result
    }
  }

  /// An index that fails to decode reads as empty, so the next update overwrites it.
  private func loadIndex() async throws -> PendingFlowIndex {
    guard let data = try await storage.load(key: PendingFlowIndex.key(storageKey: storageKey))
    else { return PendingFlowIndex() }
    do {
      return try PendingFlowIndex.decode(data)
    } catch {
      logger.warning("The pending flow index fails to decode. It is treated as empty.")
      return PendingFlowIndex()
    }
  }
}

/// Runs operations one at a time, in the order they arrive. One queue exists for each storage key
/// in the process, so every ``FlowStore`` on that key shares it.
final class FlowIndexUpdateQueue: Sendable {
  private static let queues = LockIsolated<[String: FlowIndexUpdateQueue]>([:])

  static func queue(storageKey: String) -> FlowIndexUpdateQueue {
    queues.withValue { queues in
      if let queue = queues[storageKey] { return queue }
      let queue = FlowIndexUpdateQueue()
      queues[storageKey] = queue
      return queue
    }
  }

  private let last = LockIsolated<Task<Void, Never>?>(nil)

  /// Runs `operation` after every earlier operation finished. Cancelling the caller does not
  /// cancel `operation`.
  func run<Result: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Result
  ) async throws -> Result {
    let update = last.withValue { last in
      let previous = last
      let update = Task {
        await previous?.value
        return try await operation()
      }
      last = Task { _ = await update.result }
      return update
    }
    return try await update.value
  }
}
