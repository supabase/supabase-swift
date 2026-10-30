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
  /// waits for the socket otherwise.
  mutating func sendJoin(_ topic: String, attempt: Int) -> [Effect] {
    guard case .connected = connection else {
      return waitForSocket(topic, attempt: attempt)
    }
    return pushJoin(topic, attempt: attempt)
  }

  /// Writes the `phx_join` for attempt `attempt`, with the current token, and starts its timeout.
  private mutating func pushJoin(_ topic: String, attempt: Int) -> [Effect] {
    guard var record = channels[topic] else { return [] }
    let ref = makeRef()
    record.timedOutJoinRef = nil
    let config = RealtimeJoinConfig(
      record.configuration, bindings: record.bindings, presenceEnabled: record.presenceEnabled)
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
    case .waitingToRetry where record.timedOutJoinRef == ref && message.status == .ok:
      logger.debug("Late join reply confirmed channel '\(topic)' during the rejoin backoff")
      return confirmJoin(topic, ref: ref) + [.cancel(.rejoin(topic: topic))]
    default:
      return []
    }
  }

  private mutating func receiveReply(
    _ message: RealtimeMessage, toJoin ref: Ref, attempt: Int, on topic: String
  ) -> [Effect] {

    let effects: [Effect]
    if message.status == .ok {
      effects = confirmJoin(topic, ref: ref)
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
    channels[topic] = record

    var effects: [Effect] = waiters.map { .resume($0, .success) }
    effects += setPhase(.subscribed(joinRef: ref), for: topic)
    if isRejoin {
      effects.append(.deliver(topic, .event(.resubscribed)))
    }
    return effects
  }

  /// Decides what follows a join the server refused: wait and rejoin, or fail the subscribe.
  private mutating func joinAttemptFailed(
    _ topic: String, attempt: Int, error: RealtimeError
  ) -> [Effect] {
    switch error.joinRecovery {
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
    return setPhase(
      .waitingToRetry(attempt: attempt, retryIn: delay, lastError: lastError), for: topic)
      + [.schedule(.rejoin(topic: topic), after: delay)]
  }

  /// Ends the subscribe for good: every caller waiting for it fails with `error`.
  private mutating func failSubscribe(_ topic: String, with error: RealtimeError) -> [Effect] {
    guard let waiters = channels[topic]?.subscribeWaiters else { return [] }
    channels[topic]?.subscribeWaiters = []
    channels[topic]?.timedOutJoinRef = nil
    return waiters.map { .resume($0, .failure(error)) } + setPhase(.failed(error), for: topic)
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
