//
//  Channel+Presence.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import IssueReporting

// MARK: - PresenceKey

/// The presence key string the server attaches to each meta. Comes from
/// `ChannelOptions.presence.key` if set, otherwise server-generated.
public typealias PresenceKey = String

// MARK: - PresenceState

/// A snapshot of all presences on a channel, plus the incremental diff that produced it.
///
/// `active` maps each presence key to the list of decoded meta objects for that key.
/// `lastDiff` is `nil` on the initial `presence_state` snapshot and non-nil on every
/// subsequent `presence_diff` update.
public struct PresenceState<T: Sendable>: Sendable {
  public let active: [PresenceKey: [T]]
  public let lastDiff: PresenceDiff<T>?
}

// MARK: - PresenceDiff

/// An incremental presence change: who joined and who left since the last snapshot.
///
/// Each element is `(PresenceKey, T)` — the presence key and the decoded meta.
/// Multiple metas per key are flattened into the array in the order they appear in the
/// server payload.
public struct PresenceDiff<T: Sendable>: Sendable {
  public let joined: [(PresenceKey, T)]
  public let left: [(PresenceKey, T)]
}

// MARK: - PresenceHandle

/// Represents a single tracked presence slot returned by `Presence.track(_:)`.
///
/// - `update(_:)` replaces the meta for this slot without creating an additional meta.
/// - `cancel()` untracks and awaits server ACK.
///
/// The handle should be explicitly cancelled when done to cleanly untrack from the server.
/// If a handle is deinited without cancelling while the channel is still joined, a debug
/// warning is emitted via `IssueReporting.reportIssue`.
///
/// ## Leak Warning (Decision 15)
/// A `LockIsolated<Bool>` `cancelled` flag is used to track whether `cancel()` was called.
/// In `deinit` (which is nonisolated/synchronous), we cannot reliably hop to the `Channel`
/// actor to check its state. The simplest correct approach is: fire the warning whenever a
/// non-cancelled handle deinits. This may fire after `leave()` tears down the server slot
/// implicitly, but it is always safe (never a crash) and correctly catches genuine leaks.
///
/// ## Sendable
/// `PresenceHandle` is `Sendable` because all mutable state is wrapped in `LockIsolated`.
/// The `channel` reference is to the actor-isolated `Channel`, which is itself `Sendable`.
public final class PresenceHandle: Sendable {
  /// The owning channel. Strong ref is intentional (Channel does not hold handles → no cycle).
  let channel: Channel

  /// Whether `cancel()` has been called. Protected by `LockIsolated` for nonisolated deinit.
  let cancelled: LockIsolated<Bool>

  init(channel: Channel) {
    self.channel = channel
    self.cancelled = LockIsolated(false)
  }

  deinit {
    let alreadyCancelled = cancelled.value
    if !alreadyCancelled {
      reportIssue(
        "PresenceHandle deinited without cancel() being called. "
          + "Call handle.cancel() when done tracking to cleanly untrack from the server. "
          + "If the channel was left via channel.leave(), the server slot is implicitly "
          + "torn down, but the handle should still be cancelled to suppress this warning."
      )
    }
  }

  /// Update the current presence meta for this slot.
  ///
  /// Sends a fresh presence track frame with the new state. This replaces the existing
  /// meta on the server without creating an additional meta entry (Decision 16).
  ///
  /// - Throws: `RealtimeError.notSubscribed` if the channel is not yet subscribed.
  /// - Throws: `RealtimeError.channelClosed` if the channel has been closed.
  /// - Throws: `RealtimeError.broadcastAckTimeout` if the server does not acknowledge
  ///   within `configuration.broadcastAckTimeout`.
  public func update<T: Codable & Sendable>(_ state: T) async throws(RealtimeError) {
    try await channel.sendPresenceTrack(state)
  }

  /// Untracks presence for this slot; awaits server ACK.
  ///
  /// Idempotent: a second call is a no-op and returns immediately without sending any frame.
  /// After a successful cancel, the deinit leak-warning will not fire.
  ///
  /// - Throws: `RealtimeError.notSubscribed` if the channel is not yet subscribed.
  /// - Throws: `RealtimeError.channelClosed` if the channel has been closed.
  /// - Throws: `RealtimeError.broadcastAckTimeout` if the server does not acknowledge.
  public func cancel() async throws(RealtimeError) {
    // Idempotent: return immediately if already cancelled.
    let alreadyCancelled = cancelled.withValue { val -> Bool in
      if val { return true }
      val = true
      return false
    }
    guard !alreadyCancelled else { return }

    try await channel.sendPresenceUntrack()
  }
}

// MARK: - Presence

