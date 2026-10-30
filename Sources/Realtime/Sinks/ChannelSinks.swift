//
//  ChannelSinks.swift
//  Realtime
//

import ConcurrencyExtras

/// A Postgres change and the bindings the server matched it to.
struct PostgresDelivery: Sendable, Equatable {
  let change: PostgresChange
  let matched: [PostgresJoinConfig]
}

/// The published status, presence state, and event streams of one channel.
///
/// Callers read and subscribe from any context. Only the channel writes, so the elements of each
/// broadcaster arrive in the order the channel yields them.
final class ChannelSinks: Sendable {
  let status = Broadcaster<RealtimeChannelStatus>(retaining: .unsubscribed)
  let events = Broadcaster<RealtimeChannelEvent>()
  let broadcasts = Broadcaster<BroadcastMessage>()
  let presenceChanges = Broadcaster<PresenceChange>()
  let presenceStates = Broadcaster<PresenceState>(retaining: PresenceState())
  let postgres = Broadcaster<PostgresDelivery>()

  private struct Bindings {
    var entries: [(id: UInt64, config: PostgresJoinConfig)] = []
    var nextID: UInt64 = 0
  }

  private let openBindings = LockIsolated(Bindings())
  private let spent = LockIsolated(false)

  /// The bindings of the open Postgres changes streams, in registration order. The order fixes
  /// the `postgres_changes` array of the join payload.
  var bindings: [PostgresJoinConfig] {
    openBindings.withValue { $0.entries.map(\.config) }
  }

  /// Whether a presence stream is open: that is what turns presence on in the join payload.
  var hasPresenceListener: Bool {
    presenceChanges.subscriberCount + presenceStates.subscriberCount > 0
  }

  /// Whether ``finishAll()`` ran. A spent channel's streams end at once.
  var isSpent: Bool {
    spent.value
  }

  /// Registers `config` and returns the changes the server matches to it. The binding goes away
  /// when the stream ends.
  func postgresChanges(_ config: PostgresJoinConfig) -> AsyncStream<PostgresChange> {
    let id = openBindings.withValue { bindings in
      bindings.nextID += 1
      bindings.entries.append((bindings.nextID, config))
      return bindings.nextID
    }
    let deliveries = postgres.subscribe(
      where: { delivery in delivery.matched.contains { $0 == config } },
      onTermination: { [weak self] in self?.removeBinding(id) }
    )
    return AsyncStream(deliveries.map { $0.change })
  }

  /// Marks the sinks spent and ends every stream.
  func finishAll() {
    spent.setValue(true)
    status.finish()
    events.finish()
    broadcasts.finish()
    presenceChanges.finish()
    presenceStates.finish()
    postgres.finish()
  }

  private func removeBinding(_ id: UInt64) {
    openBindings.withValue { $0.entries.removeAll { $0.id == id } }
  }
}
