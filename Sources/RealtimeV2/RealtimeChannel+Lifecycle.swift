import ConcurrencyExtras
public import Foundation

/// The SDK-issued identity of one concrete join incarnation for a retained Realtime channel.
///
/// The identity pairs the Phoenix join reference with an SDK-generated UUID, so distinct join
/// lifecycles remain distinguishable even if a transport reuses a textual join reference.
public struct RealtimeChannelJoinIdentity: Hashable, Sendable {
  /// The SDK-generated identifier for this logical join lifecycle.
  public let id: UUID

  /// The Phoenix join reference assigned to this join incarnation.
  public let joinReference: String

  init(id: UUID = UUID(), joinReference: String) {
    self.id = id
    self.joinReference = joinReference
  }
}

/// One causally ordered lifecycle event for a retained Realtime channel.
///
/// Join identity is assigned inside the SDK. Join start, invalidation, status, and accepted
/// system messages are emitted through the same sequence so a consumer never has to merge
/// independent status and system-event streams.
public enum RealtimeChannelLifecycleEvent: Sendable {
  /// A new authoritative join identity became current for the channel.
  case joinStarted(RealtimeChannelJoinIdentity)

  /// The supplied join identity ceased to be current because its transport or channel closed.
  case joinInvalidated(RealtimeChannelJoinIdentity)

  /// The channel status changed while the optional identity was current.
  case statusChanged(RealtimeChannelStatus, join: RealtimeChannelJoinIdentity?)

  /// A system message was validated as belonging to the supplied current join identity.
  case system(RealtimeMessageV2, join: RealtimeChannelJoinIdentity)
}

extension RealtimeChannelV2 {
  struct LifecycleStorage: Sendable {
    var continuations: [(UUID, AsyncStream<RealtimeChannelLifecycleEvent>.Continuation)] = []
  }

  /// Returns a single ordered stream of authoritative channel lifecycle events.
  ///
  /// Events are ordered for this channel and associate join-scoped transitions with the identity
  /// that produced them. Use the carried identity when correlating reconnect or recovery behavior.
  /// Register before subscribing. The same stream remains valid across native reconnects and
  /// retained-channel rejoins.
  public func lifecycleEvents() -> AsyncStream<RealtimeChannelLifecycleEvent> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<RealtimeChannelLifecycleEvent>.makeStream()
    lifecycleStorage.withValue { $0.continuations.append((id, continuation)) }

    continuation.onTermination = { [weak self] _ in
      self?.lifecycleStorage.withValue {
        $0.continuations.removeAll { $0.0 == id }
      }
    }
    return stream
  }

  func yieldLifecycleEvent(_ event: RealtimeChannelLifecycleEvent) {
    let continuations = lifecycleStorage.value.continuations.map { $1 }
    for continuation in continuations {
      continuation.yield(event)
    }
  }
}
