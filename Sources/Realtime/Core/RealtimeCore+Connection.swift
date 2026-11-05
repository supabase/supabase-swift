//
//  RealtimeCore+Connection.swift
//  Realtime
//

import Logging

extension RealtimeCore {
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
      effects.contains(.schedule(.idleDisconnect, after: delay))
    {
      idleDisconnectPending = true
    }
    guard connection != previous else { return effects }

    logger.debug("Connection → \(connection) on \(event)")
    switch connection {
    case .connecting:
      lastAttemptStart = now.elapsed
    case .reconnecting(_, let retryIn, _):
      reconnectDueAt = now.elapsed + retryIn
    case .connected, .disconnected:
      break
    }
    // A heartbeat pending on the old socket can never be acknowledged on the new one.
    pendingHeartbeat = nil

    var result: [Effect] = [.publishClientStatus(connection.status)]
    result += effects
    if case .connected = previous {
      result.append(.cancel(.heartbeat))
      if livenessProbeScheduled {
        livenessProbeScheduled = false
        result.append(.cancel(.livenessProbe))
      }
      heartbeatPausedByProbe = false
      result += cancelTokenRefresh()
    }
    if case .connected = connection {
      result.append(.schedule(.heartbeat, after: options.heartbeatInterval))
      // The refresh timer runs only while connected, so every connect starts it again.
      result += scheduleTokenRefresh()
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
      return .schedule(.reconnect, after: delay)
    }

    switch (state, event) {
    // connect()
    case (.disconnected, .connect):
      state = .connecting(attempt: 1)
      return [.openSocket]
    case (.reconnecting(let attempt, _, _), .connect),
      (.reconnecting(let attempt, _, _), .wake):
      state = .connecting(attempt: attempt + 1)
      return [.cancel(.reconnect), .openSocket]
    case (_, .connect), (_, .wake):
      return []

    case (.reconnecting(let attempt, _, _), .timerFired(.reconnect)):
      state = .connecting(attempt: attempt + 1)
      return [.openSocket]
    case (_, .timerFired(.reconnect)):
      return []

    // The transport answered.
    case (.connecting, .socketOpened(let conn)):
      state = .connected(conn)
      return [.installSocket(conn)]
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
      return [.schedule(.idleDisconnect, after: delay)]

    default:
      return []
    }
  }

  // MARK: App lifecycle

  mutating func enterBackground() -> [Effect] {
    wasConnectedBeforeBackground = connection.status.isConnected
    return []
  }

  /// The shortest time between the start of an attempt and the start of the next one that a
  /// wake hint causes.
  static let wakeCooldown: Duration = .seconds(2)

  /// Handles a hint that the network may be back. A hint that comes less than ``wakeCooldown``
  /// after the last attempt started moves the retry to the end of the cooldown instead of
  /// starting it, so a path that flaps cannot start an attempt per report. It never makes the
  /// wait longer than the backoff. The probe and the foreground retry at once and do not come
  /// through here.
  mutating func wakeHint() -> [Effect] {
    guard case .reconnecting = connection, let lastAttemptStart, let reconnectDueAt else {
      return transitionConnection(.wake)
    }
    let retryAt = lastAttemptStart + Self.wakeCooldown
    guard retryAt > now.elapsed else { return transitionConnection(.wake) }
    guard retryAt < reconnectDueAt else { return [] }
    self.reconnectDueAt = retryAt
    return [.schedule(.reconnect, after: retryAt - now.elapsed)]
  }

  /// How long the heartbeat sent on a return to the foreground waits for its reply.
  static let livenessProbeTimeout: Duration = .seconds(5)

  /// Checks a connected socket that the app may have left dead while suspended, and recovers a
  /// connection that went away while the app was in the background: skips the rest of a backoff
  /// wait, or connects again after a failure stopped the client.
  mutating func enterForeground() -> [Effect] {
    let wasConnected = wasConnectedBeforeBackground
    wasConnectedBeforeBackground = false
    if case .connected = connection { return startLivenessProbe() }
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
  /// A heartbeat also refreshes the token, as `setAuth()` does.
  mutating func heartbeatTimerFired() -> [Effect] {
    guard case .connected = connection else { return [] }

    if pendingHeartbeat != nil {
      logger.debug("Heartbeat timeout - previous heartbeat not acknowledged")
      return failSocketOnHeartbeatTimeout()
    }
    return sendHeartbeat()
  }

  private mutating func failSocketOnHeartbeatTimeout() -> [Effect] {
    [.publishHeartbeat(.timedOut)] + socketWentAway(.socketFailed(.heartbeatTimeout))
  }

  private mutating func sendHeartbeat() -> [Effect] {
    let ref = makeRef()
    pendingHeartbeat = (ref, now.elapsed)
    return [
      .send(
        RealtimeMessage(joinRef: nil, ref: ref, topic: "phoenix", event: "heartbeat", payload: [:])
      ),
      .publishHeartbeat(.sent),
      .schedule(.heartbeat, after: options.heartbeatInterval),
    ] + refreshAccessToken(ignoringInterval: false)
  }

  mutating func receiveHeartbeatReply(_ message: RealtimeMessage) -> [Effect] {
    guard let pending = pendingHeartbeat, message.ref == pending.ref else { return [] }

    pendingHeartbeat = nil
    // Any reply proves the socket is alive, which is all a heartbeat checks.
    if message.status != .ok {
      logger.warning("The server answered the heartbeat with: \(message.payload)")
    }
    var effects: [Effect] = [
      .publishHeartbeat(.acknowledged(latency: now.elapsed - pending.sentAt))
    ]
    if livenessProbeScheduled {
      livenessProbeScheduled = false
      effects.append(.cancel(.livenessProbe))
    }
    if heartbeatPausedByProbe {
      heartbeatPausedByProbe = false
      effects.append(.schedule(.heartbeat, after: options.heartbeatInterval))
    }
    return effects
  }

  // MARK: Liveness probe

  /// Sends a heartbeat now, outside the schedule, and gives it ``livenessProbeTimeout`` to be
  /// acknowledged. A heartbeat that already waits for its reply serves as the probe.
  ///
  /// The regular tick pauses while a pending heartbeat serves as the probe: it would fail the
  /// socket on that heartbeat, possibly before the probe's deadline. The reply restarts it.
  private mutating func startLivenessProbe() -> [Effect] {
    livenessProbeScheduled = true
    let probeDeadline = Effect.schedule(.livenessProbe, after: Self.livenessProbeTimeout)
    guard pendingHeartbeat == nil else {
      heartbeatPausedByProbe = true
      return [.cancel(.heartbeat), probeDeadline]
    }
    return sendHeartbeat() + [probeDeadline]
  }

  /// A probe with no reply is a heartbeat timeout, except that the reconnect does not wait out a
  /// backoff: the app is in the foreground now, and the user is waiting for data.
  mutating func livenessProbeTimerFired() -> [Effect] {
    // A scheduled probe means connected with an unacknowledged heartbeat: a reply, or any
    // change of `connection`, clears it.
    guard livenessProbeScheduled else { return [] }

    logger.debug("Liveness probe timeout - no reply after returning to the foreground")
    return failSocketOnHeartbeatTimeout() + transitionConnection(.wake)
  }
}
