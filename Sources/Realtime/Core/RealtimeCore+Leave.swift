//
//  RealtimeCore+Leave.swift
//  Realtime
//

import Logging

extension RealtimeCore {
  // MARK: Unsubscribe

  /// Leaves the topic. A subscribed channel sends `phx_leave` and waits, bounded by the timeout,
  /// for the server's `phx_close`. Any other channel ends its join at once.
  mutating func unsubscribe(_ topic: String, waiter: WaiterID) -> [Effect] {
    guard var record = channels[topic] else { return [.resume(waiter, .success)] }
    // A later subscribe is a new subscription, not a rejoin.
    record.hasBeenSubscribed = false
    let cleared = record.presence.clear()
    channels[topic] = record
    var effects: [Effect] =
      cleared.isEmpty ? [] : [.deliver(topic, .presence(cleared, record.presence.state))]

    switch record.phase {
    case .unsubscribed:
      logger.debug("Unsubscribe no-op for channel '\(topic)': already unsubscribed")
      return effects + [.resume(waiter, .success)]

    case .failed:
      return effects + setPhase(.unsubscribed, for: topic) + [.resume(waiter, .success)]

    case .leaving:
      // This caller wants the channel to stay unsubscribed.
      channels[topic]?.leaveWaiters.append(waiter)
      channels[topic]?.subscribeWaiters = []
      return effects + record.subscribeWaiters.map { .resume($0, .cancelled) }

    case .subscribed(let joinRef) where isConnected:
      let leaveRef = makeRef()
      channels[topic]?.leaveWaiters.append(waiter)
      logger.debug("Leaving channel '\(topic)' (join_ref: \(joinRef), ref: \(leaveRef))")
      return effects + [.send(leaveMessage(topic, joinRef: joinRef, ref: leaveRef))]
        + setPhase(.leaving(joinRef: joinRef, leaveRef: leaveRef), for: topic)
        + [.schedule(.leaveTimeout(topic: topic, ref: leaveRef), after: options.timeout)]

    case .subscribed, .waitingForSocket, .refreshingToken, .joining, .waitingToRetry:
      // The server may not know the join, or the socket is gone, so `phx_close` may never
      // come: leave without waiting.
      logger.debug("Unsubscribing channel '\(topic)' without waiting for the server")
      if let joinRef = record.currentJoinRef {
        effects += sendLeave(topic, joinRef: joinRef)
      }
      return effects
        + endJoin(
          topic, subscribers: .cancelled, pushes: .notSubscribed, phase: .unsubscribed)
        + [.resume(waiter, .success)]
    }
  }

  mutating func leaveTimedOut(_ topic: String, ref: Ref) -> [Effect] {
    guard case .leaving(_, ref)? = channels[topic]?.phase else { return [] }
    logger.debug("Leave timed out for channel '\(topic)'")
    return leaveEnded(topic, pushes: .notSubscribed, cancelTimer: false)
  }

  /// Ends the leave in flight: its callers return, and the channel is unsubscribed. A
  /// subscribe that came during the leave then joins again.
  private mutating func leaveEnded(
    _ topic: String, pushes: RealtimeError, cancelTimer: Bool
  ) -> [Effect] {
    guard var record = channels[topic], case .leaving(_, let leaveRef) = record.phase else {
      return []
    }
    let waiters = record.leaveWaiters
    record.leaveWaiters = []
    channels[topic] = record

    var effects: [Effect] = waiters.map { .resume($0, .success) }
    effects += failPendingPushes(topic, with: pushes)
    effects += setPhase(.unsubscribed, for: topic)
    if cancelTimer {
      effects.append(.cancel(.leaveTimeout(topic: topic, ref: leaveRef)))
    }
    if !record.subscribeWaiters.isEmpty {
      effects += sendJoin(topic, attempt: 1)
    }
    return effects
  }

  /// Sends `phx_leave` for the join `joinRef` on a connected socket.
  mutating func sendLeave(_ topic: String, joinRef: Ref) -> [Effect] {
    guard isConnected else { return [] }
    return [.send(leaveMessage(topic, joinRef: joinRef, ref: makeRef()))]
  }

