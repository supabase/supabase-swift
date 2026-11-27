//
//  RealtimeCore+Subscribe.swift
//  Realtime
//

import Foundation
import Helpers
import IssueReporting
import Logging

extension RealtimeCore {
  mutating func subscribe(
    channel: ChannelID, topic: String, configuration: RealtimeChannelConfiguration,
    waiter: WaiterID, snapshot: JoinSnapshot
  ) -> [Effect] {
    if channels[channel]?.isRemoving == true {
      return [.resume(waiter, .failure(.channelRemoved))]
    }
    var effects: [Effect] = []
    if idleDisconnectPending {
      idleDisconnectPending = false
      effects.append(.cancel(.idleDisconnect))
    }

    var record = channels[channel] ?? ChannelRecord(topic: topic, configuration: configuration)
    record.snapshot.bindings = snapshot.bindings
    switch record.phase {
    case .unsubscribed, .failed, .leaving:
      // A new subscription: its joins carry the presence flag of this call, as later rejoins do.
      record.snapshot.presenceEnabled = snapshot.presenceEnabled
    case .subscribed, .waitingForSocket, .refreshingToken, .joining, .waitingToRetry:
      break
    }
    switch record.phase {
    case .subscribed:
      logger.debug("Subscribe no-op for channel '\(topic)': already subscribed")
      channels.setRecord(record, for: channel)
      return effects + [.resume(waiter, .success)]

    case .unsubscribed, .failed:
      logger.debug("Subscribe requested for channel '\(topic)'")
      record.subscribeWaiters.append(waiter)
      record.hasRefreshedExpiredToken = false
      record.isAutomaticRejoin = false
      channels.setRecord(record, for: channel)
      return effects + sendJoin(channel, attempt: 1)

    case .waitingForSocket where isStopped:
      // After `disconnect()` or a 4000–4999 close, no socket comes until a `connect()`.
      guard options.connectsOnSubscribe else {
        channels.setRecord(record, for: channel)
        return effects + [.resume(waiter, .failure(.notConnectedToSubscribe))]
      }
      record.subscribeWaiters.append(waiter)
      channels.setRecord(record, for: channel)
      return effects + transitionConnection(.connect(waiter: nil))

    case .waitingForSocket, .refreshingToken, .joining, .waitingToRetry, .leaving:
      // The attempt in flight, or the join after the leave, answers this caller too.
      record.subscribeWaiters.append(waiter)
      channels.setRecord(record, for: channel)
      return effects
    }
  }

  /// Starts join attempt `attempt` for `channel`: sends `phx_join` on a connected socket, and
  /// waits for the socket otherwise. With an `accessToken` callback, the join first waits for a
  /// call in flight, or for a new call unless the last one is recent.
  mutating func sendJoin(_ channel: ChannelID, attempt: Int) -> [Effect] {
    guard case .connected = connection else {
      return waitForSocket(channel, attempt: attempt)
    }
    let fetch = refreshAccessToken(ignoringInterval: false)
    guard tokenFetchInFlight else {
      return pushJoin(channel, attempt: attempt)
    }
    return waitForToken(channel, attempt: attempt) + fetch
  }

  /// Writes the `phx_join` for attempt `attempt`, with the current token, and starts its timeout.
  mutating func pushJoin(_ channel: ChannelID, attempt: Int) -> [Effect] {
    guard var record = channels[channel] else { return [] }
    let ref = makeRef()
    record.timedOutJoinRef = nil
    let config = RealtimeJoinConfig(
      record.configuration, bindings: record.snapshot.bindings,
      presenceEnabled: record.joinsWithPresence)
    record.joinedBindings = config.postgresChanges
    record.hasTrackedSinceJoin = false
    record.pendingTracks = []
    record.sentAccessToken = tokens.token
    record.awaitsReplication = config.broadcast.replicationReady
    record.shutdownError = nil
    // A new join waits for its own first presence state.
    record.presence.waitForNextState()
    channels.setRecord(record, for: channel)
    logger.debug(
      "Sending phx_join for channel '\(topic(of: channel))' (ref: \(ref), attempt: \(attempt))")

    var effects = setPhase(.joining(ref: ref, attempt: attempt), for: channel)
    let payload = RealtimeJoinPayload(
      config: config, accessToken: record.sentAccessToken, version: options.version)
    if let encoded = try? JSONObject(payload) {
      effects.append(
        .send(
          RealtimeMessage(
            joinRef: ref, ref: ref, topic: record.wireTopic,
            event: ChannelEvent.join, payload: encoded)))
    } else {
      reportIssue(
        "Failed to encode the phx_join payload for channel '\(topic(of: channel))'. Skipping join.")
    }
    effects.append(
      .schedule(
        .joinTimeout(channel: channel, ref: ref), after: options.timeout + config.extraJoinTimeout))
    return effects
  }

