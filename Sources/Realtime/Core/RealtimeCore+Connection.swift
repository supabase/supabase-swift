//
//  RealtimeCore+Connection.swift
//  Realtime
//

import Logging

extension RealtimeCore {
  /// The heartbeat sent on the current socket that the server has not acknowledged yet.
  struct HeartbeatState {
    var pendingRef: Ref?
    /// When the pending heartbeat was sent, as `CoreTime.elapsed`.
    var sentAt: Duration?
  }

  mutating func connect(waiter: WaiterID?) -> [Effect] {
    if case .connected = connection {
      return waiter.map { [.resume($0, .success)] } ?? []
    }
    if let waiter {
      connectWaiters.append(waiter)
    }
    return transitionConnection(.connect(waiter: waiter))
  }

  /// Runs `event` through ``connectionTable(_:_:retryDelay:)`` and adds what follows from the
  /// change of `connection`: the published status, the heartbeat timer, and the connect waiters.
  mutating func transitionConnection(_ event: Event) -> [Effect] {
    if case .disconnectRequested = event {
      lastRef = 0
      // A disconnect the developer asked for is not undone when the app comes back.
      wasConnectedBeforeBackground = false
      // `cancelAllTasks` cancels the idle disconnect too.
      idleDisconnectPending = false
    }

    let previous = connection
    let effects = Self.connectionTable(&connection, event, retryDelay: options.retryDelay)
    if case .lastChannelRemoved(let delay) = event,
      effects.contains(.scheduleIdleDisconnect(after: delay))
    {
      idleDisconnectPending = true
    }
    guard connection != previous else { return effects }

    logger.debug("Connection → \(connection) on \(event)")
    // A heartbeat pending on the old socket can never be acknowledged on the new one.
    heartbeat = HeartbeatState()

    var result: [Effect] = [.publishClientStatus(connection.status)]
    result += effects
    if case .connected = previous {
      result.append(.cancel(.heartbeat))
    }
    if case .connected = connection {
      result.append(.schedule(.heartbeat, after: options.heartbeatInterval))
    }
    if case .connecting = previous {
      result += resolveConnectWaiters()
    }
    return result
  }

  /// Ends the wait of every `connect()` caller once the attempt they wait for is over.
  private mutating func resolveConnectWaiters() -> [Effect] {
    let outcome: WaiterOutcome
    switch connection {
    case .connecting:
      return []
    case .connected:
      outcome = .success
    case .reconnecting(_, _, let error):
      outcome = .failure(error)
    case .disconnected(let error):
      // No error: `disconnect()` interrupted the attempt.
      outcome = error.map(WaiterOutcome.failure) ?? .cancelled
    }
    let waiters = connectWaiters
    connectWaiters = []
    return waiters.map { .resume($0, outcome) }
  }

