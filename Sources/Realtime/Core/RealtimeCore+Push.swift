//
//  RealtimeCore+Push.swift
//  Realtime
//

import Foundation
import Helpers
import Logging

extension RealtimeCore {
  /// Sends `event` on `channel`. With a waiter, the push waits, bounded by the
  /// timeout, for the server's reply; without one, it is fire-and-forget.
  ///
  /// Only a subscribed channel sends. Otherwise the waiter fails with
  /// ``RealtimeError/notSubscribed``, and nothing is kept to send later.
  mutating func push(
    _ channel: ChannelID, event: String, payload: JSONObject, waiter: WaiterID?
  ) -> [Effect] {
    guard let record = channels[channel], let joinRef = subscribedJoinRef(channel) else {
      logger.debug("Dropping push '\(event)' for channel '\(topic(of: channel))': not subscribed")
      return waiter.map { [.resume($0, .failure(.notSubscribed))] } ?? []
    }
    let ref = makeRef()
    let message = RealtimeMessage(
      joinRef: joinRef, ref: ref, topic: record.wireTopic, event: event,
      payload: payload)
    guard let waiter else { return [.send(message)] }
    return [.send(message)] + awaitReply(channel, ref: ref, waiter: waiter)
  }

  /// Sends a broadcast on `channel` as a binary frame. The waiter returns once the
  /// frame is out, or, when the channel acknowledges broadcasts, once the server replies.
  mutating func broadcast(
    _ channel: ChannelID, event: String, payload: BroadcastPushPayload, waiter: WaiterID
  ) -> [Effect] {
    guard let record = channels[channel], let joinRef = subscribedJoinRef(channel) else {
      logger.debug(
        "Dropping broadcast '\(event)' for channel '\(topic(of: channel))': not subscribed")
      return [.resume(waiter, .failure(.notSubscribed))]
    }
    let ref = makeRef()
    let send = Effect.sendBroadcast(
      joinRef: joinRef, ref: ref, topic: record.wireTopic, event: event,
      payload: payload)
    guard record.configuration.broadcast.acknowledge else {
      return [send, .resume(waiter, .success)]
    }
    return [send] + awaitReply(channel, ref: ref, waiter: waiter)
  }

  /// Settles the push `ref` with the server's reply: `error` fails it with the server's reason,
  /// and any other status resolves it.
  mutating func receivePushReply(_ message: RealtimeMessage, ref: Ref, on channel: ChannelID)
    -> [Effect]
  {
    guard let status = message.status else {
      logger.debug(
        "Dropping a reply without a status on '\(topic(of: channel))': \(message.payload)")
      return []
    }
    guard let waiter = channels[channel]?.pendingPushes.removeValue(forKey: ref) else { return [] }
    let outcome: WaiterOutcome
    if status == .error {
      let reason = message.replyReason(default: "The server rejected the push.")
      outcome = .failure(.ackError(reason: reason))
    } else {
      outcome = .success
    }
    return [.resume(waiter, outcome), .cancel(.pushTimeout(channel: channel, ref: ref))]
  }

  mutating func pushTimedOut(_ channel: ChannelID, ref: Ref) -> [Effect] {
    guard let waiter = channels[channel]?.pendingPushes.removeValue(forKey: ref) else { return [] }
    logger.debug("Push \(ref) on '\(topic(of: channel))' timed out")
    return [.resume(waiter, .failure(.pushTimeout))]
  }

  /// Fails every push of `channel` that waits for a reply, in the order they were sent, and stops
  /// their timeouts.
  mutating func failPendingPushes(_ channel: ChannelID, with error: RealtimeError) -> [Effect] {
    guard let pushes = channels[channel]?.pendingPushes, !pushes.isEmpty else { return [] }
    channels[channel]?.pendingPushes = [:]
    return pushes.sorted { (UInt64($0.key) ?? 0) < (UInt64($1.key) ?? 0) }
      .flatMap { ref, waiter -> [Effect] in
        [.resume(waiter, .failure(error)), .cancel(.pushTimeout(channel: channel, ref: ref))]
      }
  }

  private mutating func awaitReply(_ channel: ChannelID, ref: Ref, waiter: WaiterID) -> [Effect] {
    channels[channel]?.pendingPushes[ref] = waiter
    return [.schedule(.pushTimeout(channel: channel, ref: ref), after: options.timeout)]
  }

  /// The join ref of `channel` when it is subscribed on a connected socket.
  private func subscribedJoinRef(_ channel: ChannelID) -> Ref? {
    guard case .subscribed(let joinRef)? = channels[channel]?.phase, isConnected else {
      return nil
    }
    return joinRef
  }
}