  /// Parks join attempt `attempt` until the socket opens. Connects first when
  /// `connectsOnSubscribe` allows it.
  private mutating func waitForSocket(_ channel: ChannelID, attempt: Int) -> [Effect] {
    // The next join on the new socket replaces the join that timed out.
    channels.update(channel) { $0.timedOutJoinRef = nil }
    switch connection {
    case .disconnected where !options.connectsOnSubscribe:
      return failSubscribe(channel, with: .notConnectedToSubscribe)
    case .disconnected, .reconnecting:
      let effects = setPhase(.waitingForSocket(attempt: attempt), for: channel)
      guard options.connectsOnSubscribe else { return effects }
      return effects + transitionConnection(.connect(waiter: nil))
    case .connecting, .connected:
      return setPhase(.waitingForSocket(attempt: attempt), for: channel)
    }
  }

  /// Moves on the channels that wait for the socket once a connect attempt ends. They join on
  /// an open socket. When the client gives up, a refused connect fails them, and any other
  /// failure makes them wait and try again.
  mutating func connectAttemptEnded() -> [Effect] {
    var effects: [Effect] = []
    for channel in channels.ids.sorted() {
      guard case .waitingForSocket(let attempt)? = channels[channel]?.phase else { continue }
      switch connection {
      case .connected:
        effects += sendJoin(channel, attempt: attempt)
      case .disconnected(let error?) where !error.isRetryable:
        effects += failSubscribe(channel, with: error)
      case .disconnected(.some):
        effects += waitToRejoin(
          channel, attempt: attempt, delay: options.rejoinDelay(attempt), lastError: .notConnected)
      case .disconnected(nil), .connecting, .reconnecting:
        break
      }
    }
    return effects
  }

  /// Applies a reply to the join in flight, or a late `ok` to the join that timed out, on the
  /// channel of that join. Any other frame is left alone.
  mutating func receiveJoinReply(_ message: RealtimeMessage) -> [Effect] {
    guard message.event == ChannelEvent.reply,
      let channel = routedChannel(message, joinRef: message.joinRef ?? message.ref),
      let ref = message.ref,
      let record = channels[channel]
    else { return [] }

    switch record.phase {
    case .joining(ref, let attempt):
      return receiveReply(message, toJoin: ref, attempt: attempt, on: channel)
    case .waitingToRetry(let attempt, _, _)
    where record.timedOutJoinRef == ref && message.status == .ok:
      logger.debug("Late join reply for channel '\(topic(of: channel))' during the rejoin backoff")
      return joinAccepted(message, ref: ref, attempt: attempt, on: channel)
        + [.cancel(.rejoin(channel: channel))]
    case .subscribed(ref) where message.status == .ok:
      // A `system` message confirmed the join before its reply.
      if let changes = try? serverChanges(in: message) {
        channels.update(channel) { $0.serverChanges = changes }
      }
      return []
    default:
      return []
    }
  }

  private mutating func receiveReply(
    _ message: RealtimeMessage, toJoin ref: Ref, attempt: Int, on channel: ChannelID
  ) -> [Effect] {
    let effects: [Effect]
    if message.status == .ok {
      effects = joinAccepted(message, ref: ref, attempt: attempt, on: channel)
    } else if message.status == .error {
      let reason = message.replyReason(default: "The server rejected the join.")
      logger.debug("Server refused the join for channel '\(topic(of: channel))' (ref: \(ref))")
      effects = joinAttemptFailed(channel, attempt: attempt, error: .joinError(reason: reason))
    } else {
      return []
    }
    return effects + [.cancel(.joinTimeout(channel: channel, ref: ref))]
  }

  /// Applies an `ok` to the join `ref`: keeps the bindings the server echoed, then confirms the
  /// join.
  ///
  /// The `ok` confirms the join, as in realtime-js. Without
  /// ``RealtimeChannelConfiguration/PostgresChanges/waitsForSubscription``, the server then sets
  /// up the Postgres changes and reports the result in a `system` message.
  private mutating func joinAccepted(
    _ message: RealtimeMessage, ref: Ref, attempt: Int, on channel: ChannelID
  ) -> [Effect] {
    do {
      if let changes = try serverChanges(in: message) {
        channels.update(channel) { $0.serverChanges = changes }
      }
    } catch {
      return joinAttemptFailed(channel, attempt: attempt, error: .unreadableJoinReply(error))
    }
    return confirmJoin(channel, ref: ref)
  }

