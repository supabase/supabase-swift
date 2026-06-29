//
//  Channel+Presence.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Helpers

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
/// The handle must be explicitly cancelled to untrack. Dropping it without cancelling does
/// NOT untrack — but when `leave()` is called on any holder of the topic, the slot is
/// implicitly torn down server-side.
public final class PresenceHandle: Sendable {
  /// Update the current presence meta for this slot.
  ///
  /// - Note: Implemented in Task 24.
  public func update<T: Codable & Sendable>(_ state: T) async throws(RealtimeError) {
    // Implemented in Task 24.
  }

  /// Idempotent; awaits server ACK of the untrack.
  ///
  /// - Note: Implemented in Task 24.
  public func cancel() async throws(RealtimeError) {
    // Implemented in Task 24.
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
  /// - Note: Implemented in Task 24.
  public func track<T: Codable & Sendable>(
    _ state: T
  ) async throws(RealtimeError) -> PresenceHandle {
    // Implemented in Task 24.
    throw RealtimeError.notSubscribed
  }

  /// Snapshot + diff stream of all presences, keyed by presence key.
  ///
  /// - Note: Implemented in Task 25.
  public func observe<T: Decodable & Sendable>(
    _ type: T.Type
  ) -> AsyncStream<PresenceState<T>> {
    // Implemented in Task 25.
    let (stream, continuation) = AsyncStream<PresenceState<T>>.makeStream()
    continuation.finish()
    return stream
  }

  /// Incremental diffs only.
  ///
  /// - Note: Implemented in Task 25.
  public func diffs<T: Decodable & Sendable>(
    _ type: T.Type
  ) -> AsyncStream<PresenceDiff<T>> {
    // Implemented in Task 25.
    let (stream, continuation) = AsyncStream<PresenceDiff<T>>.makeStream()
    continuation.finish()
    return stream
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
