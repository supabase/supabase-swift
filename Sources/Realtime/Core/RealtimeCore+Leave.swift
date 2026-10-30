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
    leave(topic, waiter: waiter, removing: false)
  }

  /// Removes the channel: like ``unsubscribe(_:waiter:)``, but a subscribe in flight and the
  /// pushes waiting for a reply fail with ``RealtimeError/channelRemoved``, and a join in
  /// flight on a connected socket leaves too. The channel is then finished and dropped, once
  /// the leave ends or at once when no leave is in flight.
  mutating func removeChannel(_ topic: String, waiter: WaiterID) -> [Effect] {
    guard channels[topic] != nil else {
      return [.resume(waiter, .success)] + disconnectIfNoChannels()
    }
    channels[topic]?.isRemoving = true
    var effects = failPendingPushes(topic, with: .channelRemoved)
    effects += leave(topic, waiter: waiter, removing: true)
    guard case .leaving? = channels[topic]?.phase else {
      return effects + dropChannel(topic) + disconnectIfNoChannels()
    }
    return effects
  }

  /// Leaves the topic for `waiter`, or for no caller when a join rolls back.
  private mutating func leave(_ topic: String, waiter: WaiterID?, removing: Bool) -> [Effect] {
    let done: [Effect] = waiter.map { [.resume($0, .success)] } ?? []
    guard var record = channels[topic] else { return done }
    let subscribers: WaiterOutcome = removing ? .failure(.channelRemoved) : .cancelled
    let pushes: RealtimeError = removing ? .channelRemoved : .notSubscribed
    // A later subscribe is a new subscription, not a rejoin.
    record.hasBeenSubscribed = false
    record.isAutomaticRejoin = false
    let cleared = record.presence.clear()
    channels[topic] = record
    var effects: [Effect] =
      cleared.isEmpty ? [] : [.deliver(topic, .presence(cleared, record.presence.state))]

    switch record.phase {
    case .unsubscribed:
      logger.debug("Unsubscribe no-op for channel '\(topic)': already unsubscribed")
      return effects + done

    case .failed:
      return effects + setPhase(.unsubscribed, for: topic) + done

    case .leaving:
      // This caller wants the channel to stay unsubscribed.
      if let waiter { channels[topic]?.leaveWaiters.append(waiter) }
      channels[topic]?.subscribeWaiters = []
      return effects + record.subscribeWaiters.map { .resume($0, subscribers) }

    case .subscribed(let joinRef) where isConnected,
      .joining(let joinRef, _, _) where isConnected && removing:
      // A join in flight leaves only for `removeChannel`: the server has the join, so it
      // answers the leave, and the channel must not outlive it.
      let leaveRef = makeRef()
      let leaving = ChannelRecord.Phase.leaving(joinRef: joinRef, leaveRef: leaveRef)
      if let waiter { channels[topic]?.leaveWaiters.append(waiter) }
      logger.debug("Leaving channel '\(topic)' (join_ref: \(joinRef), ref: \(leaveRef))")
      effects.append(.send(leaveMessage(topic, joinRef: joinRef, ref: leaveRef)))
      if case .joining = record.phase {
        effects += endJoin(topic, subscribers: subscribers, pushes: pushes, phase: leaving)
      } else {
        effects += setPhase(leaving, for: topic)
      }
      return effects + [
        .schedule(.leaveTimeout(topic: topic, ref: leaveRef), after: options.timeout)
      ]

    case .subscribed, .waitingForSocket, .refreshingToken, .joining, .waitingToRetry:
      // The server may not know the join, or the socket is gone, so `phx_close` may never
      // come: leave without waiting.
      logger.debug("Unsubscribing channel '\(topic)' without waiting for the server")
      if let joinRef = record.currentJoinRef {
        effects += sendLeave(topic, joinRef: joinRef)
      }
      return effects
        + endJoin(topic, subscribers: subscribers, pushes: pushes, phase: .unsubscribed)
        + done
    }
  }

  /// Rolls back the join in flight once no subscribe caller waits for it, as `unsubscribe`
  /// does: `phx_leave` goes out only for a join the server may hold. A rejoin the SDK started
  /// goes on. A leave has nothing to roll back: with no caller left, no join follows it.
  mutating func rollBackJoinWithoutCallers(_ topic: String) -> [Effect] {
    guard let record = channels[topic], record.subscribeWaiters.isEmpty,
      !record.isAutomaticRejoin
    else { return [] }
    switch record.phase {
    case .waitingForSocket, .refreshingToken, .joining, .waitingToRetry:
      logger.debug("Rolling back the join of channel '\(topic)': its last subscribe was cancelled")
      return leave(topic, waiter: nil, removing: false)
    case .unsubscribed, .subscribed, .leaving, .failed:
      return []
    }
  }

  mutating func leaveTimedOut(_ topic: String, ref: Ref) -> [Effect] {
    guard case .leaving(_, ref)? = channels[topic]?.phase else { return [] }
    logger.debug("Leave timed out for channel '\(topic)'")
    return leaveEnded(topic, pushes: .notSubscribed, cancelTimer: false)
  }

  /// Ends the leave in flight: its callers return, and the channel is unsubscribed. A
  /// subscribe that came during the leave then joins again. A removal finishes and drops the
  /// channel instead.
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
    if record.isRemoving {
      return effects + dropChannel(topic) + disconnectIfNoChannels()
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
  /// a join waiting for a token or to retry, and a subscribed channel wait for the next socket,
  /// which joins them once (see ``connectAttemptEnded()``), and a leave is over. A push waiting
  /// for a reply fails with ``RealtimeError/notConnected``.
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
      case .refreshingToken(let attempt):
        effects += failPendingPushes(topic, with: .notConnected)
        effects += waitForNextSocket(topic, attempt: attempt)
      case .subscribed:
        channels[topic]?.isAutomaticRejoin = true
        effects += failPendingPushes(topic, with: .notConnected)
        effects += waitForNextSocket(topic, attempt: 1)
      case .leaving:
        effects += leaveEnded(topic, pushes: .notConnected, cancelTimer: true)
      case .unsubscribed, .waitingForSocket, .failed:
        effects += failPendingPushes(topic, with: .notConnected)
      }
    }
    return effects
  }

  private mutating func waitForNextSocket(_ topic: String, attempt: Int) -> [Effect] {
    let timer = channels[topic]?.phase.timer(for: topic)
    channels[topic]?.timedOutJoinRef = nil
    channels[topic]?.hasRefreshedExpiredToken = false
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
        if record.isRemoving {
          effects += dropChannel(topic)
        }
      case .unsubscribed, .failed:
        effects += failPendingPushes(topic, with: .notConnected)
      }
    }
    return effects
  }

  // MARK: Helpers

  var isConnected: Bool {
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

  /// Ends the streams of `topic` and forgets its record.
  private mutating func dropChannel(_ topic: String) -> [Effect] {
    channels[topic] = nil
    return [.finishChannel(topic)]
  }

  /// Once no channel is left, disconnects at once when ``Options/disconnectOnEmptyChannelsAfter``
  /// is not positive, and schedules an idle disconnect otherwise.
  private mutating func disconnectIfNoChannels() -> [Effect] {
    guard channels.isEmpty else { return [] }
    if options.disconnectOnEmptyChannelsAfter <= .zero {
      return transitionConnection(.disconnectRequested(code: nil, reason: nil))
    }
    return transitionConnection(
      .lastChannelRemoved(disconnectAfter: options.disconnectOnEmptyChannelsAfter))
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
