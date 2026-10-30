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
    topic: String, configuration: RealtimeChannelConfiguration, waiter: WaiterID,
    snapshot: JoinSnapshot
  ) -> [Effect] {
    if channels[topic]?.isRemoving == true {
      return [.resume(waiter, .failure(.channelRemoved))]
    }
    var effects: [Effect] = []
    if idleDisconnectPending {
      idleDisconnectPending = false
      effects.append(.cancelIdleDisconnect)
    }

    var record = channels[topic] ?? ChannelRecord(configuration: configuration)
    record.bindings = snapshot.bindings
    record.presenceEnabled = snapshot.presenceEnabled
    switch record.phase {
    case .subscribed:
      logger.debug("Subscribe no-op for channel '\(topic)': already subscribed")
      channels[topic] = record
      return effects + [.resume(waiter, .success)]

    case .unsubscribed, .failed:
      logger.debug("Subscribe requested for channel '\(topic)'")
      record.subscribeWaiters.append(waiter)
      record.hasRefreshedExpiredToken = false
      record.isAutomaticRejoin = false
      channels[topic] = record
      return effects + sendJoin(topic, attempt: 1)

    case .waitingForSocket, .refreshingToken, .joining, .waitingToRetry, .leaving:
      // The attempt in flight, or the join after the leave, answers this caller too.
      record.subscribeWaiters.append(waiter)
      channels[topic] = record
      return effects
    }
  }

  /// Starts join attempt `attempt` for `topic`: sends `phx_join` on a connected socket, and
  /// waits for the socket otherwise. With an `accessToken` callback, the join first waits for a
  /// call in flight, or for a new call unless the last one is recent.
  mutating func sendJoin(_ topic: String, attempt: Int) -> [Effect] {
    guard case .connected = connection else {
      return waitForSocket(topic, attempt: attempt)
    }
    let fetch = refreshAccessToken(ignoringInterval: false)
    guard tokenFetchInFlight else {
      return pushJoin(topic, attempt: attempt)
    }
    return waitForToken(topic, attempt: attempt) + fetch
  }

  /// Writes the `phx_join` for attempt `attempt`, with the current token, and starts its timeout.
  mutating func pushJoin(_ topic: String, attempt: Int) -> [Effect] {
    guard var record = channels[topic] else { return [] }
    let ref = makeRef()
    record.timedOutJoinRef = nil
    let config = RealtimeJoinConfig(
      record.configuration, bindings: record.bindings, presenceEnabled: record.presenceEnabled)
    record.joinedBindings = config.postgresChanges
    record.joinAccessToken = tokens.token
    // A new join waits for its own first presence state.
    record.presence.waitForNextState()
    channels[topic] = record
    logger.debug("Sending phx_join for channel '\(topic)' (ref: \(ref), attempt: \(attempt))")

    var effects = setPhase(.joining(ref: ref, attempt: attempt, stage: .reply), for: topic)
    let payload = RealtimeJoinPayload(
      config: config, accessToken: record.joinAccessToken, version: options.version)
    if let encoded = try? JSONObject(payload) {
      effects.append(
        .send(
          RealtimeMessage(
            joinRef: ref, ref: ref, topic: RealtimeChannel.wireTopic(for: topic),
            event: ChannelEvent.join, payload: encoded)))
    } else {
      reportIssue("Failed to encode the phx_join payload for channel '\(topic)'. Skipping join.")
    }
    effects.append(
      .schedule(
        .joinTimeout(topic: topic, ref: ref), after: options.timeout + config.extraJoinTimeout))
    return effects
  }

  /// Parks join attempt `attempt` until the socket opens. Connects first when
  /// `connectOnSubscribe` allows it.
  private mutating func waitForSocket(_ topic: String, attempt: Int) -> [Effect] {
    // The next join on the new socket replaces the join that timed out.
    channels[topic]?.timedOutJoinRef = nil
    switch connection {
    case .disconnected where !options.connectOnSubscribe:
      return failSubscribe(topic, with: .notConnectedToSubscribe)
    case .disconnected, .reconnecting:
      let effects = setPhase(.waitingForSocket(attempt: attempt), for: topic)
      guard options.connectOnSubscribe else { return effects }
      return effects + transitionConnection(.connect(waiter: nil))
    case .connecting, .connected:
      return setPhase(.waitingForSocket(attempt: attempt), for: topic)
    }
  }

  /// Moves on the channels that wait for the socket once a connect attempt ends. They join on
  /// an open socket. When the client gives up, a refused connect fails them, and any other
  /// failure makes them wait and try again.
  mutating func connectAttemptEnded() -> [Effect] {
    var effects: [Effect] = []
    for topic in channels.keys.sorted() {
      guard case .waitingForSocket(let attempt)? = channels[topic]?.phase else { continue }
      switch connection {
      case .connected:
        effects += sendJoin(topic, attempt: attempt)
      case .disconnected(let error?) where !error.isRetryable:
        effects += failSubscribe(topic, with: error)
      case .disconnected(.some):
        effects += waitToRejoin(
          topic, attempt: attempt, delay: options.rejoinDelay(attempt), lastError: .notConnected)
      case .disconnected(nil), .connecting, .reconnecting:
        break
      }
    }
    return effects
  }

  /// Applies a reply to the join in flight, or a late `ok` to the join that timed out. Any
  /// other frame is left alone.
  mutating func receiveJoinReply(_ message: RealtimeMessage) -> [Effect] {
    guard message.event == ChannelEvent.reply,
      let topic = RealtimeChannel.topic(forWireTopic: message.topic),
      let ref = message.ref,
      let record = channels[topic]
    else { return [] }

    switch record.phase {
    case .joining(ref, let attempt, .reply):
      return receiveReply(message, toJoin: ref, attempt: attempt, on: topic)
    case .waitingToRetry(let attempt, _, _)
    where record.timedOutJoinRef == ref && message.status == .ok:
      logger.debug("Late join reply for channel '\(topic)' during the rejoin backoff")
      return joinAccepted(message, ref: ref, attempt: attempt, on: topic)
        + [.cancel(.rejoin(topic: topic))]
    case .subscribed(ref) where message.status == .ok:
      // A `system` message confirmed the join before its reply.
      if let changes = try? serverChanges(in: message) {
        channels[topic]?.serverChanges = changes
      }
      return []
    default:
      return []
    }
  }

  private mutating func receiveReply(
    _ message: RealtimeMessage, toJoin ref: Ref, attempt: Int, on topic: String
  ) -> [Effect] {
    let effects: [Effect]
    if message.status == .ok {
      effects = joinAccepted(message, ref: ref, attempt: attempt, on: topic)
    } else if message.status == .error {
      let response = message.payload["response"]
      let reason =
        response?.objectValue?["reason"]?.stringValue
        ?? response?.stringValue
        ?? "The server rejected the join."
      logger.debug("Server refused the join for channel '\(topic)' (ref: \(ref)): \(reason)")
      effects = joinAttemptFailed(topic, attempt: attempt, error: .joinError(reason: reason))
    } else {
      return []
    }
    return effects + [.cancel(.joinTimeout(topic: topic, ref: ref))]
  }

  /// Applies an `ok` to the join `ref`: keeps the bindings the server echoed, then confirms the
  /// join or waits for its Postgres changes.
  private mutating func joinAccepted(
    _ message: RealtimeMessage, ref: Ref, attempt: Int, on topic: String
  ) -> [Effect] {
    do {
      if let changes = try serverChanges(in: message) {
        channels[topic]?.serverChanges = changes
      }
    } catch {
      return joinAttemptFailed(topic, attempt: attempt, error: .unreadableJoinReply(error))
    }
    guard let record = channels[topic], record.joinWaitsForPostgresChanges else {
      return confirmJoin(topic, ref: ref)
    }
    logger.debug("Channel '\(topic)' waits for its Postgres changes (ref: \(ref))")
    channels[topic]?.timedOutJoinRef = nil
    return setPhase(.joining(ref: ref, attempt: attempt, stage: .postgres), for: topic)
      + [
        .schedule(
          .postgresTimeout(topic: topic, ref: ref),
          after: record.configuration.postgresChanges.subscriptionTimeout)
      ]
  }

  /// The bindings the server echoed in a join reply, with their ids, or `nil` when it echoed
  /// none.
  private func serverChanges(in message: RealtimeMessage) throws -> [PostgresJoinConfig]? {
    try message.payload["response"]?.objectValue?[ChannelEvent.postgresChanges]?
      .decode(as: [PostgresJoinConfig].self)
  }

  /// Applies a `system` message: the server's report on the join's Postgres changes or on
  /// replication. While the join waits for its Postgres changes, only "Subscribed to
  /// PostgreSQL" confirms it.
  mutating func receiveSystem(_ message: RealtimeMessage) -> [Effect] {
    guard let topic = RealtimeChannel.topic(forWireTopic: message.topic),
      let record = channels[topic]
    else { return [] }
    let `extension` = message.payload["extension"]?.stringValue
    let isPostgresChanges = `extension` == ChannelEvent.postgresChanges
    let isReplication = `extension` == ChannelEvent.system
    let joinRef = record.currentJoinRef
    let isForCurrentJoin = message.joinRef == nil || message.joinRef == joinRef

    switch message.status {
    case .ok where isForCurrentJoin:
      var effects: [Effect] = []
      if isPostgresChanges || !record.awaitsPostgresChanges {
        effects = confirmJoinBySystem(topic)
      }
      if isPostgresChanges {
        effects.append(.deliver(topic, .event(.postgresChangesReady)))
      } else if isReplication {
        effects.append(.deliver(topic, .event(.replicationReady)))
      }
      return effects

    case .error:
      // On a subscribed channel the join stands, so broadcast and presence keep working.
      let reason = message.payload["message"]?.stringValue ?? "\(message.payload)"
      logger.error("Channel '\(topic)' reported an error: \(reason)")
      var effects: [Effect] = []
      if isPostgresChanges, isForCurrentJoin, record.awaitsPostgresChanges,
        case .joining(let ref, _, let stage) = record.phase
      {
        let timer: TimerID =
          stage == .reply
          ? .joinTimeout(topic: topic, ref: ref) : .postgresTimeout(topic: topic, ref: ref)
        effects =
          failPostgresChanges(topic, ref: ref, with: .postgresChangesFailed(reason: reason))
          + [.cancel(timer)]
      }
      if isPostgresChanges {
        effects.append(.deliver(topic, .event(.postgresChangesFailed(reason))))
      } else if isReplication {
        effects.append(.deliver(topic, .event(.replicationFailed(reason))))
      }
      return effects

    default:
      return []
    }
  }

  /// Confirms the current join on a `system` ok, which may come before the join reply, and
  /// stops the timer of the stage it waited in.
  private mutating func confirmJoinBySystem(_ topic: String) -> [Effect] {
    switch channels[topic]?.phase {
    case .joining(let ref, _, .reply)?:
      return confirmJoin(topic, ref: ref) + [.cancel(.joinTimeout(topic: topic, ref: ref))]
    case .joining(let ref, _, .postgres)?:
      return confirmJoin(topic, ref: ref) + [.cancel(.postgresTimeout(topic: topic, ref: ref))]
    case .waitingToRetry?:
      guard let ref = channels[topic]?.timedOutJoinRef else { return [] }
      return confirmJoin(topic, ref: ref) + [.cancel(.rejoin(topic: topic))]
    case .unsubscribed?, .waitingForSocket?, .refreshingToken?, .subscribed?, .leaving?,
      .failed?, nil:
      return []
    }
  }

  mutating func postgresTimedOut(_ topic: String, ref: Ref) -> [Effect] {
    guard case .joining(ref, _, .postgres)? = channels[topic]?.phase else { return [] }
    return failPostgresChanges(topic, ref: ref, with: .postgresChangesTimeout)
  }

  /// Ends a join whose Postgres changes failed: leaves it, so the server drops the half-set-up
  /// join, and fails the subscribe. No retry: the same bindings fail the same way.
  private mutating func failPostgresChanges(
    _ topic: String, ref: Ref, with error: RealtimeError
  ) -> [Effect] {
    logger.error("Failed to subscribe to channel '\(topic)': \(error.message)")
    return sendLeave(topic, joinRef: ref) + failSubscribe(topic, with: error)
  }

  mutating func bindingsChanged(_ topic: String, snapshot: JoinSnapshot) -> [Effect] {
    guard channels[topic] != nil else { return [] }
    channels[topic]?.bindings = snapshot.bindings
    channels[topic]?.presenceEnabled = snapshot.presenceEnabled
    return rejoinIfBindingsChanged(topic)
  }

  /// Rejoins a subscribed channel when it has a binding its join did not carry, so the server
  /// sends those changes too. A removed binding never rejoins.
  ///
  /// The channel leaves the old join and joins again with every binding. It stays
  /// ``RealtimeChannelStatus/subscribing(attempt:)`` until the new join is confirmed.
  private mutating func rejoinIfBindingsChanged(_ topic: String) -> [Effect] {
    guard let record = channels[topic], case .subscribed(let joinRef) = record.phase,
      case .connected = connection
    else { return [] }
    let joined = Set(record.joinedBindings.map(BindingKey.init))
    guard record.bindings.contains(where: { !joined.contains(BindingKey($0)) }) else {
      return []
    }
    logger.debug("Rejoining channel '\(topic)' to add Postgres changes bindings")
    channels[topic]?.isAutomaticRejoin = true
    return sendLeave(topic, joinRef: joinRef) + sendJoin(topic, attempt: 1)
  }

  mutating func joinTimedOut(_ topic: String, ref: Ref) -> [Effect] {
    guard case .joining(ref, let attempt, .reply)? = channels[topic]?.phase else { return [] }
    logger.debug("Subscribe attempt \(attempt) timed out for channel '\(topic)'")
    channels[topic]?.timedOutJoinRef = ref
    return waitToRejoin(
      topic, attempt: attempt, delay: options.rejoinDelay(attempt), lastError: .joinTimeout)
  }

  mutating func rejoinTimerFired(_ topic: String) -> [Effect] {
    guard case .waitingToRetry(let attempt, _, _)? = channels[topic]?.phase else { return [] }
    return sendJoin(topic, attempt: attempt + 1)
  }

  private mutating func confirmJoin(_ topic: String, ref: Ref) -> [Effect] {
    guard var record = channels[topic] else { return [] }
    logger.debug("Server confirmed subscribe for channel '\(topic)'")
    let waiters = record.subscribeWaiters
    let isRejoin = record.hasBeenSubscribed
    record.subscribeWaiters = []
    record.hasBeenSubscribed = true
    record.timedOutJoinRef = nil
    record.hasRefreshedExpiredToken = false
    channels[topic] = record

    var effects: [Effect] = waiters.map { .resume($0, .success) }
    effects += setPhase(.subscribed(joinRef: ref), for: topic)
    if isRejoin {
      effects.append(.deliver(topic, .event(.resubscribed)))
    }
    // A binding added while the join was in flight is not in it yet.
    return effects + rejoinIfBindingsChanged(topic)
  }

  /// Decides what follows a join the server refused: wait and rejoin, or fail the subscribe.
  private mutating func joinAttemptFailed(
    _ topic: String, attempt: Int, error: RealtimeError
  ) -> [Effect] {
    switch error.joinRecovery {
    case .refreshToken where channels[topic]?.hasRefreshedExpiredToken == false:
      logger.debug("Token expired for channel '\(topic)', rejoining with a fresh one")
      return rejoinWithFreshToken(topic, attempt: attempt + 1)
    case .fail, .refreshToken:
      logger.error("Failed to subscribe to channel '\(topic)': \(error.message)")
      return failSubscribe(topic, with: error)
    case .backOff:
      return waitToRejoin(
        topic, attempt: attempt, delay: RealtimeChannel.rateLimitBackoff, lastError: error)
    case .retry:
      return waitToRejoin(
        topic, attempt: attempt, delay: options.rejoinDelay(attempt), lastError: error)
    }
  }

  private mutating func waitToRejoin(
    _ topic: String, attempt: Int, delay: Duration, lastError: RealtimeError
  ) -> [Effect] {
    logger.debug("Retrying subscribe for '\(topic)' in \(delay)")
    // Another failure ends the run of expired-token errors.
    channels[topic]?.hasRefreshedExpiredToken = false
    return setPhase(
      .waitingToRetry(attempt: attempt, retryIn: delay, lastError: lastError), for: topic)
      + [.schedule(.rejoin(topic: topic), after: delay)]
  }

  /// Ends the subscribe for good: every caller waiting for it fails with `error`, and every
  /// push waiting for a reply fails with ``RealtimeError/notSubscribed``.
  mutating func failSubscribe(_ topic: String, with error: RealtimeError) -> [Effect] {
    guard let waiters = channels[topic]?.subscribeWaiters else { return [] }
    channels[topic]?.subscribeWaiters = []
    channels[topic]?.timedOutJoinRef = nil
    return waiters.map { .resume($0, .failure(error)) }
      + failPendingPushes(topic, with: .notSubscribed)
      + setPhase(.failed(error), for: topic)
  }

  /// Moves the channel for `topic` to `phase`, and publishes its status when the status changed.
  mutating func setPhase(_ phase: ChannelRecord.Phase, for topic: String) -> [Effect] {
    guard let previous = channels[topic]?.phase else { return [] }
    channels[topic]?.phase = phase
    logger.debug("Channel '\(topic)': \(previous) → \(phase)")
    guard !phase.status.isSame(as: previous.status) else { return [] }
    return [.publishChannelStatus(topic, phase.status)]
  }
}
