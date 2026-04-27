//
//  Channel+Presence.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

extension Channel {
  public var presence: Presence { Presence(channel: self) }

  /// Returns topic and joinRef atomically (both read while holding actor isolation).
  func presenceTrackInfo() -> (topic: String, joinRef: String?) {
    (topic, joinRef)
  }

  func registerTrack(id: UUID, state: [String: JSONValue]) {
    trackedStates[id] = state
  }

  func unregisterTrack(id: UUID) {
    trackedStates.removeValue(forKey: id)
  }

  func registerSnapshotHandler(
    id: UUID,
    onSnapshot: @escaping @Sendable ([String: JSONValue]) -> Void,
    finish: @escaping @Sendable () -> Void
  ) {
    presenceSnapshotHandlers[id] = onSnapshot
    presenceFinishHandlers[id] = finish
  }

  func registerDiffHandler(
    id: UUID,
    onDiff: @escaping @Sendable ([String: JSONValue]) -> Void,
    finish: @escaping @Sendable () -> Void
  ) {
    presenceDiffHandlers[id] = onDiff
    presenceFinishHandlers[id] = finish
  }

  func unregisterPresenceHandlers(id: UUID) {
    presenceSnapshotHandlers.removeValue(forKey: id)
    presenceDiffHandlers.removeValue(forKey: id)
    presenceFinishHandlers.removeValue(forKey: id)
  }
}
