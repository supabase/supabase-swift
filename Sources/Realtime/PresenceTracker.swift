//
//  PresenceTracker.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

package import Helpers

/// Phoenix presence sync for one channel: `presence_state` replaces, `presence_diff` merges by
/// key and `phx_ref`, and diffs that arrive before the first state of a join wait for it.
package struct PresenceTracker: Sendable {
  package private(set) var state = PresenceState()
  private var hasState = false
  private var pendingDiffs: [JSONObject] = []

  package init() {}

  /// Starts a new join. The state stays until the join's first `presence_state`, which is
  /// diffed against it, so a rejoin reports only real joins and leaves.
  package mutating func waitForNextState() {
    hasState = false
    pendingDiffs = []
  }

  /// Ends the subscription: forgets every entry and reports each one as a leave, so the
  /// changes an app has applied add up to the empty state.
  package mutating func clear() -> PresenceChange {
    let change = PresenceChange(leaves: state.entries)
    state = PresenceState()
    waitForNextState()
    return change
  }

  /// Applies a `presence_state` payload and the diffs that were waiting for it.
  package mutating func applyState(_ raw: JSONObject) -> PresenceChange {
    let before = state.entries
    state.entries = Self.decode(raw)
    hasState = true
    for diff in pendingDiffs {
      merge(diff)
    }
    pendingDiffs = []
    return Self.change(from: before, to: state.entries)
  }

  /// Applies a `presence_diff` payload, or queues it (returning `nil`) until the first state.
  package mutating func applyDiff(_ raw: JSONObject) -> PresenceChange? {
    guard hasState else {
      pendingDiffs.append(raw)
      return nil
    }
    let before = state.entries
    let keys = merge(raw)
    return Self.change(from: before, to: state.entries, keys: keys)
  }

  /// Merges a diff into the state and returns the keys it touched.
  @discardableResult
  private mutating func merge(_ raw: JSONObject) -> Set<String> {
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
    return Set(joins.keys).union(leaves.keys)
  }

  /// The entries whose `phx_ref` is only in `new` (joins) or only in `old` (leaves), so a
  /// change never repeats an entry and never reports one the state did not hold.
  private static func change(
    from old: [String: [PresenceEntry]],
    to new: [String: [PresenceEntry]],
    keys: Set<String>? = nil
  ) -> PresenceChange {
    var change = PresenceChange()
    for key in keys ?? Set(old.keys).union(new.keys) {
      let before = old[key] ?? []
      let after = new[key] ?? []
      let joined = after.filter { entry in !before.contains { $0.ref == entry.ref } }
      let left = before.filter { entry in !after.contains { $0.ref == entry.ref } }
      if !joined.isEmpty { change.joins[key] = joined }
      if !left.isEmpty { change.leaves[key] = left }
    }
    return change
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