/// Provides presence operations for the owning `Channel`.
///
/// Obtain via `Channel.presence`. Methods `track`, `observe`, and `diffs` are
/// implemented in Tasks 24/25. Only the decoder utilities are live in this task.
public struct Presence: Sendable {
  /// Strong reference to the owning channel. `Presence` is a lightweight value
  /// wrapper handed out by `Channel.presence`; holding the channel strongly is
  /// safe (no retain cycle — `Channel` never references `Presence`, and `Channel`
  /// itself holds `Realtime` weakly) and avoids a use-after-free if a `Presence`
  /// value outlives the `Channel`'s entry in the registry.
  let channel: Channel

  /// Begin tracking, or update the existing tracked state, for this channel process.
  ///
  /// Sends a `presence` channel event with payload `{ "event": "track", "payload": <state> }`
  /// and awaits the server ACK. Returns a `PresenceHandle` that can be used to update or cancel
  /// the presence tracking.
  ///
  /// One meta per channel process (Decision 16): repeated `track` calls update the same slot,
  /// not create additional entries.
  ///
  /// - Parameter state: The presence meta to track. Must be `Codable & Sendable`.
  /// - Returns: A `PresenceHandle` bound to this channel.
  /// - Throws: `RealtimeError.notSubscribed` if the channel is not yet subscribed (`.unsubscribed`
  ///   or `.joining` state).
  /// - Throws: `RealtimeError.channelClosed` if the channel is leaving or closed.
  /// - Throws: `RealtimeError.broadcastAckTimeout` if the server does not ACK in time.
  public func track<T: Codable & Sendable>(
    _ state: T
  ) async throws(RealtimeError) -> PresenceHandle {
    // Delegate gating + wire send to the actor-isolated Channel seam.
    try await channel.sendPresenceTrack(state)
    // Return a handle bound to the owning channel.
    return PresenceHandle(channel: channel)
  }

  /// Snapshot + diff stream of all presences, keyed by presence key.
  ///
  /// Each call mints an independent `AsyncStream`. The consumer receives:
  /// - A `PresenceState` with `lastDiff == nil` on each `presence_state` frame (full snapshot).
  /// - A `PresenceState` with `lastDiff != nil` on each `presence_diff` frame (incremental update).
  ///
  /// The consumer's `active` map accumulates state per-consumer: `presence_state` replaces the
  /// map; `presence_diff` applies joins/leaves on top. Decode failures are swallowed so the
  /// stream stays open.
  ///
  /// The stream finishes cleanly (no throw) when the channel closes.
  public func observe<T: Decodable & Sendable>(
    _ type: T.Type
  ) async -> AsyncStream<PresenceState<T>> {
    await channel.registerPresenceObserver(T.self)
  }

  /// Incremental diffs only.
  ///
  /// Each call mints an independent `AsyncStream`. The consumer receives a `PresenceDiff<T>` only
  /// on `presence_diff` frames. `presence_state` frames are ignored.
  ///
  /// Decode failures are swallowed so the stream stays open.
  ///
  /// The stream finishes cleanly (no throw) when the channel closes.
  public func diffs<T: Decodable & Sendable>(
    _ type: T.Type
  ) async -> AsyncStream<PresenceDiff<T>> {
    await channel.registerPresenceDiffs(T.self)
  }
}

// MARK: - Channel + presence accessor

extension Channel {
  /// The presence interface for this channel.
  ///
  /// `nonisolated` — creating a `Presence` shell is always safe; it only stores
  /// a back-reference to `self` with no actor-isolated state access.
  public nonisolated var presence: Presence {
    Presence(channel: self)
  }
}

// MARK: - Channel + presence stream registration

