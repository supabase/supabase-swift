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
  /// The bindings the last `phx_join` carried.
  var joinedBindings: [PostgresJoinConfig] = []
  /// The bindings the server echoed in the join reply, with their ids.
  var serverChanges: [PostgresJoinConfig] = []
  var presence = PresenceTracker()
  /// The ref of the join that timed out while the channel waits to rejoin. A late `ok` for it
  /// still confirms the join.
  var timedOutJoinRef: Ref?
  /// The access token the channel last joined with.
  var joinAccessToken: String?
  /// Whether the channel already rejoined with a fresh token in this run of expired-token join
  /// errors. Another failure ends the run.
  var hasRefreshedExpiredToken = false
  var subscribeWaiters: [WaiterID] = []
  /// Whether the SDK started the join in flight, after a socket loss or for new bindings. It
  /// goes on when the subscribe callers that joined it cancel.
  var isAutomaticRejoin = false
  var leaveWaiters: [WaiterID] = []
  /// Whether `removeChannel` is waiting for the leave to end: the channel is then finished and
  /// dropped, and a subscribe fails.
  var isRemoving = false
  /// The pushes that wait for a reply, by ref.
  var pendingPushes: [Ref: WaiterID] = [:]

  init(configuration: RealtimeChannelConfiguration) {
    self.configuration = configuration
  }

  /// The ref of the join the server can still confirm, or already confirmed.
  var currentJoinRef: Ref? {
    switch phase {
    case .joining(let ref, _, _), .subscribed(let ref):
      ref
    case .waitingToRetry:
      timedOutJoinRef
    case .unsubscribed, .waitingForSocket, .refreshingToken, .leaving, .failed:
      nil
    }
  }

  /// Whether the current join waits for "Subscribed to PostgreSQL", so only that message
  /// confirms it.
  var awaitsPostgresChanges: Bool {
    switch phase {
    case .joining(_, _, .postgres):
      true
    case .joining(_, _, .reply):
      joinWaitsForPostgresChanges
    case .waitingToRetry:
      timedOutJoinRef != nil && joinWaitsForPostgresChanges
    case .unsubscribed, .waitingForSocket, .refreshingToken, .subscribed, .leaving, .failed:
      false
    }
  }

  /// Whether the last join needs "Subscribed to PostgreSQL" after its reply: it has bindings,
  /// and the server does not hold the reply until they are set up.
  var joinWaitsForPostgresChanges: Bool {
    !joinedBindings.isEmpty && !configuration.postgresChanges.waitForSubscription
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
