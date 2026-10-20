//
//  RealtimeClient+Connection.swift
//  Realtime
//
//  Created by Guilherme Souza on 19/10/26.
//

import Foundation
import Helpers
import IssueReporting
import Logging

// MARK: - The state machine

extension RealtimeClient {
  /// Everything that can move the connection. Events come from the public API, from the
  /// connecting and reconnecting tasks, and from the socket reader.
  enum Event {
    /// `connect()` was called.
    case connectRequested
    /// The transport handed back an open socket.
    case socketOpened(any WebSocket)
    /// The transport failed while `connect()` was waiting on it.
    case socketOpenFailed
    /// `disconnect(code:reason:)` was called.
    case disconnectRequested(code: Int?, reason: String?)
    /// The remote closed the current socket.
    case socketClosed(code: Int?, reason: String?)
    /// The current socket failed (for now, a heartbeat that was never acknowledged).
    case socketFailed(reason: String)
  }

  /// What the transition asks the actor to do once the state is updated. Effects run in order,
  /// after `connection` has its new value, so nothing observes a half-applied transition.
  enum Effect: Equatable {
    /// Start the `connect()` attempt.
    case openSocket
    /// Start the reader and heartbeat loops and flush buffered frames. After an automatic
    /// reconnect, also rejoin the channels.
    case installSocket(any WebSocket, rejoinChannels: Bool)
    /// Close a socket, either the current one or one that opened too late.
    case closeSocket(any WebSocket, code: Int?, reason: String)
    /// Stop the reader and heartbeat loops of the socket that just went away.
    case stopSocketLoops
    /// Cancel every task the client owns, including a `connect()` attempt in flight.
    case cancelAllTasks
    /// Start the reconnect loop.
    case startReconnect(reason: String)

    static func == (lhs: Effect, rhs: Effect) -> Bool {
      switch (lhs, rhs) {
      case (.openSocket, .openSocket), (.stopSocketLoops, .stopSocketLoops),
        (.cancelAllTasks, .cancelAllTasks):
        return true
      case (.installSocket(let a, let ra), .installSocket(let b, let rb)):
        return a === b && ra == rb
      case (.closeSocket(let a, let ca, let ra), .closeSocket(let b, let cb, let rb)):
        return a === b && ca == cb && ra == rb
      case (.startReconnect(let a), .startReconnect(let b)):
        return a == b
      default:
        return false
      }
    }
  }

  /// The pure transition table. It never touches the actor: given the current state and an
  /// event, it updates the state and says which effects follow.
  static func transition(_ state: inout ConnectionState, _ event: Event) -> [Effect] {
    switch (state, event) {
    // connect()
    case (.disconnected, .connectRequested):
      state = .connecting
      return [.openSocket]
    case (_, .connectRequested):
      return []

    // The transport answered.
    case (.connecting, .socketOpened(let conn)):
      state = .connected(conn)
      return [.installSocket(conn, rejoinChannels: false)]
    case (.reconnecting, .socketOpened(let conn)):
      state = .connected(conn)
      return [.installSocket(conn, rejoinChannels: true)]
    case (_, .socketOpened(let conn)):
      // `disconnect()` ran while the handshake was in flight and already moved on.
      return [.closeSocket(conn, code: nil, reason: "Connection cancelled")]
    case (.connecting, .socketOpenFailed):
      state = .disconnected
      return []
    case (_, .socketOpenFailed):
      // The reconnect loop retries by itself; `.disconnected` is not for a failed attempt.
      return []

    // disconnect()
    case (.connected(let conn), .disconnectRequested(let code, let reason)):
      state = .disconnected
      return [
        .cancelAllTasks, .closeSocket(conn, code: code, reason: reason ?? "Client disconnect"),
      ]
    case (_, .disconnectRequested):
      state = .disconnected
      return [.cancelAllTasks]

    // The socket went away.
    case (.connected, .socketClosed(let code, let reason)):
      // Application-level close codes (4000–4999) typically signal auth or protocol errors.
      // Reconnecting with the same bad token would loop; the caller must re-authenticate.
      if let code, code >= 4000 {
        state = .disconnected
        return [.stopSocketLoops]
      }
      state = .reconnecting
      let closeReason = "code: \(code?.description ?? "none"), reason: \(reason ?? "none")"
      return [.stopSocketLoops, .startReconnect(reason: closeReason)]
    case (.connected(let conn), .socketFailed(let reason)):
      state = .reconnecting
      return [
        .closeSocket(conn, code: nil, reason: "error: \(reason)"),
        .stopSocketLoops,
        .startReconnect(reason: "error: \(reason)"),
      ]
    case (_, .socketClosed), (_, .socketFailed):
      // Not connected: the socket this came from is already gone.
      return []
    }
  }

