//
//  RealtimeClient+Connection.swift
//  Realtime
//
//  Created by Guilherme Souza on 19/10/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Logging

// MARK: - Apply loop

extension RealtimeClient {
  /// Hands `event` to the core and runs the effects it returns, in order. An event that arrives
  /// while a batch is being applied waits in `pending`, so the core never sees two events at
  /// once. The waiters the batch resolved resume once every effect is applied, so a caller that
  /// returns from a wait reads the state the batch left.
  func apply(_ event: RealtimeCore.Event) {
    pending.append(event)
    guard pending.count == 1 else { return }
    while let next = pending.first {
      let effects = core.handle(next, at: CoreTime(elapsed: elapsed(), date: now()))
      for effect in effects {
        run(effect)
      }
      pending.removeFirst()
    }
    let outcomes = resolved
    resolved = []
    for (id, outcome) in outcomes {
      waiters.resume(id, with: outcome)
    }
  }

  /// Parks the caller until the core resolves the waiter that `make` hands the event. The
  /// waiter is parked before the event is applied, in one synchronous step, so the core can
  /// resolve it in the same batch. A cancelled caller throws `CancellationError` at once.
  ///
  /// A caller that is already cancelled throws before the core sees the event, unless
  /// `evenIfCancelled` is set: then the event is applied, and only the wait ends at once.
  func wait(
    evenIfCancelled: Bool = false, _ make: @Sendable (WaiterID) -> RealtimeCore.Event
  ) async throws {
    if !evenIfCancelled {
      try Task.checkCancellation()
    }
    let id = waiters.next()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiters.park(id, continuation)
        apply(make(id))
      }
    } onCancel: {
      Task { await self.apply(.waiterCancelled(id)) }
    }
  }

  /// ``wait(evenIfCancelled:_:)`` for an action of `channel`. The checks run here, on the actor,
  /// so an action cannot slip past a ``removeChannel(_:)`` that ran since the caller checked.
  ///
  /// While an older channel of the same topic is being removed, the action waits for that
  /// removal to end, then runs as on a new channel. With `evenIfCancelled`, a cancelled caller
  /// still waits for the removal, at most the older channel's leave timeout, then acts.
  func wait(
    on channel: RealtimeChannel, evenIfCancelled: Bool = false,
    _ make: @Sendable (WaiterID) -> RealtimeCore.Event
  ) async throws {
    try await waitForRemoval(blocking: channel, evenIfCancelled: evenIfCancelled)
    try await wait(evenIfCancelled: evenIfCancelled, make)
  }

  /// The channel being removed that holds the topic of `channel`, if it is another channel. The
  /// core keeps that channel's record until its leave ends, so an action of `channel` would act on
  /// the old record.
  func removal(blocking channel: RealtimeChannel) -> RealtimeChannel? {
    guard let removing = removedChannels[channel.topic], removing !== channel else { return nil }
    guard core.channels[channel.topic] != nil else {
      // The removal is over; its `removeChannel(_:)` has not resumed yet.
      removedChannels[channel.topic] = nil
      removalEnded(channel.topic)
      return nil
    }
    return removing
  }

  /// Parks the caller until no other channel's removal holds the topic of `channel`. The removal
  /// ends when the older channel's leave ends, so the wait lasts at most its leave timeout. A
  /// cancelled caller throws `CancellationError` and leaves nothing behind, unless
  /// `evenIfCancelled` is set: then it waits on, so a cancelled `unsubscribe()` still leaves
  /// once the removal ends. A channel removed meanwhile throws `channelRemoved` at once.
  private func waitForRemoval(
    blocking channel: RealtimeChannel, evenIfCancelled: Bool
  ) async throws {
    let topic = channel.topic
    while true {
      guard !channel.sinks.isSpent else { throw RealtimeError.channelRemoved }
      guard removal(blocking: channel) != nil else { return }
      let id = waiters.next()
      if evenIfCancelled {
        try await parkUntilRemovalEnds(id, topic: topic)
        continue
      }
      try Task.checkCancellation()
      try await withTaskCancellationHandler {
        try await parkUntilRemovalEnds(id, topic: topic)
      } onCancel: {
        Task { await self.removalWaitCancelled(id, topic: topic) }
      }
    }
  }

  private func parkUntilRemovalEnds(_ id: WaiterID, topic: String) async throws {
    try await withCheckedThrowingContinuation { continuation in
      waiters.park(id, continuation)
      removalWaiters[topic, default: []].append(id)
    }
  }

  private func removalWaitCancelled(_ id: WaiterID, topic: String) {
    removalWaiters[topic]?.removeAll { $0 == id }
    if removalWaiters[topic]?.isEmpty == true {
      removalWaiters[topic] = nil
    }
    waiters.resume(id, with: .cancelled)
  }

  /// Wakes the actions that wait for the removal on `topic` to end.
  func removalEnded(_ topic: String) {
    for id in removalWaiters.removeValue(forKey: topic) ?? [] {
      waiters.resume(id, with: .success)
    }
  }

  /// Runs one effect. It never hands an event to the core directly: tasks apply their events
  /// later, through ``apply(_:)``.
  private func run(_ effect: RealtimeCore.Effect) {
    switch effect {
    case .openSocket:
      openSocket()

    case .installSocket(let conn, _):
      // The core sends the rejoins itself, so `rejoinChannels` needs nothing here.
      stopSocketLoops()
      socket = conn
      outbox = Outbox(connection: conn, serializer: serializer, logger: logger)
      reader = listen(to: conn, generation: generation)

    case .closeSocket(let conn, let code, let reason):
      // A `nil` code is a normal closure.
      conn.close(code: WebSocketCloseCode(rawValue: code ?? 1000), reason: reason)

    case .stopSocketLoops:
      stopSocketLoops()

    case .cancelAllTasks:
      stopSocketLoops()
      connectAttempt?.cancel()
      connectAttempt = nil
      retryTimer?.cancel()
      retryTimer = nil
      idleDisconnectTimer?.cancel()
      idleDisconnectTimer = nil
      // The `accessToken` call goes on: it is bounded by the request timeout, and the core waits
      // for its `.tokenFetched`.
      timers.cancelAll()

    case .scheduleRetry(let delay):
      logger.debug("Reconnecting in \(delay)")
      retryTimer?.cancel()
      retryTimer = shellTimer(after: delay) { $0.apply(.retryTimerFired) }

    case .cancelRetry:
      retryTimer?.cancel()
      retryTimer = nil

    case .scheduleIdleDisconnect(let delay):
      idleDisconnectTimer?.cancel()
      idleDisconnectTimer = shellTimer(after: delay) {
        $0.apply(.disconnectRequested(code: nil, reason: nil))
      }

    case .cancelIdleDisconnect:
      idleDisconnectTimer?.cancel()
      idleDisconnectTimer = nil

    case .send(let message):
      guard let outbox else {
        logger.debug("Dropping \(message.event) on '\(message.topic)': no socket")
        return
      }
      outbox.enqueue(message)

    case .sendBroadcast(let joinRef, let ref, let topic, let event, let payload):
      sendBroadcast(joinRef: joinRef, ref: ref, topic: topic, event: event, payload: payload)

    case .schedule(let id, let delay):
      scheduleTimer(id, after: delay)

    case .cancel(let id):
      timers.cancel(id)

    case .resume(let id, let outcome):
      resolved.append((id, outcome))

    case .publishClientStatus(let status):
      sinks.status.yield(status)

    case .publishHeartbeat(let event):
      sinks.heartbeats.yield(event)

    case .publishChannelStatus(let topic, let status):
      channel(for: topic)?.sinks.status.yield(status)

    case .deliver(let topic, let delivery):
      guard let sinks = channel(for: topic)?.sinks else { return }
      switch delivery {
      case .broadcast(let message):
        sinks.broadcasts.yield(message)
      case .postgres(let change):
        sinks.postgres.yield(change)
      case .presence(let change, let state):
        sinks.presenceChanges.yield(change)
        sinks.presenceStates.yield(state)
      case .event(let event):
        sinks.events.yield(event)
      }

    case .finishChannel(let topic):
      if removedChannels.removeValue(forKey: topic) != nil {
        // `removeChannel(_:)` already spent it.
        removalEnded(topic)
        return
      }
      // The server closed the channel.
      guard let channel = sinks.channel(for: topic) else { return }
      sinks.removeChannel(channel)
      channel.sinks.finishAll()

    case .fetchAccessToken(let generation):
      fetchAccessToken(generation: generation)
    }
  }

  /// The channel that gets the effects for `topic`. A channel being removed keeps its topic
  /// until the core drops it, even when a newer channel took the topic in the registry.
  private func channel(for topic: String) -> RealtimeChannel? {
    removedChannels[topic] ?? sinks.channel(for: topic)
  }

  private func stopSocketLoops() {
    generation += 1
    reader?.cancel()
    reader = nil
    outbox?.close()
    outbox = nil
    socket = nil
  }

  // MARK: Timers

  /// Starts the core's timer `id`, replacing the one already scheduled for `id`.
  func scheduleTimer(_ id: TimerID, after delay: Duration) {
    timers.schedule(id, after: delay, clock: clock) { [weak self] id, token in
      await self?.timerFired(id, token: token)
    }
  }

  /// Applies `.timerFired` for the timer that `token` started, unless it was replaced or
  /// cancelled since.
  func timerFired(_ id: TimerID, token: UInt64) {
    guard timers.claimFire(id, token: token) else { return }
    apply(.timerFired(id))
  }

  /// Sleeps `delay`, then runs `fire` on the client. The check for cancellation runs on the
  /// actor, so a timer cancelled after its sleep ended does not fire.
  ///
  /// Weak: the sleep must not keep a released client alive until it ends.
  private func shellTimer(
    after delay: Duration,
    fire: @escaping @Sendable (isolated RealtimeClient) -> Void
  ) -> Task<Void, Never> {
    // A local, because the existential in `self.clock` is not opened when passed directly.
    let clock = clock
    return sleepThenRun(on: clock, after: delay) { [weak self] in
      await self?.fireShellTimer(fire)
    }
  }

  private func fireShellTimer(_ fire: @Sendable (isolated RealtimeClient) -> Void) {
    guard !Task.isCancelled else { return }
    fire(self)
  }

  // MARK: Socket

  /// Starts a connect attempt. It applies `.socketOpened` or `.socketOpenFailed` unless
  /// `.cancelAllTasks` cancelled it first; a socket that opens too late is closed.
  private func openSocket() {
    connectAttempt?.cancel()
    connectAttempt = Task.detached { [weak self, transport, webSocketURL, headers] in
      let result: Result<any WebSocketConnection, any Error>
      do {
        result = .success(try await transport.connect(to: webSocketURL, headerFields: headers))
      } catch {
        result = .failure(error)
      }
      guard let self else {
        if case .success(let conn) = result {
          conn.close(code: .normalClosure, reason: "Client deallocated")
        }
        return
      }
      await self.connectAttemptEnded(result)
    }
  }

  /// Runs on the attempt's own task, so `Task.isCancelled` tells whether the attempt was
  /// cancelled before its outcome got here.
  private func connectAttemptEnded(_ result: Result<any WebSocketConnection, any Error>) {
    switch result {
    case .success(let conn):
      guard !Task.isCancelled else {
        conn.close(code: .normalClosure, reason: "Connection cancelled")
        return
      }
      logger.debug("Connected to realtime WebSocket")
      apply(.socketOpened(conn))
    case .failure(let error):
      logger.error("Connection failed: \(error)")
      guard !Task.isCancelled else { return }
      apply(.socketOpenFailed(Self.realtimeError(error)))
    }
  }

  /// Reads the socket until it closes or fails.
  ///
  /// Detached, and `self` is resolved per event: a loop task isolated to this actor would retain
  /// it for as long as the socket stays open, so a client released while connected could never
  /// reach `deinit` and would leak itself, the socket and its `URLSession`.
  private func listen(
    to connection: any WebSocketConnection, generation: Int
  ) -> Task<Void, Never> {
    let events = connection.events
    return Task.detached { [weak self] in
      for await event in events {
        if Task.isCancelled { return }
        guard let self else { return }
        await self.receive(event, generation: generation)
      }
    }
  }

  /// Applies one event from the socket installed at `generation`. Events from an older socket
  /// are dropped: a reconnect already replaced it, and its close must not tear down the healthy
  /// connection.
  func receive(_ event: WebSocketEvent, generation: Int) {
    guard generation == self.generation else {
      logger.debug("Ignoring event from a stale connection: \(event)")
      return
    }

    switch event {
    case .frame(.binary(let data)):
      do {
        apply(.binaryBroadcast(try serializer.decodeBinary(data)))
      } catch {
        logger.error("Failed to decode binary frame: \(error)")
      }

    case .frame(.text(let text)):
      do {
        apply(.frame(try serializer.decodeText(text)))
      } catch {
        logger.error("Failed to decode text frame: \(error)")
      }

    case .closed(let code, let reason):
      logger.debug(
        "WebSocket closed. Code: \(code?.rawValue.description ?? "<none>"), Reason: \(reason ?? "<none>")"
      )
      apply(.socketClosed(code: code?.rawValue, reason: reason))
    }
  }

  private func sendBroadcast(
    joinRef: Ref?, ref: Ref, topic: String, event: String, payload: BroadcastPushPayload
  ) {
    guard let outbox else {
      logger.debug("Dropping broadcast '\(event)' on '\(topic)': no socket")
      return
    }
    do {
      let data =
        switch payload {
        case .json(let object):
          try serializer.encodeBroadcastPush(
            joinRef: joinRef, ref: ref, topic: topic, event: event, jsonPayload: object)
        case .binary(let binary):
          try serializer.encodeBroadcastPush(
            joinRef: joinRef, ref: ref, topic: topic, event: event, binaryPayload: binary)
        }
      outbox.enqueue(.binary(data))
    } catch {
      logger.error(
        """
        Failed to send binary broadcast:
        topic=\(topic), event=\(event)

        Error:
        \(error)
        """
      )
    }
  }

  // MARK: Access token

  /// Calls the `accessToken` callback and applies `.tokenFetched` once, with `nil` when the call
  /// fails, times out, or is cancelled. The callers of ``refreshAccessToken()`` resume after it.
  private func fetchAccessToken(generation: Int) {
    let provider = options.accessToken
    let timeout = options.requestTimeout
    let logger = logger
    // A local, because the existential in `self.clock` is not opened when passed directly.
    let clock = clock
    tokenFetch = Task.detached { [weak self] in
      let token: String?
      if let provider {
        token = await Self.callAccessTokenProvider(
          provider, timeout: timeout, clock: clock, logger: logger)
      } else {
        token = nil
      }
      await self?.tokenFetchEnded(token, generation: generation)
    }
  }

  private func tokenFetchEnded(_ token: String?, generation: Int) {
    tokenFetch = nil
    apply(.tokenFetched(token: token, generation: generation))
    let waiting = tokenFetchWaiters.values
    tokenFetchWaiters = [:]
    for waiter in waiting {
      waiter.resume()
    }
  }

  /// Calls `provider` and returns its token, or `nil` when it throws, does not return within
  /// `timeout`, or the calling task is cancelled. A call that ignores cancellation is left to
  /// finish on its own and its result is dropped, so it cannot hold up the client. `withTimeout`
  /// cannot do this: its task group waits for the call to return.
  private static func callAccessTokenProvider(
    _ provider: @escaping @Sendable () async throws -> String?,
    timeout: Duration,
    clock: some Clock<Duration>,
    logger: Logger
  ) async -> String? {
    let deadline = clock.now.advanced(by: timeout)
    let pending = LockIsolated<CheckedContinuation<String?, Never>?>(nil)
    let call = LockIsolated<Task<Void, Never>?>(nil)
    let timer = LockIsolated<Task<Void, Never>?>(nil)
    // Returns whether this resumed the caller: only the first of the call, the timer, and the
    // cancellation does.
    let finish: @Sendable (String?) -> Bool = { token in
      pending.withValue { continuation in
        guard let waiting = continuation else { return false }
        continuation = nil
        waiting.resume(returning: token)
        return true
      }
    }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        pending.setValue(continuation)
        // The timer exists before the call starts, so a call that returns at once can cancel it.
        timer.setValue(
          Task {
            do {
              try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
              return
            }
            guard finish(nil) else { return }
            logger.error("The access token callback did not return within \(timeout)")
            call.value?.cancel()
          })
        call.setValue(
          Task {
            let token: String?
            do {
              token = try await provider()
            } catch {
              logger.error("Failed to fetch access token: \(error)")
              token = nil
            }
            timer.value?.cancel()
            _ = finish(token)
          })
      }
    } onCancel: {
      if finish(nil) {
        timer.value?.cancel()
        call.value?.cancel()
      }
    }
  }

  // MARK: Errors

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