extension Channel {
  /// Registers a per-call presence observe stream.
  ///
  /// Each consumer maintains its own running `active` map (captured in the closure via
  /// `LockIsolated` for `@Sendable` closure compatibility). On each `presence_state` frame
  /// the map is replaced; on each `presence_diff` frame the map is updated incrementally
  /// using phx_ref matching to identify leaving metas. Decode failures are swallowed to
  /// keep the stream open.
  func registerPresenceObserver<T: Decodable & Sendable>(
    _ type: T.Type
  ) -> AsyncStream<PresenceState<T>> {
    let base = _subscribeEvents()
    return AsyncStream<PresenceState<T>> { continuation in
      let task = Task {
        // Per-consumer accumulated active map. Task-local — only this task touches it,
        // so no lock is needed. Value: list of (phx_ref, decoded T) pairs to allow
        // phx_ref-based leave matching.
        var active: [PresenceKey: [(phxRef: String?, value: T)]] = [:]

        for await channelEvent in base {
          switch channelEvent {
          case .terminated:
            // Presence streams finish cleanly (no throw) on channel close.
            continuation.finish()
            return

          case .message(let message):
            guard case .json(let jsonValue) = message.payload else { continue }

            if message.event == .presenceState {
              // Full snapshot: decode with raw refs and replace the accumulated map.
              guard let rawMap = try? decodePresenceStateWithRefs(jsonValue, as: T.self)
              else { continue }
              active = rawMap
              let snapshot = active.mapValues { $0.map(\.value) }
              continuation.yield(PresenceState(active: snapshot, lastDiff: nil))

            } else if message.event == .presenceDiff {
              // Incremental diff: decode once (ref-aware) and derive the public
              // `PresenceDiff<T>` by stripping the phx_refs, avoiding a redundant
              // second decode pass on the same payload.
              guard let rawDiff = try? decodePresenceDiffWithRefs(jsonValue, as: T.self)
              else { continue }
              let diff = PresenceDiff<T>(
                joined: rawDiff.joined.flatMap { key, pairs in pairs.map { (key, $0.value) } },
                left: rawDiff.left.flatMap { key, pairs in pairs.map { (key, $0.value) } }
              )

              // Apply leaves: remove metas matching by phx_ref.
              for (key, leftPairs) in rawDiff.left {
                guard var existing = active[key] else { continue }
                for (leftRef, _) in leftPairs {
                  if let ref = leftRef, let idx = existing.firstIndex(where: { $0.phxRef == ref }) {
                    existing.remove(at: idx)
                  } else if leftRef == nil, !existing.isEmpty {
                    // No phx_ref: fall back to removing the first entry.
                    existing.removeFirst()
                  }
                }
                if existing.isEmpty {
                  active.removeValue(forKey: key)
                } else {
                  active[key] = existing
                }
              }

              // Apply joins: add new metas.
              for (key, joinPairs) in rawDiff.joined {
                active[key, default: []].append(contentsOf: joinPairs)
              }

              let snapshot = active.mapValues { $0.map(\.value) }
              continuation.yield(PresenceState(active: snapshot, lastDiff: diff))
            }
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Registers a per-call presence diffs-only stream.
  ///
  /// Emits only on `presence_diff` frames. `presence_state` frames are ignored.
  /// Decode failures are swallowed to keep the stream open.
  func registerPresenceDiffs<T: Decodable & Sendable>(
    _ type: T.Type
  ) -> AsyncStream<PresenceDiff<T>> {
    let base = _subscribeEvents()
    return AsyncStream<PresenceDiff<T>> { continuation in
      let task = Task {
        for await channelEvent in base {
          switch channelEvent {
          case .terminated:
            continuation.finish()
            return
          case .message(let message):
            guard message.event == .presenceDiff,
              case .json(let jsonValue) = message.payload,
              let diff = try? decodePresenceDiff(jsonValue, as: T.self)
            else { continue }
            continuation.yield(diff)
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

// MARK: - Internal decoders

/// Decodes a `presence_state` wire payload into a keyed dictionary.
///
/// ## Wire shape
/// ```json
/// {
///   "<key>": {
///     "metas": [ { "phx_ref": "...", <userFields> } ]
///   }
/// }
/// ```
/// Each meta object is decoded whole as `T`; extra fields (e.g. `phx_ref`) are ignored
/// by the decoder if `T` does not declare them.
///
/// An empty object `{}` decodes to an empty dictionary.
///
/// - Parameters:
///   - json: The raw `JSONValue` from the `presence_state` Phoenix event payload.
///   - type: The concrete `Decodable` type to decode each meta into.
/// - Returns: A dictionary mapping each presence key to the list of decoded metas.
/// - Throws: `RealtimeError.decoding` if the overall structure is wrong or any meta
///   fails to decode as `T`.
func decodePresenceState<T: Decodable>(
  _ json: JSONValue,
  as type: T.Type
) throws -> [PresenceKey: [T]] {
  guard let topObject = json.objectValue else {
    throw RealtimeError.decoding(
      type: String(describing: T.self),
      underlying: PresenceDecodeError.invalidShape(
        "presence_state root must be a JSON object"
      )
    )
  }

  var result: [PresenceKey: [T]] = [:]

  for (key, keyValue) in topObject {
    guard let keyObject = keyValue.objectValue,
      let metasArray = keyObject["metas"]?.arrayValue
    else {
      throw RealtimeError.decoding(
        type: String(describing: T.self),
        underlying: PresenceDecodeError.invalidShape(
          "presence_state entry '\(key)' must have a 'metas' array"
        )
      )
    }

    var decoded: [T] = []
    for meta in metasArray {
      do {
        let data = try JSONEncoder().encode(meta)
        let value = try JSONDecoder().decode(T.self, from: data)
        decoded.append(value)
      } catch {
        throw RealtimeError.decoding(
          type: String(describing: T.self),
          underlying: error
        )
      }
    }

    result[key] = decoded
  }

  return result
}

/// Decodes a `presence_diff` wire payload into a `PresenceDiff<T>`.
///
/// ## Wire shape
/// ```json
/// {
///   "joins":  { "<key>": { "metas": [ ... ] } },
///   "leaves": { "<key>": { "metas": [ ... ] } }
/// }
/// ```
/// Each key's metas are flattened into the `joined`/`left` arrays as `(key, T)` pairs
/// in the order they appear. Missing `joins` or `leaves` keys are treated as empty.
///
/// - Parameters:
///   - json: The raw `JSONValue` from the `presence_diff` Phoenix event payload.
///   - type: The concrete `Decodable` type to decode each meta into.
/// - Returns: A `PresenceDiff<T>` with flattened joined and left arrays.
/// - Throws: `RealtimeError.decoding` on structural or decode errors.
func decodePresenceDiff<T: Decodable>(
  _ json: JSONValue,
  as type: T.Type
) throws -> PresenceDiff<T> {
  guard let topObject = json.objectValue else {
    throw RealtimeError.decoding(
      type: String(describing: T.self),
      underlying: PresenceDecodeError.invalidShape(
        "presence_diff root must be a JSON object"
      )
    )
  }

  let joinsValue = topObject["joins"] ?? .object([:])
  let leavesValue = topObject["leaves"] ?? .object([:])

  let joinsMap = try decodePresenceState(joinsValue, as: T.self)
  let leavesMap = try decodePresenceState(leavesValue, as: T.self)

  let joined: [(PresenceKey, T)] = joinsMap.flatMap { key, values in
    values.map { (key, $0) }
  }
  let left: [(PresenceKey, T)] = leavesMap.flatMap { key, values in
    values.map { (key, $0) }
  }

  return PresenceDiff(joined: joined, left: left)
}

// MARK: - Internal ref-aware decoders

/// Decodes a `presence_state` payload retaining the `phx_ref` of each meta.
///
/// Returns a map from presence key → list of `(phxRef: String?, value: T)` pairs.
/// Used by `registerPresenceObserver` for leave-matching.
func decodePresenceStateWithRefs<T: Decodable>(
  _ json: JSONValue,
  as type: T.Type
) throws -> [PresenceKey: [(phxRef: String?, value: T)]] {
  guard let topObject = json.objectValue else {
    throw RealtimeError.decoding(
      type: String(describing: T.self),
      underlying: PresenceDecodeError.invalidShape(
        "presence_state root must be a JSON object"
      )
    )
  }

  var result: [PresenceKey: [(phxRef: String?, value: T)]] = [:]

  for (key, keyValue) in topObject {
    guard let keyObject = keyValue.objectValue,
      let metasArray = keyObject["metas"]?.arrayValue
    else {
      throw RealtimeError.decoding(
        type: String(describing: T.self),
        underlying: PresenceDecodeError.invalidShape(
          "presence_state entry '\(key)' must have a 'metas' array"
        )
      )
    }

    var pairs: [(phxRef: String?, value: T)] = []
    for meta in metasArray {
      // Extract phx_ref (if present) before decoding T.
      let phxRef = meta.objectValue?["phx_ref"]?.stringValue
      let data = try JSONEncoder().encode(meta)
      let value = try JSONDecoder().decode(T.self, from: data)
      pairs.append((phxRef: phxRef, value: value))
    }

    result[key] = pairs
  }

  return result
}

/// Decoded presence diff with raw phx_ref information retained.
struct PresenceDiffWithRefs<T: Sendable>: Sendable {
  let joined: [PresenceKey: [(phxRef: String?, value: T)]]
  let left: [PresenceKey: [(phxRef: String?, value: T)]]
}

/// Decodes a `presence_diff` payload retaining phx_ref for each meta.
func decodePresenceDiffWithRefs<T: Decodable>(
  _ json: JSONValue,
  as type: T.Type
) throws -> PresenceDiffWithRefs<T> {
  guard let topObject = json.objectValue else {
    throw RealtimeError.decoding(
      type: String(describing: T.self),
      underlying: PresenceDecodeError.invalidShape(
        "presence_diff root must be a JSON object"
      )
    )
  }

  let joinsValue = topObject["joins"] ?? .object([:])
  let leavesValue = topObject["leaves"] ?? .object([:])

  let joinsMap = try decodePresenceStateWithRefs(joinsValue, as: T.self)
  let leavesMap = try decodePresenceStateWithRefs(leavesValue, as: T.self)

  return PresenceDiffWithRefs(joined: joinsMap, left: leavesMap)
}

// MARK: - PresenceDecodeError

/// Internal sentinel errors for presence payload shape violations.
private enum PresenceDecodeError: Error, Sendable {
  case invalidShape(String)

  var localizedDescription: String {
    switch self {
    case .invalidShape(let msg): "Invalid presence payload shape: \(msg)"
    }
  }
}