  /// The connection transition table. It updates `state` for a connection event and says which
  /// effects follow. `retryDelay(n)` is the wait after the n-th attempt failed. Every other event
  /// leaves `state` as it is.
  static func connectionTable(
    _ state: inout RealtimeClient.ConnectionState, _ event: Event,
    retryDelay: (_ attempt: Int) -> Duration
  ) -> [Effect] {
    func waitToRetry(after attempt: Int, _ error: RealtimeError) -> Effect {
      let delay = retryDelay(attempt)
      state = .reconnecting(attempt: attempt, retryIn: delay, lastError: error)
      return .scheduleRetry(after: delay)
    }

    switch (state, event) {
    // connect()
    case (.disconnected, .connect):
      state = .connecting(attempt: 1)
      return [.openSocket]
    case (.reconnecting(let attempt, _, _), .connect),
      (.reconnecting(let attempt, _, _), .wake):
      state = .connecting(attempt: attempt + 1)
      return [.cancelRetry, .openSocket]
    case (_, .connect), (_, .wake):
      return []

    case (.reconnecting(let attempt, _, _), .retryTimerFired):
      state = .connecting(attempt: attempt + 1)
      return [.openSocket]
    case (_, .retryTimerFired):
      return []

    // The transport answered.
    case (.connecting(let attempt), .socketOpened(let conn)):
      state = .connected(conn)
      return [.installSocket(conn, rejoinChannels: attempt > 1)]
    case (_, .socketOpened(let conn)):
      // `disconnect()` ran while the handshake was in flight and already moved on.
      return [.closeSocket(conn, code: nil, reason: "Connection cancelled")]
    case (.connecting(let attempt), .socketOpenFailed(let error)):
      // The user's own `connect()` reports the failure and stops; so does a retry that can
      // never succeed. Any other failed retry waits longer and tries again.
      guard attempt > 1, error.isRetryable else {
        state = .disconnected(error)
        return []
      }
      return [waitToRetry(after: attempt, error)]
    case (_, .socketOpenFailed):
      return []

    // disconnect()
    case (.connected(let conn), .disconnectRequested(let code, let reason)):
      state = .disconnected(nil)
      return [
        .cancelAllTasks, .closeSocket(conn, code: code, reason: reason ?? "Client disconnect"),
      ]
    case (_, .disconnectRequested):
      state = .disconnected(nil)
      return [.cancelAllTasks]

    // The socket went away.
    case (.connected, .socketClosed(let code, let reason)):
      let error = RealtimeError.socketClosed(
        code: code.map(WebSocketCloseCode.init(rawValue:)), reason: reason)
      // Application-level close codes (4000–4999) typically signal auth or protocol errors.
      // Reconnecting with the same bad token would loop; the caller must re-authenticate.
      if let code, code >= 4000 {
        state = .disconnected(error)
        return [.stopSocketLoops]
      }
      return [.stopSocketLoops, waitToRetry(after: 1, error)]
    case (.connected(let conn), .socketFailed(let error)):
      return [
        // 1001 rather than a normal closure: the client gives up on a connection that failed.
        .closeSocket(conn, code: 1001, reason: "error: \(error.message)"),
        .stopSocketLoops,
        waitToRetry(after: 1, error),
      ]
    case (_, .socketClosed), (_, .socketFailed):
      // Not connected: the socket this came from is already gone.
      return []

    // Channels come and go.
    case (.disconnected, .lastChannelRemoved):
      return []
    case (_, .lastChannelRemoved(let delay)):
      return [.scheduleIdleDisconnect(after: delay)]

    default:
      return []
    }
  }

  // MARK: App lifecycle

  mutating func enterBackground() -> [Effect] {
    wasConnectedBeforeBackground = connection.status.isConnected
    return []
  }

  /// Recovers a connection that went away while the app was in the background: skips the rest
  /// of a backoff wait, or connects again after a failure stopped the client.
  mutating func enterForeground() -> [Effect] {
    let wasConnected = wasConnectedBeforeBackground
    wasConnectedBeforeBackground = false
    guard wasConnected else { return [] }

    switch connection {
    case .connected, .connecting:
      return []
    case .reconnecting:
      return transitionConnection(.wake)
    case .disconnected:
      return transitionConnection(.connect(waiter: nil))
    }
  }

  // MARK: Heartbeat

  /// Sends the next heartbeat, or fails the socket when the previous one was never acknowledged.
  mutating func heartbeatTimerFired(at time: CoreTime) -> [Effect] {
    guard case .connected = connection else { return [] }

    if heartbeat.pendingRef != nil {
      logger.debug("Heartbeat timeout - previous heartbeat not acknowledged")
      return [.publishHeartbeat(.timedOut)] + socketWentAway(.socketFailed(.heartbeatTimeout))
    }

    let ref = makeRef()
    heartbeat = HeartbeatState(pendingRef: ref, sentAt: time.elapsed)
    return [
      .send(
        RealtimeMessage(joinRef: nil, ref: ref, topic: "phoenix", event: "heartbeat", payload: [:])
      ),
      .publishHeartbeat(.sent),
      .schedule(.heartbeat, after: options.heartbeatInterval),
    ]
  }

  mutating func receiveHeartbeatReply(_ message: RealtimeMessage, at time: CoreTime) -> [Effect] {
    guard let ref = message.ref, ref == heartbeat.pendingRef else { return [] }

    let sentAt = heartbeat.sentAt
    heartbeat = HeartbeatState()
    // Any reply proves the socket is alive, which is all a heartbeat checks.
    if message.status != .ok {
      logger.warning("The server answered the heartbeat with: \(message.payload)")
    }
    return [.publishHeartbeat(.acknowledged(latency: sentAt.map { time.elapsed - $0 } ?? .zero))]
  }
}
