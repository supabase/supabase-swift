//
//  ConnectionStatusBroadcaster.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 30/06/26.
//

import Foundation

/// Holds the current `ConnectionStatus` and fans transitions out to all `status` stream
/// subscribers.
///
/// A value type held as an actor-isolated stored property of `Realtime`; every method runs on
/// `Realtime`'s executor, so no internal locking is needed. The single source of truth for the
/// client's connection status, separated from the socket mechanism that drives it.
struct ConnectionStatusBroadcaster {
  /// The most recent status. New subscribers are seeded with this value.
  private(set) var current: ConnectionStatus
  private var continuations: [UUID: AsyncStream<ConnectionStatus>.Continuation] = [:]

  init(initial: ConnectionStatus) {
    self.current = initial
  }

  /// Registers a new subscriber, seeded with `current`, and returns its stream.
  ///
  /// `onTerminate` is invoked (with the subscriber's id) when the stream is cancelled or
  /// finished, so the owner can hop back onto its executor and call `remove(_:)`.
  mutating func makeStream(
    onTerminate: @escaping @Sendable (UUID) -> Void
  ) -> AsyncStream<ConnectionStatus> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
    continuation.yield(current)
    continuations[id] = continuation
    continuation.onTermination = { _ in onTerminate(id) }
    return stream
  }

  /// Updates `current` and yields it to every subscriber.
  mutating func emit(_ status: ConnectionStatus) {
    current = status
    for continuation in continuations.values {
      continuation.yield(status)
    }
  }

  /// Removes a finished/cancelled subscriber.
  mutating func remove(_ id: UUID) {
    continuations.removeValue(forKey: id)
  }
}