  /// Applies `event` in two phases: the pure transition first, then its effects. An event
  /// raised while effects are running is queued and applied right after them, so the table
  /// always sees one event at a time.
  func apply(_ event: Event) {
    pendingEvents.append(event)
    guard !isApplying else {
      reportIssue(
        "RealtimeClient.apply(_:) re-entered while applying an event; the new event was queued. Effects must not apply events synchronously."
      )
      return
    }
    isApplying = true
    defer { isApplying = false }

    while !pendingEvents.isEmpty {
      let next = pendingEvents.removeFirst()
      let effects = Self.transition(&connection, next)
      options.logger.debug("Connection → \(connection.status.rawValue) on \(next)")
      setStatus(connection.status)
      for effect in effects {
        run(effect)
      }
    }
  }

  private func run(_ effect: Effect) {
    switch effect {
    case .openSocket:
      connectAttempt = Task { try await openSocket() }

    case .installSocket(let conn, let rejoinChannels):
      generation += 1
      // A heartbeat awaiting an ack on the previous connection can never be acknowledged on
      // this one. Clearing the pending ref prevents the new connection's first heartbeat from
      // misreading it as a timeout and tearing down a healthy socket.
      pendingHeartbeatRef = nil
      listenForMessages(on: conn)
      startHeartbeating()
      flushSendBuffer()
      if rejoinChannels {
        Task.immediateIfAvailable { await self.rejoinChannels() }
      }

    case .closeSocket(let conn, let code, let reason):
      conn.close(code: code, reason: reason)

    case .stopSocketLoops:
      tasks.cancel(at: .socketReader)
      tasks.cancel(at: .heartbeat)
      pendingHeartbeatRef = nil

    case .cancelAllTasks:
      tasks.cancelAll()
      connectAttempt?.cancel()
      connectAttempt = nil
      pendingHeartbeatRef = nil
      generation += 1

    case .startReconnect(let reason):
      startReconnect(reason: reason)
    }
  }
}

// MARK: - Public API

extension RealtimeClient {
  /// Opens the WebSocket connection and suspends until it is established.
  ///
  /// Calling this method when already connected is a no-op; calling it while a connection or
  /// an automatic reconnect is in progress waits for that attempt. If
  /// ``RealtimeClientOptions/defaultConnectOnSubscribe`` is `true` (the default), this is called
  /// automatically when a channel is subscribed to.
  ///
  /// ```swift
  /// try await client.connect()
  /// ```
  ///
  /// - Throws: ``RealtimeError`` with kind `.transport` when the socket could not be opened, or
  ///   `CancellationError` when the calling task is cancelled or ``disconnect(code:reason:)``
  ///   interrupts the attempt.
  public func connect() async throws {
    options.logger.debug("Connecting...")

    switch connection {
    case .connected:
      options.logger.debug("Already connected")

    case .connecting:
      options.logger.debug("Connection already in progress, waiting...")
      try await awaitConnectAttempt()

    case .reconnecting:
      options.logger.debug("Reconnection in progress, waiting...")
      for task in tasks.tasks(at: .connection) {
        await task.value
      }
      guard case .connected = connection else {
        throw RealtimeError.transport("Connection failed")
      }

    case .disconnected:
      options.logger.debug("Initiating new connection")
      apply(.connectRequested)
      try await awaitConnectAttempt()
    }
  }

  /// Closes the WebSocket connection.
  ///
  /// Cancels pending tasks, clears the send buffer, fails every push still waiting for a reply
  /// with ``RealtimeError/Kind/notConnected``, and emits ``RealtimeClientStatus/disconnected``.
  /// Channels stay registered; subscribe to them again after the next ``connect()``.
  ///
  /// - Parameters:
  ///   - code: An optional numeric close code to send to the server.
  ///   - reason: An optional reason string to send to the server.
  public func disconnect(code: Int? = nil, reason: String? = nil) async {
    options.logger.debug("Closing WebSocket connection")
    ref = 0
    sendBuffer = []
    // A developer-initiated disconnect should not be undone on the next foreground event.
    wasConnectedBeforeBackground = false

    apply(.disconnectRequested(code: code, reason: reason))

    for channel in channels.values {
      await channel.socketDidDisconnect()
    }
  }

  // MARK: - App lifecycle

  /// Records that the app is entering the background. Captures whether the socket was connected
  /// at that moment so ``handleAppForeground()`` knows whether to attempt recovery when the app
  /// returns to the foreground.
  ///
  /// Invoked automatically by ``RealtimeLifecycleManager`` when
  /// ``RealtimeClientOptions/handleAppLifecycle`` is `true`.
  func handleAppBackground() {
    wasConnectedBeforeBackground = status == .connected
  }

