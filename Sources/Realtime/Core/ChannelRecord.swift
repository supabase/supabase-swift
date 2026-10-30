//
//  ChannelRecord.swift
//  Realtime
//

/// What the core knows about one channel. ``RealtimeCore`` creates it on the first command for a
/// topic, and `removeChannel` deletes it.
struct ChannelRecord {
  let configuration: RealtimeChannelConfiguration
  var phase: Phase = .unsubscribed
  /// Whether the channel joined at least once, so the next join is a rejoin.
  var hasBeenSubscribed = false
  /// The client's Postgres bindings, in registration order.
  var bindings: [PostgresJoinConfig] = []
  /// Whether a presence stream is open, so the join turns presence on.
  var presenceEnabled = false
  /// The bindings the server echoed in the join reply, with their ids.
  var serverChanges: [PostgresJoinConfig] = []
  var presence = PresenceTracker()
  /// The ref of the join that timed out while the channel waits to rejoin. A late `ok` for it
  /// still confirms the join.
  var timedOutJoinRef: Ref?
  /// The access token the channel last joined with.
  var joinAccessToken: String?
  var subscribeWaiters: [WaiterID] = []
  var leaveWaiters: [WaiterID] = []
  /// The pushes that wait for a reply, by ref.
  var pendingPushes: [Ref: WaiterID] = [:]

  init(configuration: RealtimeChannelConfiguration) {
    self.configuration = configuration
  }

  /// What a `phx_join` waits for.
  enum JoinStage: Equatable {
    /// The join reply.
    case reply
    /// The `system` message that says the Postgres changes subscriptions are ready.
    case postgres
  }

  enum Phase: Equatable {
    case unsubscribed
    case waitingForSocket(attempt: Int)
    case refreshingToken(attempt: Int)
    case joining(ref: Ref, attempt: Int, stage: JoinStage)
    case waitingToRetry(attempt: Int, retryIn: Duration, lastError: RealtimeError)
    case subscribed(joinRef: Ref)
    case leaving(joinRef: Ref, leaveRef: Ref)
    case failed(RealtimeError)

    /// The phase as the channel publishes it.
    var status: RealtimeChannelStatus {
      switch self {
      case .unsubscribed:
        .unsubscribed
      case .waitingForSocket(let attempt), .refreshingToken(let attempt),
        .joining(_, let attempt, _):
        .subscribing(attempt: attempt)
      case .waitingToRetry(let attempt, let retryIn, let lastError):
        .resubscribing(attempt: attempt, retryIn: retryIn, lastError: lastError)
      case .subscribed:
        .subscribed
      case .leaving:
        .unsubscribing
      case .failed(let error):
        .failed(error)
      }
    }

    static func == (lhs: Phase, rhs: Phase) -> Bool {
      switch (lhs, rhs) {
      case (.unsubscribed, .unsubscribed):
        return true
      case (.waitingForSocket(let a), .waitingForSocket(let b)),
        (.refreshingToken(let a), .refreshingToken(let b)):
        return a == b
      case (.joining(let ra, let a, let sa), .joining(let rb, let b, let sb)):
        return ra == rb && a == b && sa == sb
      case (.waitingToRetry(let a, let da, let ea), .waitingToRetry(let b, let db, let eb)):
        return a == b && da == db && ea.isSameFailure(as: eb)
      case (.subscribed(let a), .subscribed(let b)):
        return a == b
      case (.leaving(let ja, let la), .leaving(let jb, let lb)):
        return ja == jb && la == lb
      case (.failed(let a), .failed(let b)):
        return a.isSameFailure(as: b)
      default:
        return false
      }
    }
  }
}