  private func leaveMessage(_ topic: String, joinRef: Ref, ref: Ref) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: ref, topic: RealtimeChannel.wireTopic(for: topic),
      event: ChannelEvent.leave, payload: [:])
  }

  // MARK: Server close

  /// Applies `phx_close` or `phx_error` for the current join. A join in flight fails with
  /// ``RealtimeError/channelClosedByServer``, a leave is over, and any other join ends.
  /// `phx_close` also finishes the channel's streams and drops the channel, as today's
  /// `client.remove(self)`. Either message for an older join is ignored.
  mutating func receiveClose(_ message: RealtimeMessage) -> [Effect] {
    guard let topic = RealtimeChannel.topic(forWireTopic: message.topic),
      let record = channels[topic]
    else { return [] }
    let joinRef: Ref? =
      if case .leaving(let ref, _) = record.phase { ref } else { record.currentJoinRef }
    if let closed = message.joinRef, closed != joinRef {
      logger.debug(
        "Ignoring \(message.event) for stale join_ref \(closed) on '\(topic)' (current: \(joinRef ?? "<none>"))"
      )
      return []
    }
    logger.debug("Server closed channel '\(topic)' (\(message.event))")

    var effects: [Effect]
    switch record.phase {
    case .leaving:
      // The answer to `phx_leave`: the channel stays, so it can subscribe again.
      return leaveEnded(topic, pushes: .channelClosedByServer, cancelTimer: true)
    case .waitingForSocket, .refreshingToken, .joining, .waitingToRetry:
      effects = endJoin(
        topic, subscribers: .failure(.channelClosedByServer), pushes: .channelClosedByServer,
        phase: .failed(.channelClosedByServer))
    case .subscribed, .failed:
      effects = endJoin(
        topic, subscribers: .cancelled, pushes: .channelClosedByServer, phase: .unsubscribed)
    case .unsubscribed:
      effects = []
    }

    guard message.event == ChannelEvent.close else { return effects }
    channels[topic] = nil
    return effects + [.finishChannel(topic)]
  }

  // MARK: Socket loss and disconnect

  /// Runs a socket close or failure through the connection table. When it ends the
  /// connection, every channel loses its join and waits for the next socket.
  mutating func socketWentAway(_ event: Event) -> [Effect] {
    guard isConnected else { return transitionConnection(event) }
    return transitionConnection(event) + channelsLostSocket() + failSubscribesIfStopped()
  }

  /// Fails the subscribes that wait for a socket when the client will not reconnect on its
  /// own, for example after a 4000–4999 close. A channel with no caller keeps waiting, so the
  /// next `connect()` or a return to the foreground rejoins it.
  private mutating func failSubscribesIfStopped() -> [Effect] {
    guard case .disconnected(let error?) = connection else { return [] }
    var effects: [Effect] = []
    for topic in channels.keys.sorted() {
      guard let record = channels[topic], case .waitingForSocket = record.phase,
        !record.subscribeWaiters.isEmpty
      else { continue }
      effects += failSubscribe(topic, with: error)
    }
    return effects
  }

  /// Moves the channels on once the socket went away without `disconnect()`: a join in flight,
  /// a join waiting to retry, and a subscribed channel wait for the next socket, which joins
  /// them once (see ``connectAttemptEnded()``), and a leave is over. A push waiting for a reply
  /// fails with ``RealtimeError/notConnected``.
  private mutating func channelsLostSocket() -> [Effect] {
    var effects: [Effect] = []
    for topic in channels.keys.sorted() {
      guard let phase = channels[topic]?.phase else { continue }
      switch phase {
      case .joining(_, let attempt, _):
        effects += failPendingPushes(topic, with: .notConnected)
        effects += waitForNextSocket(topic, attempt: attempt)
      case .waitingToRetry(let attempt, _, _):
        effects += failPendingPushes(topic, with: .notConnected)
        effects += waitForNextSocket(topic, attempt: attempt + 1)
      case .subscribed:
        effects += failPendingPushes(topic, with: .notConnected)
        effects += waitForNextSocket(topic, attempt: 1)
      case .leaving:
        effects += leaveEnded(topic, pushes: .notConnected, cancelTimer: true)
      case .unsubscribed, .waitingForSocket, .refreshingToken, .failed:
        effects += failPendingPushes(topic, with: .notConnected)
      }
    }
    return effects
  }

  private mutating func waitForNextSocket(_ topic: String, attempt: Int) -> [Effect] {
    let timer = channels[topic]?.phase.timer(for: topic)
    channels[topic]?.timedOutJoinRef = nil
    return setPhase(.waitingForSocket(attempt: attempt), for: topic)
      + (timer.map { [.cancel($0)] } ?? [])
  }

  /// Ends every join after `disconnect()`. A subscribe in flight fails with
  /// ``RealtimeError/disconnectedWhileSubscribing`` instead of connecting again, a leave is
  /// over, and a push waiting for a reply fails with ``RealtimeError/notConnected``.
  mutating func disconnectChannels() -> [Effect] {
    var effects: [Effect] = []
    for topic in channels.keys.sorted() {
      guard var record = channels[topic] else { continue }
      switch record.phase {
      case .waitingForSocket, .refreshingToken, .joining, .waitingToRetry, .subscribed, .leaving:
        let leavers = record.leaveWaiters
        record.leaveWaiters = []
        channels[topic] = record
        effects += leavers.map { .resume($0, .success) }
        effects += endJoin(
          topic, subscribers: .failure(.disconnectedWhileSubscribing), pushes: .notConnected,
          phase: .unsubscribed)
      case .unsubscribed, .failed:
        effects += failPendingPushes(topic, with: .notConnected)
      }
    }
    return effects
  }

  // MARK: Helpers

  private var isConnected: Bool {
    if case .connected = connection { true } else { false }
  }

  /// Stops the channel's current join for good: resumes the subscribe callers with
  /// `subscribers` and the pushes waiting for a reply with `pushes`, moves to `phase`, and
  /// stops the timer the old phase waited on.
  private mutating func endJoin(
    _ topic: String, subscribers: WaiterOutcome, pushes: RealtimeError,
    phase: ChannelRecord.Phase
  ) -> [Effect] {
    guard var record = channels[topic] else { return [] }
    let timer = record.phase.timer(for: topic)
    let waiters = record.subscribeWaiters
    record.subscribeWaiters = []
    record.timedOutJoinRef = nil
    channels[topic] = record

    var effects: [Effect] = waiters.map { .resume($0, subscribers) }
    effects += failPendingPushes(topic, with: pushes)
    effects += setPhase(phase, for: topic)
    if let timer {
      effects.append(.cancel(timer))
    }
    return effects
  }

  /// Fails every push of `topic` that waits for a reply, in the order they were sent.
  private mutating func failPendingPushes(
    _ topic: String, with error: RealtimeError
  ) -> [Effect] {
    guard let pushes = channels[topic]?.pendingPushes, !pushes.isEmpty else { return [] }
    channels[topic]?.pendingPushes = [:]
    return pushes.sorted { (UInt64($0.key) ?? 0) < (UInt64($1.key) ?? 0) }
      .map { .resume($0.value, .failure(error)) }
  }
}

extension ChannelRecord.Phase {
  /// The timer this phase of the channel for `topic` waits on, if any.
  fileprivate func timer(for topic: String) -> TimerID? {
    switch self {
    case .joining(let ref, _, .reply):
      .joinTimeout(topic: topic, ref: ref)
    case .joining(let ref, _, .postgres):
      .postgresTimeout(topic: topic, ref: ref)
    case .waitingToRetry:
      .rejoin(topic: topic)
    case .leaving(_, let leaveRef):
      .leaveTimeout(topic: topic, ref: leaveRef)
    case .unsubscribed, .waitingForSocket, .refreshingToken, .subscribed, .failed:
      nil
    }
  }
}
