//
//  RealtimeClient+Connection.swift
//  Realtime
//
//  Created by Guilherme Souza on 19/10/26.
//

import Foundation
import Helpers
import Logging

extension RealtimeClient {
  // MARK: - Connect and disconnect

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

    case .connecting(let task):
      options.logger.debug("Connection already in progress, waiting...")
      try await awaitConnection(task)

    case .reconnecting(let task):
      options.logger.debug("Reconnection in progress, waiting...")
      await task.value
      guard case .connected = connection else {
        throw RealtimeError.transport("Connection failed")
      }

    case .disconnected:
      options.logger.debug("Initiating new connection")
      // The task does the whole job, including `handleConnected`, so every caller that awaits
      // it (this one and any concurrent `connect()`) observes `.connected` once it returns.
      let task = Task<Void, any Error> { try await openConnection() }
      setConnectionState(.connecting(task))
      try await awaitConnection(task)
    }
  }

  private func awaitConnection(_ task: Task<Void, any Error>) async throws {
    do {
      try await task.value
    } catch {
      throw Self.connectionError(error)
    }
  }

  /// Runs the transport and installs the socket. Only runs inside the `.connecting` task.
  private func openConnection() async throws {
    let conn: any WebSocket
    do {
      conn = try await wsTransport(webSocketURL, options.headers.dictionary)
    } catch {
      if case .connecting = connection {
        setConnectionState(.disconnected)
      }
      options.logger.error("Connection failed: \(error)")
      throw error
    }

    // `disconnect()` ran while the handshake was in flight and already moved on.
    guard case .connecting = connection else {
      conn.close(code: nil, reason: "Connection cancelled")
      throw CancellationError()
    }

    options.logger.debug("Connected to realtime WebSocket")
    handleConnected(conn, isReconnect: false)
  }

  /// Closes the WebSocket connection.
  ///
  /// Cancels pending tasks, clears the send buffer, fails every push still waiting for a reply
  /// with ``RealtimeError/Kind/notConnected``, and emits ``RealtimeClientStatus/disconnected``.
  /// Channels stay registered; subscribe to them again after the next ``connect()``.
  ///
  /// - Parameters:
  ///   - code: An optional numeric close code to send to the server.
  ///   - reason: An optional human-readable reason string.
  public func disconnect(code: Int? = nil, reason: String? = nil) async {
    options.logger.debug("Closing WebSocket connection")

    ref = 0
    stopConnectionTasks()
    pendingDisconnectTask?.cancel()
    pendingDisconnectTask = nil
    sendBuffer = []
    // A developer-initiated disconnect should not be undone on the next foreground event.
    wasConnectedBeforeBackground = false

    switch connection {
    case .connected(let conn):
      conn.close(code: code, reason: reason ?? "Client disconnect")
    case .connecting(let task):
      options.logger.debug("Cancelling connection attempt")
      task.cancel()
    case .reconnecting(let task):
      options.logger.debug("Cancelling reconnection attempt")
      task.cancel()
    case .disconnected:
      break
    }
    setConnectionState(.disconnected)

    for channel in channels.values {
      await channel.socketDidDisconnect()
    }
  }

  // MARK: - Connection lifecycle

  func setConnectionState(_ state: ConnectionState) {
    connection = state
    switch state {
    case .disconnected: setStatus(.disconnected)
    case .connecting, .reconnecting: setStatus(.connecting)
    case .connected: setStatus(.connected)
    }
  }

  /// Wires up a freshly opened socket: the receive loop, the heartbeat, the buffered frames and,
  /// after an automatic reconnect, the channel rejoin.
  func handleConnected(_ conn: any WebSocket, isReconnect: Bool) {
    stopConnectionTasks()
    setConnectionState(.connected(conn))
    // A heartbeat awaiting an ack on the previous connection can never be acknowledged on this
    // one. Clearing the pending ref prevents the new connection's first heartbeat from
    // misreading it as a timeout and tearing down a healthy socket.
    pendingHeartbeatRef = nil

    listenForMessages(on: conn)
    startHeartbeating()
    flushSendBuffer()

    if isReconnect {
      Task.immediateIfAvailable { await rejoinChannels() }
    }
  }

  private func stopConnectionTasks() {
    messageTask?.cancel()
    messageTask = nil
    heartbeatTask?.cancel()
    heartbeatTask = nil
    pendingHeartbeatRef = nil
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
    messageTask = Task.detached { [weak self] in
      for await event in stream {
        if Task.isCancelled { return }
        guard let self else { return }
        await self.handleSocketEvent(event, from: conn)
      }
    }
  }

  private func startHeartbeating() {
    heartbeatTask = Task.detached { [weak self, clock, interval = options.heartbeatInterval] in
      while !Task.isCancelled {
        try? await clock.sleep(for: interval)
        guard !Task.isCancelled, let self else { return }
        await self.sendHeartbeat()
      }
    }
  }

  private func sendHeartbeat() async {
    guard case .connected(let conn) = connection else {
      // Don't leak `.disconnected` to `heartbeats` consumers — it's not a heartbeat outcome,
      // just this cycle bailing out early.
      return
    }

    if pendingHeartbeatRef != nil {
      // Previous heartbeat was never acknowledged.
      options.logger.debug("Heartbeat timeout - previous heartbeat not acknowledged")
      heartbeatMirror.update(.timeout)
      pendingHeartbeatRef = nil
      handleSocketError(RealtimeError.heartbeatTimeout, from: conn)
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
    heartbeatMirror.update(.sent)
    await setAuth()
  }

  // MARK: - Socket events

  private func handleSocketEvent(_ event: LegacyWebSocketEvent, from conn: any WebSocket) async {
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
      handleClose(code: code, reason: reason, from: conn)
    }
  }

  private func onMessage(_ message: RealtimeMessageV2) async {
    if message.topic == "phoenix", message.event == "phx_reply" {
      heartbeatMirror.update(message.status == .ok ? .ok : .error)
    }

    if let ref = message.ref, ref == pendingHeartbeatRef {
      pendingHeartbeatRef = nil
      options.logger.debug("heartbeat received")
    } else {
      options.logger.debug("Received event \(message.event) for channel \(message.topic)")
    }

    await channels[message.topic]?.onMessage(message)
  }

  /// Handles a socket failure by closing it and starting the reconnect ladder.
  ///
  /// `conn` scopes the error to the socket it came from: a late error from a socket that a
  /// reconnect already replaced is ignored, so it cannot tear down the healthy connection.
  private func handleSocketError(_ error: any Error, from conn: any WebSocket) {
    guard !(error is CancellationError) else {
      options.logger.debug("CancellationError do not trigger reconnects.")
      return
    }

    guard case .connected(let current) = connection, current === conn else {
      options.logger.debug("Ignoring error from a stale or absent connection: \(error)")
      return
    }

    options.logger.debug("Connection error, initiating reconnect: \(error.localizedDescription)")
    current.close(code: nil, reason: "error: \(error.localizedDescription)")
    stopConnectionTasks()
    initiateReconnect(reason: "error: \(error.localizedDescription)")
  }

  /// Handles a close initiated by the remote. The socket is already closed; just update state.
  ///
  /// Like `handleSocketError`, a `.close` frame from a socket a reconnect already replaced is
  /// ignored so it cannot mark a healthy connection as disconnected.
  private func handleClose(code: Int?, reason: String?, from conn: any WebSocket) {
    let closeReason = "code: \(code?.description ?? "none"), reason: \(reason ?? "none")"
    options.logger.debug("Connection closed by remote: \(closeReason)")

    guard case .connected(let current) = connection, current === conn else {
      options.logger.debug("Ignoring close from a stale or absent connection: \(closeReason)")
      return
    }

    stopConnectionTasks()
    // Application-level close codes (4000–4999) typically signal auth or protocol errors.
    // Reconnecting with the same bad token would loop; the caller must re-authenticate before
    // reconnecting.
    if let code, code >= 4000 {
      options.logger.debug("Skipping reconnect for application close code \(code)")
      setConnectionState(.disconnected)
      return
    }
    initiateReconnect(reason: closeReason)
  }

  // MARK: - Reconnect

  /// Keeps retrying with exponential backoff until a connection is established or the task is
  /// cancelled (`disconnect()` / `deinit`).
  ///
  /// State stays `.reconnecting` for every attempt — a failed attempt here does not flip state
  /// to `.disconnected`, so a `connect()` caller waiting on the task sees one outcome.
  private func initiateReconnect(reason: String) {
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

    setConnectionState(.reconnecting(reconnectTask))
  }

  /// A single reconnect attempt. Only succeeds into `.connected`; a failure is left for the
  /// loop in `initiateReconnect` to retry.
  private func performReconnectAttempt() async throws {
    guard case .reconnecting = connection else { throw CancellationError() }
    let conn = try await wsTransport(webSocketURL, options.headers.dictionary)
    try Task.checkCancellation()
    // `disconnect()` ran during the handshake.
    guard case .reconnecting = connection else {
      conn.close(code: nil, reason: "Connection cancelled")
      throw CancellationError()
    }
    handleConnected(conn, isReconnect: true)
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
