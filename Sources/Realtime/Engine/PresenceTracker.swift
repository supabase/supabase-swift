//
//  PresenceTracker.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

public import Foundation
package import Helpers

/// One tracked client under a presence key. A key holds one entry per device or tab.
public struct PresenceEntry: Sendable, Hashable {
  /// The server's `phx_ref`.
  public var ref: String
  /// The `phx_ref` this entry replaced, on an update.
  public var previousRef: String?
  /// The tracked payload, without the `phx_ref` fields.
  public var payload: JSONObject

  package init(ref: String, previousRef: String? = nil, payload: JSONObject) {
    self.ref = ref
    self.previousRef = previousRef
    self.payload = payload
  }

  /// Decodes the tracked payload as `T`.
  ///
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/decoding`` when the payload does not
  ///   decode.
  public func decode<T: Decodable>(
    as _: T.Type = T.self, decoder: JSONDecoder = .supabase()
  ) throws -> T {
    do {
      return try JSONValue.object(payload).decode(as: T.self, decoder: decoder)
    } catch {
      throw RealtimeError(
        kind: .decoding, message: "presence entry \(ref) did not decode as \(T.self)",
        underlyingError: error)
    }
  }
}

/// Everyone present on a channel, by presence key.
public struct PresenceState: Sendable, Hashable {
  /// Every entry under each key. A key has one entry per device or tab that tracks with it.
  public var entries: [String: [PresenceEntry]]

  package init(entries: [String: [PresenceEntry]] = [:]) {
    self.entries = entries
  }

  /// Decodes the payload of every entry as `T`, keeping the keys.
  ///
  /// - Parameters:
  ///   - type: The type to decode each payload as.
  ///   - decoder: The decoder for each payload.
  ///   - ignoringUndecodable: When `true`, an entry that does not decode is skipped, and a key
  ///     whose entries all fail is left out. When `false`, the first failure throws.
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/decoding`` when
  ///   `ignoringUndecodable` is `false` and an entry does not decode.
  public func decode<T: Decodable>(
    as type: T.Type, decoder: JSONDecoder = .supabase(), ignoringUndecodable: Bool = true
  ) throws -> [String: [T]] {
    var decoded: [String: [T]] = [:]
    for (key, entries) in self.entries {
      let values: [T] =
        if ignoringUndecodable {
          entries.compactMap { try? $0.decode(as: T.self, decoder: decoder) }
        } else {
          try entries.map { try $0.decode(as: T.self, decoder: decoder) }
        }
      if !values.isEmpty { decoded[key] = values }
    }
    return decoded
  }
}

/// The entries that joined and left in one presence update.
public struct PresenceChange: Sendable, Hashable {
  /// The entries that joined, by presence key. An updated entry joins with its new payload.
  public var joins: [String: [PresenceEntry]]
  /// The entries that left, by presence key.
  public var leaves: [String: [PresenceEntry]]

  package init(joins: [String: [PresenceEntry]] = [:], leaves: [String: [PresenceEntry]] = [:]) {
    self.joins = joins
    self.leaves = leaves
  }
}

/// Phoenix presence sync for one channel: `presence_state` replaces, `presence_diff` merges by
/// key and `phx_ref`, and diffs that arrive before the first state of a join wait for it.
package struct PresenceTracker: Sendable {
  package private(set) var state = PresenceState()
  /// The payload of the last `track`, re-sent after every rejoin until `untrack`.
  package var trackedPayload: JSONObject?
  private var hasState = false
  private var pendingDiffs: [JSONObject] = []

  package init() {}

  /// Forgets the server's view at a rejoin. The tracked payload survives so it can be re-sent.
  package mutating func reset() {
    state = PresenceState()
    hasState = false
    pendingDiffs = []
  }

  /// Applies a `presence_state` payload and the diffs that were waiting for it.
  package mutating func applyState(_ raw: JSONObject) -> PresenceChange {
    let incoming = Self.decode(raw)
    var change = PresenceChange()
    for (key, entries) in state.entries {
      let remaining = incoming[key] ?? []
      let gone = entries.filter { entry in !remaining.contains { $0.ref == entry.ref } }
      if !gone.isEmpty { change.leaves[key] = gone }
    }
    for (key, entries) in incoming {
      let known = state.entries[key] ?? []
      let new = entries.filter { entry in !known.contains { $0.ref == entry.ref } }
      if !new.isEmpty { change.joins[key] = new }
    }
    state.entries = incoming
    hasState = true
    for diff in pendingDiffs {
      let applied = merge(diff)
      change.joins.merge(applied.joins) { $0 + $1 }
      change.leaves.merge(applied.leaves) { $0 + $1 }
    }
    pendingDiffs = []
    return change
  }

  /// Applies a `presence_diff` payload, or queues it (returning `nil`) until the first state.
  package mutating func applyDiff(_ raw: JSONObject) -> PresenceChange? {
    guard hasState else {
      pendingDiffs.append(raw)
      return nil
    }
    return merge(raw)
  }

  private mutating func merge(_ raw: JSONObject) -> PresenceChange {
    let joins = Self.decode(raw["joins"]?.objectValue ?? [:])
    let leaves = Self.decode(raw["leaves"]?.objectValue ?? [:])
    for (key, entries) in joins {
      let refs = Set(entries.map(\.ref))
      let kept = (state.entries[key] ?? []).filter { !refs.contains($0.ref) }
      state.entries[key] = kept + entries
    }
    for (key, entries) in leaves {
      let refs = Set(entries.map(\.ref))
      let kept = (state.entries[key] ?? []).filter { !refs.contains($0.ref) }
      state.entries[key] = kept.isEmpty ? nil : kept
    }
    return PresenceChange(joins: joins, leaves: leaves)
  }

  /// `{key: {metas: [{phx_ref, phx_ref_prev?, …payload}]}}`, skipping metas without a ref.
  private static func decode(_ raw: JSONObject) -> [String: [PresenceEntry]] {
    var entries: [String: [PresenceEntry]] = [:]
    for (key, value) in raw {
      let metas = value.objectValue?["metas"]?.arrayValue ?? []
      let decoded = metas.compactMap { meta -> PresenceEntry? in
        guard var payload = meta.objectValue, let ref = payload["phx_ref"]?.stringValue else {
          return nil
        }
        payload["phx_ref"] = nil
        let previousRef = payload.removeValue(forKey: "phx_ref_prev")?.stringValue
        return PresenceEntry(ref: ref, previousRef: previousRef, payload: payload)
      }
      if !decoded.isEmpty { entries[key] = decoded }
    }
    return entries
  }
}