  /// The bindings the server echoed in a join reply, with their ids, or `nil` when it echoed
  /// none. An entry that does not decode is skipped; a reply whose list is not a list throws.
  private func serverChanges(in message: RealtimeMessage) throws -> [ServerPostgresBinding]? {
    guard
      let entries = try message.payload["response"]?.objectValue?[ChannelEvent.postgresChanges]?
        .decode(as: [ServerPostgresBinding.Lossy].self)
    else { return nil }
    let bindings = entries.compactMap(\.binding)
    if bindings.count < entries.count {
      logger.warning(
        "Skipped \(entries.count - bindings.count) unreadable Postgres bindings in a join reply")
    }
    return bindings
  }

  /// Applies a `system` message: the server's report on the join's Postgres changes or on
  /// replication. An `ok` confirms a join whose reply has not come yet. A Postgres changes error
  /// leaves the channel as it is: the server may set up the Postgres changes on a later try.
  ///
  /// The server sends a `system` extension error right before it stops the channel, for example
  /// on the tenant's events-per-second limit (`shutdown_response/2` in Realtime's
  /// `realtime_channel.ex`). The channel keeps the reason for the `phx_close` that follows. It is
  /// a replication failure only while a join that asked for the replication report waits for it.
  ///
  /// The message goes to the channel its `join_ref` names, or to the live channel of its topic
  /// when it has none.
  mutating func receiveSystem(_ message: RealtimeMessage) -> [Effect] {
    guard let channel = routedChannel(message, joinRef: message.joinRef),
      let record = channels[channel]
    else { return [] }
    let `extension` = message.payload["extension"]?.stringValue
    let isPostgresChanges = `extension` == ChannelEvent.postgresChanges
    let isReplication = `extension` == ChannelEvent.system
    let isForCurrentJoin = message.joinRef == nil || message.joinRef == record.currentJoinRef
    let reason = message.payload["message"]?.stringValue ?? "\(message.payload)"

    switch message.status {
    case .ok where isForCurrentJoin:
      // Before the confirmation: it may start a join for new bindings, which waits anew.
      if isReplication {
        channels.update(channel) { $0.awaitsReplication = false }
      }
      var effects = confirmJoinBySystem(channel)
      if isPostgresChanges {
        effects.append(.deliver(channel, .event(.postgresChangesReady)))
      } else if isReplication {
        effects.append(.deliver(channel, .event(.replicationReady)))
      }
      return effects

    case .error where isPostgresChanges:
      // The join stands, so broadcast and presence keep working.
      logger.error("Channel '\(topic(of: channel))' reported an error")
      return [.deliver(channel, .event(.postgresChangesFailed(reason)))]

    case .error where isReplication && isForCurrentJoin && record.currentJoinRef != nil:
      // A message without `join_ref` counts only while the channel has a join.
      logger.error("Server is shutting down channel '\(topic(of: channel))'")
      channels.update(channel) {
        $0.shutdownError = .channelClosed(reason: reason)
        $0.awaitsReplication = false
      }
      return record.awaitsReplication
        ? [.deliver(channel, .event(.replicationFailed(reason)))] : []

    default:
      return []
    }
  }

  /// Confirms the current join on a `system` ok, which may come before the join reply, and
  /// stops the join's timer.
  private mutating func confirmJoinBySystem(_ channel: ChannelID) -> [Effect] {
    guard let record = channels[channel], let ref = record.currentJoinRef,
      let timer = record.phase.timer(for: channel)
    else { return [] }
    return confirmJoin(channel, ref: ref) + [.cancel(timer)]
  }

  mutating func bindingsChanged(_ channel: ChannelID, bindings: [PostgresJoinConfig]) -> [Effect] {
    guard channels[channel] != nil else { return [] }
    channels.update(channel) { $0.snapshot.bindings = bindings }
    return rejoinIfBindingsChanged(channel)
  }

  /// Rejoins a subscribed channel when it has a binding its join did not carry, so the server
  /// sends those changes too. A removed binding never rejoins.
  ///
  /// The channel leaves the old join and joins again with every binding. It stays
  /// ``RealtimeChannelStatus/subscribing(attempt:)`` until the new join is confirmed.
  private mutating func rejoinIfBindingsChanged(_ channel: ChannelID) -> [Effect] {
    guard let record = channels[channel], case .subscribed(let joinRef) = record.phase,
      case .connected = connection
    else { return [] }
    let joined = Set(record.joinedBindings.map(BindingKey.init))
    guard record.snapshot.bindings.contains(where: { !joined.contains(BindingKey($0)) }) else {
      return []
    }
    logger.debug("Rejoining channel '\(topic(of: channel))' to add Postgres changes bindings")
    channels.update(channel) { $0.isAutomaticRejoin = true }
    return sendLeave(channel, joinRef: joinRef) + sendJoin(channel, attempt: 1)
  }

