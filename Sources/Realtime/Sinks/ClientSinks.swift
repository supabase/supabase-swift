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

  /// The channels by their ``RealtimeChannel/topic``.
  private let registry = LockIsolated<[String: RealtimeChannel]>([:])

  /// The channel registered for `topic`, or the one `make` returns, registered under the same
  /// lock so concurrent callers get one instance.
  func channel(
    for topic: String, orInsert make: @Sendable () -> RealtimeChannel
  ) -> RealtimeChannel {
    registry.withValue { channels in
      if let channel = channels[topic] { return channel }
      let channel = make()
      channels[topic] = channel
      return channel
    }
  }

  func channel(for topic: String) -> RealtimeChannel? {
    registry.value[topic]
  }

  /// Removes `channel` only while its topic still maps to it: a newer channel created for the
  /// same topic after `channel` was removed stays registered.
  func removeChannel(_ channel: RealtimeChannel) {
    registry.withValue { channels in
      if channels[channel.topic] === channel {
        channels[channel.topic] = nil
      }
    }
  }

  var channels: [RealtimeChannel] {
    Array(registry.value.values)
  }

  /// Ends every status and heartbeat stream.
  func finishAll() {
    status.finish()
    heartbeats.finish()
  }
}
