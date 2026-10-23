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
  /// connect attempt, from the timers, and from the socket reader.
  enum Event {
    /// `connect()` was called.
    case connectRequested
    /// The transport handed back an open socket.
    case socketOpened(any WebSocketConnection)
    /// The transport failed to open a socket.
    case socketOpenFailed(RealtimeError)
    /// `disconnect(code:reason:)` was called.
    case disconnectRequested(code: Int?, reason: String?)
    /// The remote closed the current socket.
    case socketClosed(code: Int?, reason: String?)
    /// The current socket failed (for now, a heartbeat that was never acknowledged).
    case socketFailed(RealtimeError)
    /// The backoff wait before the next reconnect attempt is over.
    case retryTimerFired
    /// A hint that the network may be back (the app came to the foreground). Cuts a backoff
    /// wait short; ignored in every other state.
    case wake
    /// The last channel was removed; disconnect after `disconnectAfter` unless one is added.
    case lastChannelRemoved(disconnectAfter: Duration)
    /// A channel was added.
    case channelAdded
  }

  /// What the transition asks the actor to do once the state is updated. Effects run in order,
  /// after `connection` has its new value, so nothing observes a half-applied transition.
  enum Effect: Equatable {
    /// Start a connect attempt.
    case openSocket
    /// Start the reader and heartbeat loops and flush buffered frames. After an automatic
    /// reconnect, also rejoin the channels.
    case installSocket(any WebSocketConnection, rejoinChannels: Bool)
    /// Close a socket, either the current one or one that opened too late.
    case closeSocket(any WebSocketConnection, code: Int?, reason: String)
    /// Stop the reader and heartbeat loops of the socket that just went away.
    case stopSocketLoops
    /// Cancel every task the client owns, including a connect attempt in flight.
    case cancelAllTasks
    /// Fire `.retryTimerFired` after `after`.
    case scheduleRetry(after: Duration)
    case cancelRetry
    /// Disconnect after `after`.
    case scheduleIdleDisconnect(after: Duration)
    case cancelIdleDisconnect

    static func == (lhs: Effect, rhs: Effect) -> Bool {
      switch (lhs, rhs) {
      case (.openSocket, .openSocket), (.stopSocketLoops, .stopSocketLoops),
        (.cancelAllTasks, .cancelAllTasks), (.cancelRetry, .cancelRetry),
        (.cancelIdleDisconnect, .cancelIdleDisconnect):
        return true
      case (.installSocket(let a, let ra), .installSocket(let b, let rb)):
        return a === b && ra == rb
      case (.closeSocket(let a, let ca, let ra), .closeSocket(let b, let cb, let rb)):
        return a === b && ca == cb && ra == rb
      case (.scheduleRetry(let a), .scheduleRetry(let b)),
        (.scheduleIdleDisconnect(let a), .scheduleIdleDisconnect(let b)):
        return a == b
      default:
        return false
      }
    }
  }

  /// The pure transition table. It never touches the actor: given the current state and an
  /// event, it updates the state and says which effects follow. `retryDelay(n)` is the wait
  /// after the n-th attempt failed.
  static func transition(
    _ state: inout ConnectionState, _ event: Event, retryDelay: (_ attempt: Int) -> Duration
  ) -> [Effect] {
    func waitToRetry(after attempt: Int, _ error: RealtimeError) -> Effect {
      let delay = retryDelay(attempt)
      state = .reconnecting(attempt: attempt, retryIn: delay, lastError: error)
      return .scheduleRetry(after: delay)
    }

    switch (state, event) {
    // connect()
    case (.disconnected, .connectRequested):
      state = .connecting(attempt: 1)
      return [.openSocket]
    case (.reconnecting(let attempt, _, _), .connectRequested),
      (.reconnecting(let attempt, _, _), .wake):
      state = .connecting(attempt: attempt + 1)
      return [.cancelRetry, .openSocket]
    case (_, .connectRequested), (_, .wake):
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
    case (_, .channelAdded):
      return [.cancelIdleDisconnect]
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
      let effects = Self.transition(&connection, next) { [reconnectBackoff, jitter] attempt in
        reconnectBackoff.delay(forAttempt: attempt, random: jitter)
      }
      options.logger.debug("Connection → \(connection) on \(next)")
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
      let generation = generation
      Task.immediateIfAvailable {
        await self.flushSendBuffer(on: conn)
        // A disconnect or a newer socket during the flush owns the channels now.
        guard rejoinChannels, generation == self.generation else { return }
        await self.rejoinChannels()
      }

    case .closeSocket(let conn, let code, let reason):
      // A `nil` code is a normal closure.
      conn.close(code: WebSocketCloseCode(rawValue: code ?? 1000), reason: reason)

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

    case .scheduleRetry(let delay):
      if case .reconnecting(let attempt, _, let error) = connection {
        options.logger.debug(
          "Reconnect attempt \(attempt + 1) in \(delay) after: \(error.message)")
      }
      tasks.replace([timer(after: delay) { $0.fireRetryTimer() }], at: .connection)

    case .cancelRetry:
      tasks.cancel(at: .connection)

    case .scheduleIdleDisconnect(let delay):
      tasks.replace(
        [timer(after: delay) { await $0.fireIdleDisconnect() }], at: .idleDisconnect)

    case .cancelIdleDisconnect:
      tasks.cancel(at: .idleDisconnect)
    }
  }

  /// Sleeps `delay`, then runs `fire` on the client.
  ///
  /// Detached and weak: the sleep must not keep a released client alive until it ends.
  private func timer(
    after delay: Duration,
    fire: @escaping @Sendable (isolated RealtimeClient) async -> Void
  ) -> Task<Void, Never> {
    Task.detached { [weak self, clock] in
      try? await clock.sleep(for: delay)
      guard let self else { return }
      await fire(self)
    }
  }

  /// Checks cancellation here, on the actor: a timer cancelled after its sleep ended but
  /// before it got here must not fire.
  private func fireRetryTimer() {
    guard !Task.isCancelled else { return }
    apply(.retryTimerFired)
  }

  private func fireIdleDisconnect() async {
    guard !Task.isCancelled else { return }
    await disconnect()
  }
}

