import ConcurrencyExtras
import Foundation

extension RealtimeClientV2 {

  /// An async stream that emits heartbeat status updates.
  ///
  /// The client sends a heartbeat at each ``RealtimeClientOptions/defaultHeartbeatInterval``
  /// interval to keep the connection alive. Use ``onHeartbeat(_:)`` for a closure-based alternative.
  ///
  /// ```swift
  /// for await beat in client.heartbeat {
  ///   print("Heartbeat: \(beat)")
  /// }
  /// ```
  public var heartbeat: AsyncStream<HeartbeatStatus> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<HeartbeatStatus>.makeStream()
    let lastHeartbeatStatus = mutableState.withValue {
      $0.heartbeatStatusContinuations.append((id, continuation))
      return $0.lastHeartbeatStatus
    }

    continuation.onTermination = { [weak self] _ in
      self?.mutableState.withValue {
        $0.heartbeatStatusContinuations.removeAll { $0.0 == id }
      }
    }

    if let lastHeartbeatStatus {
      continuation.yield(lastHeartbeatStatus)
    }

    return stream
  }

  /// Registers a closure to be called on every heartbeat cycle.
  ///
  /// - Parameter listener: A `@Sendable` closure called with the latest ``HeartbeatStatus``.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  ///
  /// > Note: Use ``heartbeat`` if you prefer async iteration over closures.
  public func onHeartbeat(
    _ listener: @escaping @Sendable (HeartbeatStatus) -> Void
  ) -> RealtimeSubscription {
    // Subscribe synchronously, before spawning the observer Task — otherwise
    // a heartbeat could race ahead of the Task actually starting to iterate,
    // silently dropping it.
    let stream = heartbeat
    let task = Task {
      for await beat in stream {
        listener(beat)
      }
    }
    return RealtimeSubscription { task.cancel() }
  }

  /// Yields a heartbeat status to all registered listeners.
  func yieldHeartbeatStatus(_ status: HeartbeatStatus) {
    let continuations = mutableState.withValue { state in
      state.lastHeartbeatStatus = status
      return state.heartbeatStatusContinuations.map { $1 }
    }

    for continuation in continuations {
      continuation.yield(status)
    }
  }
}
