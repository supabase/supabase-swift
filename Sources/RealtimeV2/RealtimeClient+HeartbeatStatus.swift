import ConcurrencyExtras
import Foundation

/// One step of the heartbeat cycle, as the client records it.
enum HeartbeatSignal: Sendable {
  case sent
  case acknowledged(latency: Duration)
  case error
  case timedOut
}

struct HeartbeatObserver: Sendable {
  var yield: @Sendable (HeartbeatSignal) -> Void
  var finish: @Sendable () -> Void
}

extension RealtimeClientV2 {

  /// Returns an async stream of the client's heartbeat cycle.
  ///
  /// The client sends a heartbeat at each heartbeat interval to keep the connection alive. The
  /// stream emits ``HeartbeatEvent/sent`` when it does, ``HeartbeatEvent/acknowledged(latency:)``
  /// when the server answers, and ``HeartbeatEvent/timedOut`` when the next heartbeat is due and
  /// the server has not answered the previous one.
  ///
  /// ```swift
  /// for await event in await client.heartbeats() {
  ///   if case .acknowledged(let latency) = event {
  ///     print("Round trip: \(latency)")
  ///   }
  /// }
  /// ```
  ///
  /// > Note: On this version the stream first replays the last event, when there is one, as
  /// > ``heartbeat`` does. It does not report an error reply from the server; v3 has no event
  /// > for it.
  public func heartbeats() async -> AsyncStream<HeartbeatEvent> {
    let (stream, continuation) = AsyncStream<HeartbeatEvent>.makeStream()
    let removeObserver = observeHeartbeats(
      HeartbeatObserver(
        yield: { signal in
          switch signal {
          case .sent: continuation.yield(.sent)
          case .acknowledged(let latency): continuation.yield(.acknowledged(latency: latency))
          case .timedOut: continuation.yield(.timedOut)
          case .error: break
          }
        },
        finish: { continuation.finish() }
      )
    )
    continuation.onTermination = { _ in removeObserver() }
    return stream
  }

  /// An async stream that emits heartbeat status updates.
  ///
  /// The client sends a heartbeat at each ``RealtimeClientOptions/defaultHeartbeatInterval``
  /// interval to keep the connection alive. Use ``onHeartbeat(_:)`` for a closure-based alternative.
  @available(*, deprecated, message: "Use heartbeats() instead.")
  public var heartbeat: AsyncStream<HeartbeatStatus> {
    let (stream, continuation) = AsyncStream<HeartbeatStatus>.makeStream()
    let removeObserver = observeHeartbeats(
      HeartbeatObserver(
        yield: { signal in
          switch signal {
          case .sent: continuation.yield(.sent)
          case .acknowledged: continuation.yield(.ok)
          case .error: continuation.yield(.error)
          case .timedOut: continuation.yield(.timeout)
          }
        },
        finish: { continuation.finish() }
      )
    )
    continuation.onTermination = { _ in removeObserver() }
    return stream
  }

  /// Registers a closure to be called on every heartbeat cycle.
  ///
  /// - Parameter listener: A `@Sendable` closure called with the latest ``HeartbeatStatus``.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  @available(*, deprecated, message: "Use heartbeats() instead.")
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

  /// Registers `observer` and replays the last signal to it. Call the result to remove it.
  private func observeHeartbeats(_ observer: HeartbeatObserver) -> @Sendable () -> Void {
    let id = UUID()
    let lastSignal = mutableState.withValue {
      $0.heartbeatObservers.append((id, observer))
      return $0.lastHeartbeatSignal
    }

    if let lastSignal {
      observer.yield(lastSignal)
    }

    return { [weak self] in
      self?.mutableState.withValue {
        $0.heartbeatObservers.removeAll { $0.0 == id }
      }
    }
  }

  /// Yields a heartbeat signal to all registered listeners.
  func yieldHeartbeatSignal(_ signal: HeartbeatSignal) {
    let observers = mutableState.withValue { state in
      state.lastHeartbeatSignal = signal
      return state.heartbeatObservers.map { $1 }
    }

    for observer in observers {
      observer.yield(signal)
    }
  }
}