// MARK: - Public API

extension RealtimeClient {
  /// Opens the WebSocket connection and suspends until it is established.
  ///
  /// Calling this method when already connected is a no-op, and calling it while a connection
  /// attempt is in progress waits for that attempt. While an automatic reconnect is waiting
  /// out its backoff, this tries at once instead; if that attempt fails, this throws and the
  /// automatic reconnect carries on. If
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

    case .reconnecting, .disconnected:
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
    switch connection {
    case .connected, .connecting:
      // An attempt in flight drives `rejoinChannels()` itself when it completes.
      return
    case .reconnecting:
      // The network is likely back; do not wait out the rest of the backoff.
      apply(.wake)
      return
    case .disconnected:
      break
    }

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

  /// Runs the transport for one connect attempt and reports the outcome to the machine. Every
  /// caller that awaits this task observes `.connected` once it returns.
  ///
  /// `.cancelAllTasks` and `.cancelRetry` cancel this task but cannot stop the transport call
  /// already in flight. A cancelled attempt drops its outcome here instead of handing it to
  /// whichever attempt is current by then.
  private func openSocket() async throws {
    let conn: any WebSocketConnection
    do {
      conn = try await openConnection()
    } catch {
      options.logger.error("Connection failed: \(error)")
      if !Task.isCancelled {
        apply(.socketOpenFailed(Self.realtimeError(error)))
      }
      throw error
    }

    apply(.socketOpened(conn))
    guard case .connected = connection else {
      throw CancellationError()
    }
    options.logger.debug("Connected to realtime WebSocket")
  }

  /// Asks the transport for a connection. One that opens after the calling task was cancelled
  /// is closed here, since nothing else will ever see it.
  private func openConnection() async throws -> any WebSocketConnection {
    let conn = try await transport.connect(to: webSocketURL, headerFields: options.headers)
    if Task.isCancelled {
      conn.close(code: .normalClosure, reason: "Connection cancelled")
      throw CancellationError()
    }
    return conn
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
  private func listenForMessages(on connection: any WebSocketConnection) {
    let stream = connection.events
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
      apply(.socketFailed(.heartbeatTimeout))
      return
    }

    let heartbeatRef = makeRef()
    pendingHeartbeatRef = heartbeatRef
    recordHeartbeat(.sent)
    // Not awaited: a write stalled on a half-open socket must not hold up the loop, or the
    // next tick never reports the missing acknowledgement.
    Task.immediateIfAvailable {
      await self.push(
        RealtimeMessageV2(
          joinRef: nil,
          ref: heartbeatRef,
          topic: "phoenix",
          event: "heartbeat",
          payload: [:]
        )
      )
      await self.setAuth()
    }
  }

  // MARK: Socket events

  /// Applies one frame from the socket installed at `generation`. Frames from an older socket
  /// are dropped: a reconnect already replaced it, and its close must not tear down the
  /// healthy connection.
  func handleSocketEvent(_ event: WebSocketEvent, generation: Int) async {
    guard generation == self.generation else {
      options.logger.debug("Ignoring event from a stale connection: \(event)")
      return
    }

    switch event {
    case .frame(.binary(let data)):
      do {
        let broadcast = try BroadcastFrameCodec.decode(data)
        options.logger.debug(
          "Received binary broadcast for topic \(broadcast.topic), event \(broadcast.event)"
        )
        await channels[broadcast.topic]?.handleBinaryBroadcast(broadcast)
      } catch {
        options.logger.error("Failed to decode binary frame: \(error)")
      }

    case .frame(.text(let text)):
      do {
        await onMessage(try serializer.decodeText(text))
      } catch {
        options.logger.error("Failed to decode text frame: \(error)")
      }

    case .closed(let code, let reason):
      options.logger.debug(
        "WebSocket closed. Code: \(code?.rawValue.description ?? "<none>"), Reason: \(reason ?? "<none>")"
      )
      apply(.socketClosed(code: code?.rawValue, reason: reason))
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

  /// Full-jitter exponential backoff: the n-th wait is a random duration in
  /// `0...min(30s, baseDelay · 2^(n-1))`. Spreading the waits over the whole range keeps
  /// clients that lost the same server from reconnecting in step. Attempts are unbounded.
  ///
  /// `baseDelay` is user-supplied and checked nowhere else, so it is clamped to `0...30s` here.
  static func reconnectBackoff(baseDelay: Duration) -> BackoffPolicy {
    let maxDelay: Duration = .seconds(30)
    return .fullJitter(base: min(max(baseDelay, .zero), maxDelay), cap: maxDelay)
  }

  /// The transport's failure as the error the connection state carries.
  static func realtimeError(_ error: any Error) -> RealtimeError {
    error as? RealtimeError ?? .transport(error.localizedDescription, underlyingError: error)
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
