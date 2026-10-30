//
//  RealtimeCore+Inbound.swift
//  Realtime
//

import Foundation
import Helpers
import Logging

extension RealtimeCore {
  /// Routes a channel frame that is not `system`, `phx_close`, or `phx_error` by its wire
  /// topic: replies settle a push or a join, and the rest goes to the channel's streams. A frame
  /// for a topic with no channel, or one that cannot be read, is dropped.
  mutating func receiveFrame(_ message: RealtimeMessage) -> [Effect] {
    guard let topic = RealtimeChannel.topic(forWireTopic: message.topic), channels[topic] != nil
    else {
      logger.debug("Dropping '\(message.event)' for unknown topic '\(message.topic)'")
      return []
    }
    switch message.event {
    case ChannelEvent.reply:
      if let ref = message.ref, channels[topic]?.pendingPushes[ref] != nil {
        return receivePushReply(message, ref: ref, on: topic)
      }
      return receiveJoinReply(message)
    case ChannelEvent.broadcast:
      guard let broadcast = BroadcastMessage(message) else {
        logger.debug("Dropping a broadcast without an event on '\(topic)': \(message.payload)")
        return []
      }
      return [.deliver(topic, .broadcast(broadcast))]
    case ChannelEvent.postgresChanges:
      return receivePostgresChange(message, on: topic)
    case ChannelEvent.presenceState, ChannelEvent.presenceDiff:
      return receivePresence(message, on: topic)
    default:
      logger.debug("Received message with unhandled event type: \(message)")
      return []
    }
  }

  /// Delivers a binary (kind 4) broadcast frame to the channel of its wire topic.
  mutating func receiveBinaryBroadcast(_ broadcast: DecodedBroadcast) -> [Effect] {
    guard let topic = RealtimeChannel.topic(forWireTopic: broadcast.topic), channels[topic] != nil
    else {
      logger.debug("Dropping a binary broadcast for unknown topic '\(broadcast.topic)'")
      return []
    }
    return [.deliver(topic, .broadcast(BroadcastMessage(broadcast)))]
  }

  /// Delivers a Postgres change with the server bindings whose ids the frame lists.
  private func receivePostgresChange(_ message: RealtimeMessage, on topic: String) -> [Effect] {
    do {
      guard let data = try RealtimeChannel.postgresChangeData(in: message.payload) else {
        logger.debug("Expected \"data\" key in message payload.")
        return []
      }
      let change = try PostgresChange(payload: data)
      let ids = message.payload["ids"]?.arrayValue?.compactMap(\.intValue) ?? []
      let matched = channels[topic]?.serverChanges.filter { ids.contains($0.id) } ?? []
      return [.deliver(topic, .postgres(PostgresDelivery(change: change, matched: matched)))]
    } catch {
      logger.debug("Dropping a Postgres change on '\(topic)': \(error)")
      return []
    }
  }

  /// Applies `presence_state` or `presence_diff` for the current join, and delivers the change
  /// with the new state unless the sync changed nothing. A diff before the join's first state
  /// waits for it.
  private mutating func receivePresence(_ message: RealtimeMessage, on topic: String) -> [Effect] {
    guard var record = channels[topic] else { return [] }
    // Presence for an earlier join carries that join's `join_ref`. Broadcast diffs carry none.
    if let joinRef = message.joinRef, joinRef != record.currentJoinRef {
      logger.debug("Ignoring presence for stale join_ref \(joinRef) on '\(topic)'")
      return []
    }
    let change =
      message.event == ChannelEvent.presenceState
      ? record.presence.applyState(message.payload)
      : record.presence.applyDiff(message.payload)
    channels[topic] = record
    guard let change, !change.isEmpty else { return [] }
    return [.deliver(topic, .presence(change, record.presence.state))]
  }
}
