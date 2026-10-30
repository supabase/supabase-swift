//
//  RealtimeCore+Leave.swift
//  Realtime
//

import Logging

extension RealtimeCore {
  // MARK: Unsubscribe

  /// Leaves the channel. A subscribed channel sends `phx_leave` and waits, bounded by the timeout,
  /// for the server's `phx_close`. Any other channel ends its join at once.
  mutating func unsubscribe(_ channel: ChannelID, waiter: WaiterID) -> [Effect] {
    leave(channel, waiter: waiter, removing: false)
  }

  /// Removes the channel: like ``unsubscribe(_:waiter:)``, but a subscribe in flight and the
  /// pushes waiting for a reply fail with ``RealtimeError/channelRemoved``, and a join in
  /// flight on a connected socket leaves too. The channel is then finished and dropped, once
  /// the leave ends or at once when no leave is in flight.
  mutating func removeChannel(_ channel: ChannelID, waiter: WaiterID) -> [Effect] {
    guard channels[channel] != nil else {
      return [.resume(waiter, .success)] + disconnectIfNoChannels()
    }
    channels[channel]?.isRemoving = true
    var effects = failPendingPushes(channel, with: .channelRemoved)
    effects += leave(channel, waiter: waiter, removing: true)
    guard case .leaving? = channels[channel]?.phase else {
      return effects + dropChannel(channel) + disconnectIfNoChannels()
    }
    return effects
  }

  /// Leaves the channel for `waiter`, or for no caller when a join rolls back.
  private mutating func leave(_ channel: ChannelID, waiter: WaiterID?, removing: Bool) -> [Effect] {
    let done: [Effect] = waiter.map { [.resume($0, .success)] } ?? []
    guard var record = channels[channel] else { return done }
    let subscribers: WaiterOutcome = removing ? .failure(.channelRemoved) : .cancelled
    let pushes: RealtimeError = removing ? .channelRemoved : .notSubscribed
    // A later subscribe is a new subscription, not a rejoin.
    record.hasBeenSubscribed = false
    record.isAutomaticRejoin = false
    let cleared = record.presence.clear()
    channels[channel] = record
    var effects: [Effect] =
      cleared.isEmpty ? [] : [.deliver(channel, .presence(cleared, record.presence.state))]

    switch record.phase {
    case .unsubscribed:
      logger.debug("Unsubscribe no-op for channel '\(topic(of: channel))': already unsubscribed")
      return effects + done

    case .failed:
      return effects + setPhase(.unsubscribed, for: channel) + done

    case .leaving:
      // This caller wants the channel to stay unsubscribed.
      if let waiter { channels[channel]?.leaveWaiters.append(waiter) }
      channels[channel]?.subscribeWaiters = []
      return effects + record.subscribeWaiters.map { .resume($0, subscribers) }

    case .subscribed(let joinRef) where isConnected,
      .joining(let joinRef, _, _) where isConnected && removing:
      // A join in flight leaves only for `removeChannel`: the server has the join, so it
      // answers the leave, and the channel must not outlive it.
      let leaveRef = makeRef()
      let leaving = ChannelRecord.Phase.leaving(joinRef: joinRef, leaveRef: leaveRef)
      if let waiter { channels[channel]?.leaveWaiters.append(waiter) }
      logger.debug(
        "Leaving channel '\(topic(of: channel))' (join_ref: \(joinRef), ref: \(leaveRef))")
      effects.append(.send(leaveMessage(record.topic, joinRef: joinRef, ref: leaveRef)))
      if case .joining = record.phase {
        effects += endJoin(channel, subscribers: subscribers, pushes: pushes, phase: leaving)
      } else {
        effects += setPhase(leaving, for: channel)
      }
      return effects + [
        .schedule(.leaveTimeout(channel: channel, ref: leaveRef), after: options.timeout)
      ]

    case .subscribed, .waitingForSocket, .refreshingToken, .joining, .waitingToRetry:
      // The server may not know the join, or the socket is gone, so `phx_close` may never
      // come: leave without waiting.
      logger.debug("Unsubscribing channel '\(topic(of: channel))' without waiting for the server")
      if let joinRef = record.currentJoinRef {
        effects += sendLeave(channel, joinRef: joinRef)
      }
      return effects
        + endJoin(channel, subscribers: subscribers, pushes: pushes, phase: .unsubscribed)
        + done
    }
  }

