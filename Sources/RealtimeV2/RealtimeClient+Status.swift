import ConcurrencyExtras
import Foundation

extension RealtimeClientV2 {

  /// The current WebSocket connection status.
  ///
  /// Reflects the last value emitted by ``statusChanges()``.
  public var status: RealtimeClientStatus {
    mutableState.status
  }

  /// Returns an async stream of the client's connection status.
  ///
  /// The stream emits the current status at once, then each change. It is registered before
  /// this method returns.
  ///
  /// ```swift
  /// for await status in await client.statusChanges() {
  ///   print("Status changed to \(status)")
  /// }
  /// ```
  ///
  /// > Note: On this version the stream yields the v2 ``RealtimeClientStatus``, which has three
  /// > cases and no payloads. The v3 status adds a `reconnecting` case and carries the error and
  /// > the attempt number.
  public func statusChanges() async -> AsyncStream<RealtimeClientStatus> {
    makeStatusStream()
  }

  /// An async stream that emits connection status changes.
  ///
  /// The stream emits the current status immediately upon iteration and then each
  /// subsequent change.
  @available(*, deprecated, message: "Use statusChanges() instead.")
  public var statusChange: AsyncStream<RealtimeClientStatus> {
    makeStatusStream()
  }

  private func makeStatusStream() -> AsyncStream<RealtimeClientStatus> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<RealtimeClientStatus>.makeStream()
    let lastStatus = mutableState.withValue {
      $0.statusContinuations.append((id, continuation))
      return $0.status
    }

    continuation.onTermination = { [weak self] _ in
      self?.mutableState.withValue {
        $0.statusContinuations.removeAll { $0.0 == id }
      }
    }

    continuation.yield(lastStatus)

    return stream
  }

  /// Registers a closure to be called whenever the connection status changes.
  ///
  /// - Parameter listener: A `@Sendable` closure called with the new ``RealtimeClientStatus`` on every change.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  ///
  @available(*, deprecated, message: "Use statusChanges() instead.")
  public func onStatusChange(
    _ listener: @escaping @Sendable (RealtimeClientStatus) -> Void
  ) -> RealtimeSubscription {
    // Subscribe synchronously, before spawning the observer Task — otherwise
    // a status change could race ahead of the Task actually starting to
    // iterate, silently dropping it (including the initial replay).
    let stream = makeStatusStream()
    let task = Task {
      for await status in stream {
        listener(status)
      }
    }
    return RealtimeSubscription { task.cancel() }
  }

  /// Yields the new status to all registered continuations if it has changed.
  func yieldStatusIfChanged(_ status: RealtimeClientStatus) {
    let continuations: [AsyncStream<RealtimeClientStatus>.Continuation] = mutableState.withValue {
      state in
      guard state.status != status else { return [] }
      state.status = status
      return state.statusContinuations.map { $1 }
    }

    for continuation in continuations {
      continuation.yield(status)
    }
  }
}
