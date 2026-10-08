//
//  ConnectionMachine.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

/// The socket lifecycle as a pure function of state and event.
///
/// No I/O, no clock, no socket: the engine feeds events in and performs the effects that come
/// out. The state is also the connection status, so the engine emits it whenever a transition
/// changes it; no effect carries one.
package enum ConnectionMachine {
  package enum State: Sendable {
    /// Idle, paused, or stopped by the user; carries the error when a fatal failure stopped it.
    case disconnected(RealtimeError?)
    case connecting(attempt: Int)
    case connected
    case reconnecting(attempt: Int, retryIn: Duration, lastError: RealtimeError)

    package var isConnected: Bool {
      if case .connected = self { return true }
      return false
    }

    package var error: RealtimeError? {
      switch self {
      case .disconnected(let error): error
      case .reconnecting(_, _, let error): error
      case .connecting, .connected: nil
      }
    }
  }

  package enum Event: Sendable {
    case connectRequested, disconnectRequested, pauseRequested, resumeRequested
    case upgradeSucceeded
    case upgradeFailed(RealtimeError)
    case transportClosed(code: WebSocketCloseCode?, reason: String?)
    case heartbeatTimedOut
    case retryTimerFired
    /// The network path became satisfied or the app came to the foreground.
    case wakeSignal
    case channelAdded, lastChannelRemoved, idleTimerFired
  }

  package enum Effect: Sendable, Hashable {
    case openTransport
    case closeTransport(code: WebSocketCloseCode)
    case startHeartbeat, stopHeartbeat
    case scheduleRetry(after: Duration), cancelRetry
    case scheduleIdleDisconnect(after: Duration), cancelIdleDisconnect
    case rejoinAllChannels
    case failPendingReplies
    /// Every channel keeps wanting its subscription and rejoins when the socket is back.
    case channelsSocketLost
    /// Every channel drops its subscription.
    case channelsUnsubscribed
  }

  package struct Configuration: Sendable, Hashable {
    package var reconnect: BackoffPolicy
    package var idleDisconnectAfter: Duration

    package init(reconnect: BackoffPolicy, idleDisconnectAfter: Duration) {
      self.reconnect = reconnect
      self.idleDisconnectAfter = idleDisconnectAfter
    }
  }

  package static func transition(
    _ state: inout State, _ event: Event, configuration: Configuration
  ) -> [Effect] {
    switch (state, event) {
    // Connect.
    case (.disconnected, .connectRequested), (.disconnected, .resumeRequested):
      state = .connecting(attempt: 1)
      return [.openTransport]
    case (.reconnecting(let attempt, _, _), .connectRequested),
      (.reconnecting(let attempt, _, _), .wakeSignal):
      state = .connecting(attempt: attempt + 1)
      return [.cancelRetry, .openTransport]
    case (.reconnecting(let attempt, _, _), .retryTimerFired):
      state = .connecting(attempt: attempt + 1)
      return [.openTransport]

    // Handshake.
    case (.connecting, .upgradeSucceeded):
      state = .connected
      return [.startHeartbeat, .rejoinAllChannels]
    case (.connecting, .upgradeFailed(let error)) where !error.isRetryable:
      state = .disconnected(error)
      return [.channelsSocketLost]
    case (.connecting(let attempt), .upgradeFailed(let error)):
      return scheduleRetry(&state, attempt: attempt, error: error, configuration: configuration)
    case (.connecting(let attempt), .transportClosed(let code, let reason)):
      let error = RealtimeError.socketClosed(code: code, reason: reason)
      return scheduleRetry(&state, attempt: attempt, error: error, configuration: configuration)

    // Loss while connected.
    case (.connected, .transportClosed(let code, let reason)):
      let error = RealtimeError.socketClosed(code: code, reason: reason)
      return [.stopHeartbeat, .failPendingReplies, .channelsSocketLost]
        + scheduleRetry(&state, attempt: 1, error: error, configuration: configuration)
    case (.connected, .heartbeatTimedOut):
      return [
        .stopHeartbeat, .closeTransport(code: .normalClosure), .failPendingReplies,
        .channelsSocketLost,
      ]
        + scheduleRetry(
          &state, attempt: 1, error: .heartbeatTimeout, configuration: configuration)

    // Stop.
    case (.connected, .disconnectRequested), (.connected, .idleTimerFired):
      state = .disconnected(nil)
      return [
        .stopHeartbeat, .cancelIdleDisconnect, .channelsUnsubscribed,
        .closeTransport(code: .normalClosure), .failPendingReplies,
      ]
    case (.connected, .pauseRequested):
      state = .disconnected(nil)
      return [
        .stopHeartbeat, .cancelIdleDisconnect, .channelsSocketLost,
        .closeTransport(code: .normalClosure), .failPendingReplies,
      ]
    case (.connecting, .disconnectRequested):
      state = .disconnected(nil)
      return [.closeTransport(code: .normalClosure), .channelsUnsubscribed]
    case (.connecting, .pauseRequested):
      state = .disconnected(nil)
      return [.closeTransport(code: .normalClosure)]
    case (.reconnecting, .disconnectRequested):
      state = .disconnected(nil)
      return [.cancelRetry, .channelsUnsubscribed]
    case (.reconnecting, .pauseRequested):
      state = .disconnected(nil)
      return [.cancelRetry]
    case (.disconnected, .disconnectRequested):
      state = .disconnected(nil)
      return []

    // Idle.
    case (.connected, .lastChannelRemoved):
      return [.scheduleIdleDisconnect(after: configuration.idleDisconnectAfter)]
    case (.connected, .channelAdded):
      return [.cancelIdleDisconnect]

    default:
      return []
    }
  }

  private static func scheduleRetry(
    _ state: inout State, attempt: Int, error: RealtimeError, configuration: Configuration
  ) -> [Effect] {
    let delay = configuration.reconnect.delay(forAttempt: attempt)
    state = .reconnecting(attempt: attempt, retryIn: delay, lastError: error)
    return [.scheduleRetry(after: delay)]
  }
}
