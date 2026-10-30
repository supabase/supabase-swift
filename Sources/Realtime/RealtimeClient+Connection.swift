//
//  RealtimeClient+Connection.swift
//  Realtime
//
//  Created by Guilherme Souza on 19/10/26.
//

import Foundation
import Helpers
import Logging

// MARK: - Apply loop

/// What the batch of a ``RealtimeClient/disconnect(code:reason:)`` stopped: the outbox of the
/// socket, which still holds the frames queued before the call, and the close of that socket.
struct StoppedSocket {
  var outbox: Outbox?
  var close: (() -> Void)?
}

extension RealtimeClient {
  /// Hands `event` to the core and runs the effects it returns, in order. It never suspends, and
  /// no effect hands the core an event, so the core never sees two events at once. A waiter the
  /// core resolves resumes as its effect runs; it continues on this actor, so only once the
  /// whole batch is applied, and it reads the state the batch left.
  func apply(_ event: RealtimeCore.Event) {
    let effects = core.handle(event, at: CoreTime(elapsed: elapsed(), date: now()))
    for effect in effects {
      run(effect)
    }
  }

  // MARK: Inbox

  /// Applies one input from an edge. The pump calls this once per input, in the order the edges
  /// yielded them. An input whose stamp no longer matches, because the work that yielded it was
  /// replaced or stopped, is dropped.
  func receive(_ input: Input) {
    switch input {
    case .socket(let input, let generation):
      guard generation == self.generation else {
        logger.debug("Ignoring event from a stale connection: \(input)")
        return
      }
      switch input {
      case .frame(let message):
        apply(.frame(message))
      case .binaryBroadcast(let broadcast):
        apply(.binaryBroadcast(broadcast))
      case .closed(let code, let reason):
        logger.debug(
          "WebSocket closed. Code: \(code?.description ?? "<none>"), Reason: \(reason ?? "<none>")"
        )
        apply(.socketClosed(code: code, reason: reason))
      }

    case .connectEnded(let result, let attempt):
      connectAttemptEnded(result, attempt: attempt)

    case .timerFired(let id, let token):
      guard timers.claimFire(id, token: token) else { return }
      apply(.timerFired(id))

    case .retryTimerFired(let token):
      guard retryTimer?.token == token else { return }
      retryTimer = nil
      apply(.retryTimerFired)

    case .idleTimerFired(let token):
      guard idleDisconnectTimer?.token == token else { return }
      idleDisconnectTimer = nil
      apply(.disconnectRequested(code: nil, reason: nil))

    case .tokenFetched(let token, let generation):
      tokenFetchEnded(token, generation: generation)

    case .streamEnded:
      // No stream yields this yet.
      break

    case .waiterCancelled(let id):
      apply(.waiterCancelled(id))

    case .removalWaitCancelled(let id, let topic):
      removalWaitCancelled(id, topic: topic)

    case .tokenWaitCancelled(let id):
      tokenFetchWaiters.removeValue(forKey: id)?.resume()

    case .bindingsChanged(let id):
      bindingsChanged(id)

    case .appBackground:
      handleAppBackground()

    case .appForeground:
      handleAppForeground()

    case .flush(let continuation):
      continuation.resume()
    }
  }

  /// Returns once the pump has applied every input yielded before this call.
  nonisolated func flushInbox() async {
    await withCheckedContinuation { continuation in
      if case .terminated = inbox.yield(.flush(continuation)) {
        continuation.resume()
      }
    }
  }

  // MARK: Waiters