  /// Recover the connection on app foregrounding: reconnect and re-join existing channels if the
  /// socket was connected before the app backgrounded and has since been torn down. No-op if the
  /// socket was already disconnected at background time, or if it is still connected now.
  ///
  /// Invoked automatically by ``RealtimeLifecycleManager`` when
  /// ``RealtimeClientOptions/handleAppLifecycle`` is `true`.
  func handleAppForeground() async {
    // Read-modify-write in one synchronous stretch, so two rapid foreground notifications
    // can't both observe `true`.
    let wasConnected = wasConnectedBeforeBackground
    wasConnectedBeforeBackground = false

    guard wasConnected else { return }
    // Skip if already connected OR if an auto-reconnect is in flight (.connecting): the
    // reconnect drives `rejoinChannels()` itself when it completes.
    guard status == .disconnected else { return }

    let hadChannels = !channels.isEmpty
    try? await connect()

    if hadChannels, status == .connected {
      await rejoinChannels()
    }
  }
}

// MARK: - Effects

extension RealtimeClient {
  /// Waits for the `connect()` attempt started by `.openSocket`.
  private func awaitConnectAttempt() async throws {
    guard let connectAttempt else {
      throw RealtimeError.transport("Connection failed")
    }
    do {
      try await connectAttempt.value
    } catch {
      throw Self.connectionError(error)
    }
  }

  /// Runs the transport for `connect()` and reports the outcome to the machine. Every caller
  /// that awaits this task observes `.connected` once it returns.
  ///
  /// `.cancelAllTasks` cancels this task but cannot stop the transport call already in flight.
  /// The table has no attempt identity, so a cancelled attempt drops its outcome here instead
  /// of handing it to whichever attempt is current by then.
  private func openSocket() async throws {
    let conn: any WebSocket
    do {
      conn = try await wsTransport(webSocketURL, options.headers.dictionary)
    } catch {
      options.logger.error("Connection failed: \(error)")
      if !Task.isCancelled {
        apply(.socketOpenFailed)
      }
      throw error
    }

    if Task.isCancelled {
      conn.close(code: nil, reason: "Connection cancelled")
      throw CancellationError()
    }
    apply(.socketOpened(conn))
    guard case .connected = connection else {
      throw CancellationError()
    }
    options.logger.debug("Connected to realtime WebSocket")
  }

  func rejoinChannels() async {
    await withTaskGroup(of: Void.self) { group in
      for channel in channels.values {
        group.addTask {
          await channel.resetForReconnect()
          try? await channel.subscribe()
        }
      }
    }
  }

  /// Reads the socket until it closes or fails.
  ///
  /// Detached, and `self` is resolved per event: a loop task isolated to this actor would retain
  /// it for as long as the socket stays open, so a client released while connected could never
  /// reach `deinit` and would leak itself, the socket and its `URLSession`.
  private func listenForMessages(on conn: any WebSocket) {
    let stream = conn.events
    let generation = generation
    let reader = Task.detached { [weak self] in
      for await event in stream {
        if Task.isCancelled { return }
        guard let self else { return }
        await self.handleSocketEvent(event, generation: generation)
      }
    }
    tasks.replace([reader], at: .socketReader)
  }

  private func startHeartbeating() {
    let generation = generation
    let heartbeat = Task.detached { [weak self, clock, interval = options.heartbeatInterval] in
      while !Task.isCancelled {
        try? await clock.sleep(for: interval)
        guard !Task.isCancelled, let self else { return }
        await self.sendHeartbeat(generation: generation)
      }
    }
    tasks.replace([heartbeat], at: .heartbeat)
  }

  private func sendHeartbeat(generation: Int) async {
    guard generation == self.generation, case .connected = connection else {
      // Don't leak `.disconnected` to `heartbeats` consumers — it's not a heartbeat outcome,
      // just this cycle bailing out early.
      return
    }

    if pendingHeartbeatRef != nil {
      // Previous heartbeat was never acknowledged.
      options.logger.debug("Heartbeat timeout - previous heartbeat not acknowledged")
      recordHeartbeat(.timeout)
      pendingHeartbeatRef = nil
      apply(.socketFailed(reason: RealtimeError.heartbeatTimeout.message))
      return
    }

    let heartbeatRef = makeRef()
    pendingHeartbeatRef = heartbeatRef
    push(
      RealtimeMessageV2(
        joinRef: nil,
        ref: heartbeatRef,
        topic: "phoenix",
        event: "heartbeat",
        payload: [:]
      )
    )
    recordHeartbeat(.sent)
    await setAuth()
  }

  // MARK: Socket events

