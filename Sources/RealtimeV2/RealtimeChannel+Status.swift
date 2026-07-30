import ConcurrencyExtras
import Foundation

extension RealtimeChannelV2 {

  struct StatusStorage: Sendable {
    var status: RealtimeChannelStatus = .unsubscribed
    var continuations: [(UUID, AsyncStream<RealtimeChannelStatus>.Continuation)] = []
  }

  /// The current subscription status of the channel.
  public var status: RealtimeChannelStatus {
    statusStorage.value.status
  }

  /// An async stream that emits channel subscription status changes.
  ///
  /// The stream emits the current status immediately upon iteration and then each
  /// subsequent change. Use ``onStatusChange(_:)`` for a closure-based alternative.
  public var statusChange: AsyncStream<RealtimeChannelStatus> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<RealtimeChannelStatus>.makeStream()
    let lastStatus = statusStorage.withValue {
      $0.continuations.append((id, continuation))
      return $0.status
    }

    continuation.onTermination = { [weak self] _ in
      self?.statusStorage.withValue {
        $0.continuations.removeAll { $0.0 == id }
      }
    }

    continuation.yield(lastStatus)

    return stream
  }

  /// Registers a closure to be called whenever the channel subscription status changes.
  ///
  /// - Parameter listener: A `@Sendable` closure called with the new ``RealtimeChannelStatus`` on every change.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  ///
  /// > Note: Use ``statusChange`` if you prefer async iteration over closures.
  public func onStatusChange(
    _ listener: @escaping @Sendable (RealtimeChannelStatus) -> Void
  ) -> RealtimeSubscription {
    // Subscribe synchronously, before spawning the observer Task — otherwise
    // a status change could race ahead of the Task actually starting to
    // iterate, silently dropping it (including the initial replay).
    let stream = statusChange
    let task = Task {
      for await status in stream {
        listener(status)
      }
    }
    return RealtimeSubscription { task.cancel() }
  }

  /// Yields the new status to all registered continuations.
  ///
  /// Snapshots subscribers under the lock, then resumes them outside of it —
  /// resuming a continuation can synchronously reach into the Swift runtime's
  /// task status-record lock, and holding our own lock at the same time would
  /// invert lock order with cancellation and deadlock (see supabase-swift#1154).
  func yieldStatus(_ status: RealtimeChannelStatus) {
    let continuations: [AsyncStream<RealtimeChannelStatus>.Continuation] = statusStorage.withValue {
      state in
      state.status = status
      return state.continuations.map { $1 }
    }

    for continuation in continuations {
      continuation.yield(status)
    }
  }
}
