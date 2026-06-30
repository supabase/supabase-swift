//
//  ChannelRegistry.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 30/06/26.
//

import Foundation

/// The topic → `Channel` collection owned by `Realtime`.
///
/// A value type held as an actor-isolated stored property of `Realtime`; every method runs on
/// `Realtime`'s executor, so no internal locking is needed. Encapsulates the keyed lookup,
/// insertion, eviction, and snapshotting that the connect, reconnect, frame-routing, and
/// token-update paths all need — keeping the raw dictionary out of those call sites.
///
/// Topic strings are the `realtime:`-prefixed form (see `Realtime.channel(_:)`).
struct ChannelRegistry {
  private var channels: [String: Channel] = [:]

  /// The channel currently registered for `topic`, if any.
  func channel(for topic: String) -> Channel? {
    channels[topic]
  }

  /// Registers `channel` under `topic` (first-call-wins is enforced by the caller).
  mutating func insert(_ channel: Channel, for topic: String) {
    channels[topic] = channel
  }

  /// Removes the channel registered for `topic`, if any.
  mutating func remove(topic: String) {
    channels.removeValue(forKey: topic)
  }

  /// A snapshot of all registered channels (for concurrent rejoin / token push).
  var all: [Channel] {
    Array(channels.values)
  }

  /// A snapshot of all registered `(topic, channel)` pairs (for give-up eviction).
  var allByTopic: [(topic: String, channel: Channel)] {
    channels.map { (topic: $0.key, channel: $0.value) }
  }
}