  /// Applies one frame from the socket installed at `generation`. Frames from an older socket
  /// are dropped: a reconnect already replaced it, and its close must not tear down the
  /// healthy connection.
  func handleSocketEvent(_ event: LegacyWebSocketEvent, generation: Int) async {
    guard generation == self.generation else {
      options.logger.debug("Ignoring event from a stale connection: \(event)")
      return
    }

    switch event {
    case .binary(let data):
      do {
        let broadcast = try serializer.decodeBinary(data)
        options.logger.debug(
          "Received binary broadcast for topic \(broadcast.topic), event \(broadcast.event)"
        )
        await channels[broadcast.topic]?.handleBinaryBroadcast(broadcast)
      } catch {
        options.logger.error("Failed to decode binary frame: \(error)")
      }

    case .text(let text):
      do {
        await onMessage(try serializer.decodeText(text))
      } catch {
        options.logger.error("Failed to decode text frame: \(error)")
      }

    case .close(let code, let reason):
      options.logger.debug(
        "WebSocket closed. Code: \(code?.description ?? "<none>"), Reason: \(reason)"
      )
      apply(.socketClosed(code: code, reason: reason))
    }
  }

  private func onMessage(_ message: RealtimeMessageV2) async {
    if message.topic == "phoenix", message.event == "phx_reply" {
      recordHeartbeat(message.status == .ok ? .ok : .error)
    }

    if let ref = message.ref, ref == pendingHeartbeatRef {
      pendingHeartbeatRef = nil
      options.logger.debug("heartbeat received")
    } else {
      options.logger.debug("Received event \(message.event) for channel \(message.topic)")
    }

    await channels[message.topic]?.onMessage(message)
  }

  // MARK: Reconnect

  /// Keeps retrying with exponential backoff until a connection is established or the task is
  /// cancelled (`disconnect()` / `deinit`).
  ///
  /// State stays `.reconnecting` for every attempt — a failed attempt here does not flip state
  /// to `.disconnected`, so a `connect()` caller waiting on the task sees one outcome.
  private func startReconnect(reason: String) {
    options.logger.debug("Connection lost, initiating reconnect: \(reason)")
    // Captured by value so the sleep below doesn't need `self` at all — held only while
    // actually attempting a connection, not for the whole backoff wait. Otherwise a released
    // client would be kept alive for up to the current attempt's delay.
    let clock = self.clock
    let backoff = Self.reconnectBackoff(baseDelay: options.reconnectDelay)
    let logger = options.logger

    let reconnectTask = Task.detached { [weak self] in
      var attempt = 0
      while !Task.isCancelled {
        attempt += 1
        try? await clock.sleep(for: backoff.backoffDelay(retry: attempt))
        guard !Task.isCancelled, let self else { return }
        logger.debug("Attempting to reconnect (attempt \(attempt))...")

        do {
          try await self.performReconnectAttempt()
          return
        } catch is CancellationError {
          return
        } catch {
          logger.debug(
            "Reconnect attempt \(attempt) failed: \(error.localizedDescription). Retrying with backoff."
          )
        }
      }
    }

    tasks.replace([reconnectTask], at: .connection)
  }

  /// A single reconnect attempt. Only succeeds into `.connected`; a failure is left for the
  /// loop in `startReconnect` to retry.
  private func performReconnectAttempt() async throws {
    guard case .reconnecting = connection else { throw CancellationError() }
    let conn = try await wsTransport(webSocketURL, options.headers.dictionary)
    try Task.checkCancellation()
    apply(.socketOpened(conn))
    // `disconnect()` ran during the handshake; the machine closed the late socket.
    guard case .connected = connection else { throw CancellationError() }
  }

  /// Equal-jitter exponential backoff capped at 30s (phoenix.js's `reconnectAfterMs`
  /// ladder is the same shape: a growing delay that levels off rather than giving
  /// up). Jitter spreads the clients that lost the same connection instead of
  /// letting them all reconnect at the same instant. Only the delay math of
  /// `RetryPolicy` is used here: attempts are unbounded, and there is no HTTP
  /// status or method to consult.
  ///
  /// The n-th wait is in `cap/2...cap` with `cap = min(30s, baseDelay · 2^(n-1))`,
  /// so a test that advances a manual clock by `cap` always fires the sleep, and
  /// one that advances by less than `cap/2` never does.
  ///
  /// `baseDelay` is user-supplied and checked nowhere else, so it is clamped to `0...30s` here.
  static func reconnectBackoff(baseDelay: Duration) -> RetryPolicy {
    let maxDelay: Duration = .seconds(30)
    return RetryPolicy(baseDelay: min(max(baseDelay, .zero), maxDelay), maxDelay: maxDelay)
  }

  /// `CancellationError` and `RealtimeError` pass through; anything else the transport threw
  /// becomes a `.transport` error.
  static func connectionError(_ error: any Error) -> any Error {
    switch error {
    case is CancellationError, is RealtimeError:
      return error
    default:
      return RealtimeError.transport(error.localizedDescription, underlyingError: error)
    }
  }
}
