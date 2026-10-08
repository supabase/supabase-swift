//
//  ChannelMachine.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

/// The channel lifecycle as a pure function of state and event.
///
/// Same contract as ``ConnectionMachine``: the engine feeds events in and performs the effects.
/// The state is the channel status; no effect carries one or an error.
package enum ChannelMachine {
  package enum State: Sendable {
    case unsubscribed
    /// `isRejoin` is true after any earlier join on this channel, so a successful join knows to
    /// report the discontinuity.
    case subscribing(attempt: Int, isRejoin: Bool)
    case subscribed
    /// `retryIn == .zero` means the rejoin waits for the socket or a fresh token, not a timer.
    case resubscribing(attempt: Int, retryIn: Duration, lastError: RealtimeError)
    case unsubscribing
    case failed(RealtimeError)

    package var isSubscribed: Bool {
      if case .subscribed = self { return true }
      return false
    }

    package var error: RealtimeError? {
      switch self {
      case .resubscribing(_, _, let error): error
      case .failed(let error): error
      case .unsubscribed, .subscribing, .subscribed, .unsubscribing: nil
      }
    }
  }

  package struct JoinReply: Sendable, Hashable {
    /// Server ids for the declared postgres bindings, by position.
    package var postgresChangeIDs: [Int]

    package init(postgresChangeIDs: [Int]) {
      self.postgresChangeIDs = postgresChangeIDs
    }
  }

  package enum Event: Sendable {
    case subscribeRequested, unsubscribeRequested
    case socketConnected
    case socketLost(RealtimeError)
    case joinReplied(Result<JoinReply, RealtimeError>)
    case joinTimedOut
    /// A `system` push with `status: "error"`; the server follows it with `phx_close`.
    case systemError(message: String)
    case serverClosed, serverErrored
    case leaveCompleted
    case rejoinTimerFired
    case tokenRefreshed
    case bindingsChanged
    case listenerAdded, lastListenerEnded, lingerTimerFired
  }

  package enum Effect: Sendable, Hashable {
    /// Send `phx_join` with the current bindings and token. When the socket is down the engine
    /// skips it; `socketConnected` sends it later.
    case sendJoin
    case sendLeave
    case scheduleRejoin(after: Duration), cancelRejoin
    case refreshToken
    case emitResubscribed
    case resolveSubscribe
    /// Fail the pending `subscribe()` with the state's error, or `.notSubscribed` when the
    /// channel was unsubscribed underneath it.
    case rejectSubscribe
    case resendPresenceTrack
    case finishDataStreams
    case scheduleLinger(after: Duration), cancelLinger
  }

  package struct Configuration: Sendable, Hashable {
    package var rejoin: BackoffPolicy
    package var rateLimitBackoff: Duration
    package var lingerAfterLastListener: Duration

    package init(
      rejoin: BackoffPolicy, rateLimitBackoff: Duration, lingerAfterLastListener: Duration
    ) {
      self.rejoin = rejoin
      self.rateLimitBackoff = rateLimitBackoff
      self.lingerAfterLastListener = lingerAfterLastListener
    }
  }

  // MARK: - Error classification

  package enum ErrorClass: Sendable, Hashable {
    /// The user must act; no timer.
    case fatal
    /// A fresh token can fix it; refresh once, then rejoin.
    case authRefresh
    /// Back off for the long interval.
    case rateLimit
    /// Rejoin on the regular steps.
    case retry
  }

  package static func classify(_ error: RealtimeError) -> ErrorClass {
    if let code = error.serverCode {
      if code == .invalidJWTToken, error.message.contains("expired") { return .authRefresh }
      if RealtimeError.ServerCode.fatal.contains(code) { return .fatal }
      if RealtimeError.ServerCode.rateLimit.contains(code) { return .rateLimit }
      return .retry
    }
    let message = error.message
    if message.contains("Token has expired") { return .authRefresh }
    if message.contains("Too many") && message.contains("per second")
      || message.contains("rate limit")
    {
      return .rateLimit
    }
    if message.contains("You no longer have permission") { return .fatal }
    return .retry
  }

  /// Maps the server's echoed bindings to ids by position, checking each one still describes
  /// the binding the client declared.
  static func verify(declared: [PostgresJoinConfig], replied: [PostgresJoinConfig])
    -> Result<[Int], RealtimeError>
  {
    guard declared.count == replied.count, zip(declared, replied).allSatisfy({ $0 == $1 })
    else {
      return .failure(
        RealtimeError(
          kind: .server,
          message: "mismatch between server and client bindings for postgres changes",
          isRetryable: false))
    }
    return .success(replied.map(\.id))
  }

  // MARK: - Transition

  package static func transition(
    _ state: inout State, _ event: Event, configuration: Configuration
  ) -> [Effect] {
    switch (state, event) {
    // Subscribe.
    case (.unsubscribed, .subscribeRequested), (.failed, .subscribeRequested):
      state = .subscribing(attempt: 1, isRejoin: false)
      return [.sendJoin]
    case (.subscribed, .subscribeRequested):
      return [.resolveSubscribe]
    case (.subscribing, .socketConnected):
      return [.sendJoin]
    case (.resubscribing(let attempt, _, _), .socketConnected):
      state = .subscribing(attempt: attempt + 1, isRejoin: true)
      return [.sendJoin]

    // Join replies.
    case (.subscribing(_, let isRejoin), .joinReplied(.success)):
      state = .subscribed
      return [.resolveSubscribe, .resendPresenceTrack] + (isRejoin ? [.emitResubscribed] : [])
    case (.subscribing(let attempt, _), .joinReplied(.failure(let error))):
      switch classify(error) {
      case .fatal:
        return fail(&state, with: error, rejectingSubscribe: true)
      case .authRefresh where attempt > 1:
        // ponytail: one refresh per subscribe attempt chain; a retry-class failure before the
        // expiry makes this fatal too. Track "refreshed once" separately if that bites.
        return fail(&state, with: error, rejectingSubscribe: true)
      case .authRefresh:
        state = .resubscribing(attempt: attempt, retryIn: .zero, lastError: error)
        return [.refreshToken]
      case .rateLimit:
        return scheduleRejoin(
          &state, attempt: attempt, after: configuration.rateLimitBackoff, error: error)
      case .retry:
        let delay = configuration.rejoin.delay(forAttempt: attempt)
        return scheduleRejoin(&state, attempt: attempt, after: delay, error: error)
      }
    case (.subscribing(let attempt, _), .joinTimedOut):
      let delay = configuration.rejoin.delay(forAttempt: attempt)
      let error = RealtimeError(kind: .timeout, message: "join timed out")
      return [.sendLeave] + scheduleRejoin(&state, attempt: attempt, after: delay, error: error)
    case (.resubscribing(let attempt, _, _), .rejoinTimerFired),
      (.resubscribing(let attempt, _, _), .tokenRefreshed):
      state = .subscribing(attempt: attempt + 1, isRejoin: true)
      return [.sendJoin]

    // Server-side ends while subscribed.
    case (.subscribed, .systemError(let message)):
      let error = RealtimeError.channelClosed(message: message)
      switch classify(error) {
      case .fatal:
        return fail(&state, with: error, rejectingSubscribe: false)
      case .authRefresh:
        state = .resubscribing(attempt: 1, retryIn: .zero, lastError: error)
        return [.refreshToken]
      case .rateLimit:
        return scheduleRejoin(
          &state, attempt: 1, after: configuration.rateLimitBackoff, error: error)
      case .retry:
        let delay = configuration.rejoin.delay(forAttempt: 1)
        return scheduleRejoin(&state, attempt: 1, after: delay, error: error)
      }
    case (.subscribed, .serverClosed), (.subscribed, .serverErrored):
      let error = RealtimeError.channelClosed(
        message: event.isServerErrored
          ? "channel crashed (phx_error)" : "channel closed (phx_close)")
      let delay = configuration.rejoin.delay(forAttempt: 1)
      return scheduleRejoin(&state, attempt: 1, after: delay, error: error)

    // Socket.
    case (.subscribed, .socketLost(let error)):
      state = .resubscribing(attempt: 1, retryIn: .zero, lastError: error)
      return []
    case (.subscribing(let attempt, _), .socketLost(let error)):
      state = .resubscribing(attempt: attempt, retryIn: .zero, lastError: error)
      return []
    case (.resubscribing(let attempt, let retryIn, _), .socketLost(let error)):
      state = .resubscribing(attempt: attempt, retryIn: .zero, lastError: error)
      return retryIn > .zero ? [.cancelRejoin] : []
    case (.unsubscribing, .socketLost):
      state = .unsubscribed
      return []

    // Bindings.
    case (.subscribed, .bindingsChanged):
      state = .subscribing(attempt: 1, isRejoin: true)
      return [.sendLeave, .sendJoin]
    case (.subscribing, .bindingsChanged):
      return [.sendLeave, .sendJoin]

    // Unsubscribe.
    case (.subscribed, .unsubscribeRequested):
      state = .unsubscribing
      return [.cancelLinger, .sendLeave]
    case (.subscribing, .unsubscribeRequested):
      state = .unsubscribed
      return [.sendLeave, .rejectSubscribe]
    case (.resubscribing(_, let retryIn, _), .unsubscribeRequested):
      state = .unsubscribed
      return (retryIn > .zero ? [.cancelRejoin] : []) + [.rejectSubscribe]
    case (.failed, .unsubscribeRequested):
      state = .unsubscribed
      return []
    case (.unsubscribing, .leaveCompleted), (.unsubscribing, .serverClosed):
      state = .unsubscribed
      return []

    // Linger.
    case (.subscribed, .lastListenerEnded):
      return [.scheduleLinger(after: configuration.lingerAfterLastListener)]
    case (.subscribed, .listenerAdded):
      return [.cancelLinger]
    case (.subscribed, .lingerTimerFired):
      state = .unsubscribing
      return [.sendLeave]

    default:
      return []
    }
  }

  private static func scheduleRejoin(
    _ state: inout State, attempt: Int, after delay: Duration, error: RealtimeError
  ) -> [Effect] {
    state = .resubscribing(attempt: attempt, retryIn: delay, lastError: error)
    return [.scheduleRejoin(after: delay)]
  }

  private static func fail(
    _ state: inout State, with error: RealtimeError, rejectingSubscribe: Bool
  ) -> [Effect] {
    state = .failed(error)
    return (rejectingSubscribe ? [.rejectSubscribe] : []) + [.finishDataStreams]
  }
}

extension ChannelMachine.Event {
  fileprivate var isServerErrored: Bool {
    if case .serverErrored = self { return true }
    return false
  }
}

extension RealtimeError {
  /// The error for a channel the server closed with a `system` error message.
  package static func channelClosed(message: String) -> RealtimeError {
    RealtimeError(kind: .channelClosed, message: message)
  }
}
