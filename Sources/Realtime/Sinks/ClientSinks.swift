//
//  ClientSinks.swift
//  Realtime
//

import ConcurrencyExtras

/// The published status and heartbeats of one client, and its channel registry.
///
/// Callers read, subscribe, and look up channels from any context. Only the client yields, so the
/// elements of each broadcaster arrive in the order the client yields them.
final class ClientSinks: Sendable {
  let status = Broadcaster<RealtimeClientStatus>(retaining: .disconnected(nil))
  /// Retains nothing until the first heartbeat, then replays the latest one.
  let heartbeats = Broadcaster<HeartbeatEvent>(retaining: nil)

  private struct Registry {
    /// The channels by their ``RealtimeChannel/topic``.
    var channels: [String: RealtimeChannel] = [:]
    /// The last ``ChannelID`` issued.
    var lastID: UInt64 = 0
  }

  private let registry = LockIsolated(Registry())

  /// The channel registered for `topic`, or the one `make` returns for a new ``ChannelID``,
  /// registered under the same lock so concurrent callers get one instance.
  func channel(
    for topic: String, orInsert make: @Sendable (ChannelID) -> RealtimeChannel
  ) -> RealtimeChannel {
    registry.withValue { registry in
      if let channel = registry.channels[topic] { return channel }
      registry.lastID += 1
      let channel = make(ChannelID(rawValue: registry.lastID))
      registry.channels[topic] = channel
      return channel
    }
  }

  func channel(for topic: String) -> RealtimeChannel? {
    registry.value.channels[topic]
  }

  /// The registered channel with `id`.
  func channel(withID id: ChannelID) -> RealtimeChannel? {
    registry.value.channels.values.first { $0.id == id }
  }

  /// Removes `channel` only while its topic still maps to it: a newer channel created for the
  /// same topic after `channel` was removed stays registered.
  func removeChannel(_ channel: RealtimeChannel) {
    registry.withValue { registry in
      if registry.channels[channel.topic] === channel {
        registry.channels[channel.topic] = nil
      }
    }
  }

  var channels: [RealtimeChannel] {
    Array(registry.value.channels.values)
  }

  /// Ends every status and heartbeat stream.
  func finishAll() {
    status.finish()
    heartbeats.finish()
  }
}