  /// Rolls back the join in flight once no subscribe caller waits for it, as `unsubscribe`
  /// does: `phx_leave` goes out only for a join the server may hold. A rejoin the SDK started
  /// goes on. A leave has nothing to roll back: with no caller left, no join follows it.
  mutating func rollBackJoinWithoutCallers(_ channel: ChannelID) -> [Effect] {
    guard let record = channels[channel], record.subscribeWaiters.isEmpty,
      !record.isAutomaticRejoin
    else { return [] }
    switch record.phase {
    case .waitingForSocket, .refreshingToken, .joining, .waitingToRetry:
      logger.debug(
        "Rolling back the join of channel '\(topic(of: channel))': its last subscribe was cancelled"
      )
      return leave(channel, waiter: nil, removing: false)
    case .unsubscribed, .subscribed, .leaving, .failed:
      return []
    }
  }

  mutating func leaveTimedOut(_ channel: ChannelID, ref: Ref) -> [Effect] {
    guard case .leaving(_, ref)? = channels[channel]?.phase else { return [] }
    logger.debug("Leave timed out for channel '\(topic(of: channel))'")
    return leaveEnded(channel, pushes: .notSubscribed, cancelTimer: false)
  }

  /// Ends the leave in flight: its callers return, and the channel is unsubscribed. A
  /// subscribe that came during the leave then joins again. A removal finishes and drops the
  /// channel instead.
  private mutating func leaveEnded(
    _ channel: ChannelID, pushes: RealtimeError, cancelTimer: Bool
  ) -> [Effect] {
    guard var record = channels[channel], case .leaving(_, let leaveRef) = record.phase else {
      return []
    }
    let waiters = record.leaveWaiters
    record.leaveWaiters = []
    channels[channel] = record

    var effects: [Effect] = waiters.map { .resume($0, .success) }
    effects += failPendingPushes(channel, with: pushes)
    effects += setPhase(.unsubscribed, for: channel)
    if cancelTimer {
      effects.append(.cancel(.leaveTimeout(channel: channel, ref: leaveRef)))
    }
    if record.isRemoving {
      return effects + dropChannel(channel) + disconnectIfNoChannels()
    }
    if !record.subscribeWaiters.isEmpty {
      effects += sendJoin(channel, attempt: 1)
    }
    return effects
  }

