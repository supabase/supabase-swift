//
//  RealtimeCore+Push.swift
//  Realtime
//

import Foundation
import Helpers
import Logging

extension RealtimeCore {
  /// Sends `event` on the channel for `topic`. With a waiter, the push waits, bounded by the
  /// timeout, for the server's reply; without one, it is fire-and-forget.
  ///
  /// Only a subscribed channel sends. Otherwise the waiter fails with
  /// ``RealtimeError/notSubscribed``, and nothing is kept to send later.
  mutating func push(
    _ topic: String, event: String, payload: JSONObject, waiter: WaiterID?
  ) -> [Effect] {
    guard let joinRef = subscribedJoinRef(topic) else {
      logger.debug("Dropping push '\(event)' for channel '\(topic)': not subscribed")
      return waiter.map { [.resume($0, .failure(.notSubscribed))] } ?? []
    }
    let ref = makeRef()
    let message = RealtimeMessage(
      joinRef: joinRef, ref: ref, topic: RealtimeChannel.wireTopic(for: topic), event: event,
      payload: payload)
    guard let waiter else { return [.send(message)] }
    return [.send(message)] + awaitReply(topic, ref: ref, waiter: waiter)
  }

  /// Sends a broadcast on the channel for `topic` as a binary frame. The waiter returns once the
  /// frame is out, or, when the channel acknowledges broadcasts, once the server replies.
  mutating func broadcast(
    _ topic: String, event: String, payload: BroadcastPushPayload, waiter: WaiterID
  ) -> [Effect] {
    guard let record = channels[topic], let joinRef = subscribedJoinRef(topic) else {
      logger.debug("Dropping broadcast '\(event)' for channel '\(topic)': not subscribed")
      return [.resume(waiter, .failure(.notSubscribed))]
    }
    let ref = makeRef()
    let send = Effect.sendBroadcast(
      joinRef: joinRef, ref: ref, topic: RealtimeChannel.wireTopic(for: topic), event: event,
      payload: payload)
    guard record.configuration.broadcast.acknowledge else {
      return [send, .resume(waiter, .success)]
    }
    return [send] + awaitReply(topic, ref: ref, waiter: waiter)
  }

  /// Settles the push `ref` with the server's reply: `error` fails it with the server's reason,
  /// and any other status resolves it.
  mutating func receivePushReply(_ message: RealtimeMessage, ref: Ref, on topic: String)
    -> [Effect]
  {
    guard let status = message.status else {
      logger.debug("Dropping a reply without a status on '\(topic)': \(message.payload)")
      return []
    }
    guard let waiter = channels[topic]?.pendingPushes.removeValue(forKey: ref) else { return [] }
    let outcome: WaiterOutcome
    if status == .error {
      let response = message.payload["response"]
      let reason =
        response?.objectValue?["reason"]?.stringValue
        ?? response?.stringValue
        ?? "The server rejected the push."
      outcome = .failure(.ackError(reason: reason))
    } else {
      outcome = .success
    }
    return [.resume(waiter, outcome), .cancel(.pushTimeout(topic: topic, ref: ref))]
  }

  mutating func pushTimedOut(_ topic: String, ref: Ref) -> [Effect] {
    guard let waiter = channels[topic]?.pendingPushes.removeValue(forKey: ref) else { return [] }
    logger.debug("Push \(ref) on '\(topic)' timed out")
    return [.resume(waiter, .failure(.pushTimeout))]
  }

  /// Fails every push of `topic` that waits for a reply, in the order they were sent, and stops
  /// their timeouts.
  mutating func failPendingPushes(_ topic: String, with error: RealtimeError) -> [Effect] {
    guard let pushes = channels[topic]?.pendingPushes, !pushes.isEmpty else { return [] }
    channels[topic]?.pendingPushes = [:]
    return pushes.sorted { (UInt64($0.key) ?? 0) < (UInt64($1.key) ?? 0) }
      .flatMap { ref, waiter -> [Effect] in
        [.resume(waiter, .failure(error)), .cancel(.pushTimeout(topic: topic, ref: ref))]
      }
  }

  private mutating func awaitReply(_ topic: String, ref: Ref, waiter: WaiterID) -> [Effect] {
    channels[topic]?.pendingPushes[ref] = waiter
    return [.schedule(.pushTimeout(topic: topic, ref: ref), after: options.timeout)]
  }

  /// The join ref of the channel for `topic` when it is subscribed on a connected socket.
  private func subscribedJoinRef(_ topic: String) -> Ref? {
    guard case .subscribed(let joinRef)? = channels[topic]?.phase, isConnected else {
      return nil
    }
    return joinRef
  }
}