  /// Parks the caller until the core resolves the waiter that `make` hands the event. The
  /// waiter is parked and the event applied in one actor step, so the core can resolve it in
  /// the same batch. A cancelled caller throws `CancellationError`: the cancel only yields
  /// ``Input/waiterCancelled(_:)``, which the pump applies after the current actor job, so it
  /// never overtakes its own park.
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
    } onCancel: { [inbox] in
      inbox.yield(.waiterCancelled(id))
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
    guard core.channels[removing.id] != nil else {
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
      } onCancel: { [inbox] in
        inbox.yield(.removalWaitCancelled(id, topic: topic))
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

  /// Runs one effect. It never hands an event to the core: the tasks it starts yield their
  /// inputs into the inbox, and the pump applies them later.
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
      let close = { conn.close(code: WebSocketCloseCode(rawValue: code ?? 1000), reason: reason) }
      if stoppedByDisconnect != nil {
        stoppedByDisconnect?.close = close
      } else {
        close()
      }

    case .stopSocketLoops:
      stopSocketLoops()

    case .cancelAllTasks:
      stopSocketLoops()
      connectAttempt?.task.cancel()
      connectAttempt = nil
      retryTimer?.task.cancel()
      retryTimer = nil
      idleDisconnectTimer?.task.cancel()
      idleDisconnectTimer = nil
      // The `accessToken` call goes on: it is bounded by the request timeout, and the core waits
      // for its `.tokenFetched`.
      timers.cancelAll()

    case .scheduleRetry(let delay):
      logger.debug("Reconnecting in \(delay)")
      retryTimer?.task.cancel()
      let token = nextShellTimerToken()
      retryTimer = (token, inboxTimer(after: delay, .retryTimerFired(token: token)))

    case .cancelRetry:
      retryTimer?.task.cancel()
      retryTimer = nil

    case .scheduleIdleDisconnect(let delay):
      idleDisconnectTimer?.task.cancel()
      let token = nextShellTimerToken()
      idleDisconnectTimer = (token, inboxTimer(after: delay, .idleTimerFired(token: token)))

    case .cancelIdleDisconnect:
      idleDisconnectTimer?.task.cancel()
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
      waiters.resume(id, with: outcome)

    case .publishClientStatus(let status):
      sinks.status.yield(status)

    case .publishHeartbeat(let event):
      sinks.heartbeats.yield(event)

    case .publishChannelStatus(let id, let status):
      channel(withID: id)?.sinks.status.yield(status)

    case .deliver(let id, let delivery):
      guard let sinks = channel(withID: id)?.sinks else { return }
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

    case .finishChannel(let id):
      if let removed = removedChannels.first(where: { $0.value.id == id })?.value {
        // `removeChannel(_:)` already spent it.
        removedChannels[removed.topic] = nil
        removalEnded(removed.topic)
        return
      }
      // The server closed the channel.
      guard let channel = sinks.channel(withID: id) else { return }
      sinks.removeChannel(channel)
      channel.sinks.finishAll()

    case .fetchAccessToken(let generation):
      fetchAccessToken(generation: generation)
    }
  }

  /// The channel that gets the effects for `id`: a registered channel, or one being removed
  /// until the core drops it, even when a newer channel took its topic in the registry.
  private func channel(withID id: ChannelID) -> RealtimeChannel? {
    removedChannels.values.first { $0.id == id } ?? sinks.channel(withID: id)
  }

  private func stopSocketLoops() {
    generation += 1
    reader?.cancel()
    reader = nil
    if stoppedByDisconnect != nil {
      if let outbox { stoppedByDisconnect?.outbox = outbox }
    } else {
      outbox?.close()
    }
    outbox = nil
    socket = nil
  }

  // MARK: Timers

  /// Starts the core's timer `id`, replacing the one already scheduled for `id`. Its fire
  /// yields ``Input/timerFired(_:token:)``.
  func scheduleTimer(_ id: TimerID, after delay: Duration) {
    timers.schedule(id, after: delay, clock: clock) { [inbox] id, token in
      inbox.yield(.timerFired(id, token: token))
    }
  }

  private func nextShellTimerToken() -> UInt64 {
    lastShellTimerToken += 1
    return lastShellTimerToken
  }

  /// An edge: sleeps `delay`, then yields `input`.
  private nonisolated func inboxTimer(after delay: Duration, _ input: Input) -> Task<Void, Never> {
    // A local, because the existential in `self.clock` is not opened when passed directly.
    let clock = clock
    return sleepThenRun(on: clock, after: delay) { [inbox] in
      inbox.yield(input)
    }
  }

  // MARK: Socket

  /// Starts a connect attempt. Its result is applied unless `.cancelAllTasks` or a newer
  /// attempt replaced it first; a socket that opens too late is closed.
  private func openSocket() {
    connectAttempt?.task.cancel()
    lastConnectAttempt += 1
    let attempt = lastConnectAttempt
    connectAttempt = (attempt, connect(attempt: attempt))
  }

  /// An edge: opens a socket and yields ``Input/connectEnded(_:attempt:)``. A socket that opens
  /// after the client was released is closed.
  private nonisolated func connect(attempt: Int) -> Task<Void, Never> {
    Task(priority: .medium) { [inbox, transport, webSocketURL, headers] in
      let result: Result<any WebSocketConnection, any Error>
      do {
        result = .success(try await transport.connect(to: webSocketURL, headerFields: headers))
      } catch {
        result = .failure(error)
      }
      if case .terminated = inbox.yield(.connectEnded(result, attempt: attempt)),
        case .success(let conn) = result
      {
        conn.close(code: .normalClosure, reason: "Client deallocated")
      }
    }
  }

  private func connectAttemptEnded(
    _ result: Result<any WebSocketConnection, any Error>, attempt: Int
  ) {
    let isCurrent = connectAttempt?.id == attempt
    if isCurrent {
      connectAttempt = nil
    }
    switch result {
    case .success(let conn):
      guard isCurrent else {
        conn.close(code: .normalClosure, reason: "Connection cancelled")
        return
      }
      logger.debug("Connected to realtime WebSocket")
      apply(.socketOpened(conn))
    case .failure(let error):
      logger.error("Connection failed: \(error)")
      guard isCurrent else { return }
      apply(.socketOpenFailed(Self.realtimeError(error)))
    }
  }

  /// An edge: reads the socket until it closes or fails, decodes each event off the actor, and
  /// yields it stamped with `generation`. A frame that fails to decode is logged and dropped.
  ///
  /// It holds only the inbox, never the client: a task that retained the client for as long as
  /// the socket stays open would keep a released client from reaching `deinit`, leaking it, the
  /// socket, and its `URLSession`.
  private nonisolated func listen(
    to connection: any WebSocketConnection, generation: Int
  ) -> Task<Void, Never> {
    let events = connection.events
    return Task(priority: .medium) { [inbox, serializer, logger] in
      for await event in events {
        if Task.isCancelled { return }
        let input: SocketInput
        switch event {
        case .frame(.binary(let data)):
          do {
            input = .binaryBroadcast(try serializer.decodeBinary(data))
          } catch {
            logger.error("Failed to decode binary frame: \(error)")
            continue
          }
        case .frame(.text(let text)):
          do {
            input = .frame(try serializer.decodeText(text))
          } catch {
            logger.error("Failed to decode text frame: \(error)")
            continue
          }
        case .closed(let code, let reason):
          input = .closed(code: code?.rawValue, reason: reason)
        }
        if case .terminated = inbox.yield(.socket(input, generation: generation)) { return }
      }
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

  /// Starts two edges that race to yield ``Input/tokenFetched(_:generation:)``: the
  /// `accessToken` callback call, which reports `nil` when the call fails, and a timer that
  /// reports `nil` after `requestTimeout`. The first to arrive for the fetch wins, and the
  /// actor cancels the other.
  private func fetchAccessToken(generation: Int) {
    tokenFetch?.call.cancel()
    tokenFetch?.timeout.cancel()
    tokenFetch = (
      generation, callAccessToken(generation: generation),
      accessTokenTimeout(generation: generation)
    )
  }

  private nonisolated func callAccessToken(generation: Int) -> Task<Void, Never> {
    let provider = options.accessToken
    return Task(priority: .medium) { [inbox, logger] in
      var token: String?
      if let provider {
        do {
          token = try await provider()
        } catch {
          logger.error("Failed to fetch access token: \(error)")
        }
      }
      inbox.yield(.tokenFetched(token, generation: generation))
    }
  }

  private nonisolated func accessTokenTimeout(generation: Int) -> Task<Void, Never> {
    let timeout = options.requestTimeout
    // A local, because the existential in `self.clock` is not opened when passed directly.
    let clock = clock
    return sleepThenRun(on: clock, after: timeout) { [inbox, logger] in
      logger.error("The access token callback did not return within \(timeout)")
      inbox.yield(.tokenFetched(nil, generation: generation))
    }
  }

  /// Applies the first result for the fetch in flight and cancels both of its edges, so
  /// `.tokenFetched` reaches the core once per fetch. The callers of ``refreshAccessToken()``
  /// resume after it.
  private func tokenFetchEnded(_ token: String?, generation: Int) {
    guard let fetch = tokenFetch, fetch.generation == generation else { return }
    // Cleared before the event: the core may start the next fetch while it applies it.
    tokenFetch = nil
    fetch.call.cancel()
    fetch.timeout.cancel()
    apply(.tokenFetched(token: token, generation: generation))
    let waiting = tokenFetchWaiters.values
    tokenFetchWaiters = [:]
    for waiter in waiting {
      waiter.resume()
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