  /// Sends `phx_leave` for the join `joinRef` on a connected socket.
  mutating func sendLeave(_ channel: ChannelID, joinRef: Ref) -> [Effect] {
    guard isConnected, let topic = channels[channel]?.topic else { return [] }
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
  /// `client.remove(self)`. The message goes to the channel its `join_ref` names, or to the live
  /// channel of its topic when it has none. Either message for an older join matches no channel
  /// and is dropped.
  mutating func receiveClose(_ message: RealtimeMessage) -> [Effect] {
    guard let channel = routedChannel(message, joinRef: message.joinRef),
      let record = channels[channel]
    else { return [] }
    logger.debug("Server closed channel '\(topic(of: channel))' (\(message.event))")

    var effects: [Effect]
    switch record.phase {
    case .leaving:
      // The answer to `phx_leave`: the channel stays, so it can subscribe again.
      return leaveEnded(channel, pushes: .channelClosedByServer, cancelTimer: true)
    case .waitingForSocket, .refreshingToken, .joining, .waitingToRetry:
      effects = endJoin(
        channel, subscribers: .failure(.channelClosedByServer), pushes: .channelClosedByServer,
        phase: .failed(.channelClosedByServer))
    case .subscribed, .failed:
      effects = endJoin(
        channel, subscribers: .cancelled, pushes: .channelClosedByServer, phase: .unsubscribed)
    case .unsubscribed:
      effects = []
    }

    guard message.event == ChannelEvent.close else { return effects }
    channels[channel] = nil
    return effects + [.finishChannel(channel)]
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
    for channel in channels.keys.sorted() {
      guard let record = channels[channel], case .waitingForSocket = record.phase,
        !record.subscribeWaiters.isEmpty
      else { continue }
      effects += failSubscribe(channel, with: error)
    }
    return effects
  }

  /// Moves the channels on once the socket went away without `disconnect()`: a join in flight,
  /// a join waiting for a token or to retry, and a subscribed channel wait for the next socket,
  /// which joins them once (see ``connectAttemptEnded()``), and a leave is over. A push waiting
  /// for a reply fails with ``RealtimeError/notConnected``.
  private mutating func channelsLostSocket() -> [Effect] {
    var effects: [Effect] = []
    for channel in channels.keys.sorted() {
      guard let phase = channels[channel]?.phase else { continue }
      switch phase {
      case .joining(_, let attempt, _):
        effects += failPendingPushes(channel, with: .notConnected)
        effects += waitForNextSocket(channel, attempt: attempt)
      case .waitingToRetry(let attempt, _, _):
        effects += failPendingPushes(channel, with: .notConnected)
        effects += waitForNextSocket(channel, attempt: attempt + 1)
      case .refreshingToken(let attempt):
        effects += failPendingPushes(channel, with: .notConnected)
        effects += waitForNextSocket(channel, attempt: attempt)
      case .subscribed:
        channels[channel]?.isAutomaticRejoin = true
        effects += failPendingPushes(channel, with: .notConnected)
        effects += waitForNextSocket(channel, attempt: 1)
      case .leaving:
        effects += leaveEnded(channel, pushes: .notConnected, cancelTimer: true)
      case .unsubscribed, .waitingForSocket, .failed:
        effects += failPendingPushes(channel, with: .notConnected)
      }
    }
    return effects
  }

  private mutating func waitForNextSocket(_ channel: ChannelID, attempt: Int) -> [Effect] {
    let timer = channels[channel]?.phase.timer(for: channel)
    channels[channel]?.timedOutJoinRef = nil
    channels[channel]?.hasRefreshedExpiredToken = false
    return setPhase(.waitingForSocket(attempt: attempt), for: channel)
      + (timer.map { [.cancel($0)] } ?? [])
  }

  /// Ends every join after `disconnect()`. A subscribe in flight fails with
  /// ``RealtimeError/disconnectedWhileSubscribing`` instead of connecting again, a leave is
  /// over, and a push waiting for a reply fails with ``RealtimeError/notConnected``.
  mutating func disconnectChannels() -> [Effect] {
    var effects: [Effect] = []
    for channel in channels.keys.sorted() {
      guard var record = channels[channel] else { continue }
      switch record.phase {
      case .waitingForSocket, .refreshingToken, .joining, .waitingToRetry, .subscribed, .leaving:
        let leavers = record.leaveWaiters
        record.leaveWaiters = []
        channels[channel] = record
        effects += leavers.map { .resume($0, .success) }
        effects += endJoin(
          channel, subscribers: .failure(.disconnectedWhileSubscribing), pushes: .notConnected,
          phase: .unsubscribed)
        if record.isRemoving {
          effects += dropChannel(channel)
        }
      case .unsubscribed, .failed:
        effects += failPendingPushes(channel, with: .notConnected)
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
    _ channel: ChannelID, subscribers: WaiterOutcome, pushes: RealtimeError,
    phase: ChannelRecord.Phase
  ) -> [Effect] {
    guard var record = channels[channel] else { return [] }
    let timer = record.phase.timer(for: channel)
    let waiters = record.subscribeWaiters
    record.subscribeWaiters = []
    record.timedOutJoinRef = nil
    channels[channel] = record

    var effects: [Effect] = waiters.map { .resume($0, subscribers) }
    effects += failPendingPushes(channel, with: pushes)
    effects += setPhase(phase, for: channel)
    if let timer {
      effects.append(.cancel(timer))
    }
    return effects
  }

  /// Ends the streams of `channel` and forgets its record.
  private mutating func dropChannel(_ channel: ChannelID) -> [Effect] {
    channels[channel] = nil
    return [.finishChannel(channel)]
  }

  /// Once no channel is left, disconnects at once when ``Options/disconnectOnEmptyChannelsAfter``
  /// is not positive, and schedules an idle disconnect otherwise. A channel the client still
  /// registers counts, even without a record.
  private mutating func disconnectIfNoChannels() -> [Effect] {
    guard channels.isEmpty, !options.hasRegisteredChannels() else { return [] }
    if options.disconnectOnEmptyChannelsAfter <= .zero {
      return transitionConnection(.disconnectRequested(code: nil, reason: nil))
    }
    return transitionConnection(
      .lastChannelRemoved(disconnectAfter: options.disconnectOnEmptyChannelsAfter))
  }
}

extension ChannelRecord.Phase {
  /// The timer this phase of `channel` waits on, if any.
  fileprivate func timer(for channel: ChannelID) -> TimerID? {
    switch self {
    case .joining(let ref, _, .reply):
      .joinTimeout(channel: channel, ref: ref)
    case .joining(let ref, _, .postgres):
      .postgresTimeout(channel: channel, ref: ref)
    case .waitingToRetry:
      .rejoin(channel: channel)
    case .leaving(_, let leaveRef):
      .leaveTimeout(channel: channel, ref: leaveRef)
    case .unsubscribed, .waitingForSocket, .refreshingToken, .subscribed, .failed:
      nil
    }
  }
}