  mutating func joinTimedOut(_ channel: ChannelID, ref: Ref) -> [Effect] {
    guard case .joining(ref, let attempt)? = channels[channel]?.phase else { return [] }
    logger.debug("Subscribe attempt \(attempt) timed out for channel '\(topic(of: channel))'")
    channels.update(channel) { $0.timedOutJoinRef = ref }
    return waitToRejoin(
      channel, attempt: attempt, delay: options.rejoinDelay(attempt), lastError: .joinTimeout)
  }

  mutating func rejoinTimerFired(_ channel: ChannelID) -> [Effect] {
    guard case .waitingToRetry(let attempt, _, _)? = channels[channel]?.phase else { return [] }
    return sendJoin(channel, attempt: attempt + 1)
  }

  private mutating func confirmJoin(_ channel: ChannelID, ref: Ref) -> [Effect] {
    guard var record = channels[channel] else { return [] }
    logger.debug("Server confirmed subscribe for channel '\(topic(of: channel))'")
    let waiters = record.subscribeWaiters
    let isRejoin = record.hasBeenSubscribed
    record.subscribeWaiters = []
    record.hasBeenSubscribed = true
    record.timedOutJoinRef = nil
    record.hasRefreshedExpiredToken = false
    channels.setRecord(record, for: channel)

    var effects: [Effect] = waiters.map { .resume($0, .success) }
    effects += setPhase(.subscribed(joinRef: ref), for: channel)
    if isRejoin {
      effects.append(.deliver(channel, .event(.resubscribed)))
    }
    // A binding added while the join was in flight is not in it yet.
    return effects + rejoinIfBindingsChanged(channel)
  }

  /// Decides what follows a join the server refused: wait and rejoin, or fail the subscribe.
  mutating func joinAttemptFailed(
    _ channel: ChannelID, attempt: Int, error: RealtimeError
  ) -> [Effect] {
    switch error.joinRecovery {
    case .refreshToken where channels[channel]?.hasRefreshedExpiredToken == false:
      logger.debug("Token expired for channel '\(topic(of: channel))', rejoining with a fresh one")
      return rejoinWithFreshToken(channel, attempt: attempt + 1)
    case .fail, .refreshToken:
      logger.error(
        "Failed to subscribe to channel '\(topic(of: channel))': \(LogRedaction.summary(of: error))"
      )
      return failSubscribe(channel, with: error)
    case .backOff:
      return waitToRejoin(
        channel, attempt: attempt, delay: RealtimeChannel.rateLimitBackoff, lastError: error)
    case .retry:
      return waitToRejoin(
        channel, attempt: attempt, delay: options.rejoinDelay(attempt), lastError: error)
    }
  }

  private mutating func waitToRejoin(
    _ channel: ChannelID, attempt: Int, delay: Duration, lastError: RealtimeError
  ) -> [Effect] {
    logger.debug("Retrying subscribe for '\(topic(of: channel))' in \(delay)")
    // Another failure ends the run of expired-token errors.
    channels.update(channel) { $0.hasRefreshedExpiredToken = false }
    return setPhase(
      .waitingToRetry(attempt: attempt, retryIn: delay, lastError: lastError), for: channel)
      + [.schedule(.rejoin(channel: channel), after: delay)]
  }

  /// Ends the subscribe for good: every caller waiting for it fails with `error`, and every
  /// push waiting for a reply fails with ``RealtimeError/notSubscribed``.
  mutating func failSubscribe(_ channel: ChannelID, with error: RealtimeError) -> [Effect] {
    guard let waiters = channels[channel]?.subscribeWaiters else { return [] }
    channels.update(channel) {
      $0.subscribeWaiters = []
      $0.timedOutJoinRef = nil
    }
    return waiters.map { .resume($0, .failure(error)) }
      + failPendingPushes(channel, with: .notSubscribed)
      + setPhase(.failed(error), for: channel)
  }

  /// Moves `channel` to `phase`, and publishes its status when the status changed.
  mutating func setPhase(_ phase: ChannelRecord.Phase, for channel: ChannelID) -> [Effect] {
    guard let previous = channels[channel]?.phase else { return [] }
    channels.update(channel) { $0.phase = phase }
    logger.debug(
      "Channel '\(topic(of: channel))': \(caseName(of: previous)) → \(caseName(of: phase))")
    guard !phase.status.isSame(as: previous.status) else { return [] }
    return [.publishChannelStatus(channel, phase.status)]
  }
}
