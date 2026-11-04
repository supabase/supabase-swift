//
//  RealtimeCore+Inbound.swift
//  Realtime
//

import Foundation
import Helpers
import Logging

extension RealtimeCore {
  /// The channel of the topic a wire topic names that is not being removed, if any. A topic has
  /// at most one: a new channel of the topic joins only once the old one is removing.
  func liveChannel(forWireTopic wireTopic: String) -> ChannelID? {
    firstChannel(forWireTopic: wireTopic) { !$0.isRemoving }
  }

  /// The channel of the topic a wire topic names whose frames carry `joinRef`: the channel of
  /// that join, or of the leave that ends it. With no `joinRef`, the live channel of the topic.
  func channel(forWireTopic wireTopic: String, joinRef: Ref?) -> ChannelID? {
    guard let joinRef else { return liveChannel(forWireTopic: wireTopic) }
    return firstChannel(forWireTopic: wireTopic) { $0.inboundJoinRef == joinRef }
  }

  /// The channel of `message`'s topic whose frames carry `joinRef`, as
  /// ``channel(forWireTopic:joinRef:)``. A frame that matches no channel is logged.
  func routedChannel(_ message: RealtimeMessage, joinRef: Ref?) -> ChannelID? {
    guard let channel = channel(forWireTopic: message.topic, joinRef: joinRef) else {
      logger.debug(
        "Dropping '\(message.event)' on '\(message.topic)': no channel for join_ref \(joinRef ?? "<none>")"
      )
      return nil
    }
    return channel
  }

  /// The first channel in creation order on `wireTopic` whose record matches `predicate`.
  private func firstChannel(
    forWireTopic wireTopic: String, where predicate: (ChannelRecord) -> Bool
  ) -> ChannelID? {
    var first: ChannelID?
    for (id, record) in channels where record.wireTopic == wireTopic && predicate(record) {
      first = min(first ?? id, id)
    }
    return first
  }

  /// The topic of `channel`, for log lines. A channel with no record has none.
  func topic(of channel: ChannelID) -> String {
    channels[channel]?.topic ?? channel.description
  }

  /// Routes a channel frame that is not `system`, `phx_close`, or `phx_error`: a reply settles
  /// the push of its topic that waits for its ref, or else the join its `join_ref` names, and
  /// the rest goes to the streams of the live channel of its topic. A frame for a topic with
  /// no live channel, or one that cannot be read, is dropped.
  mutating func receiveFrame(_ message: RealtimeMessage) -> [Effect] {
    if message.event == ChannelEvent.reply {
      if let ref = message.ref,
        let channel = firstChannel(
          forWireTopic: message.topic,
          where: {
            $0.pendingPushes[ref] != nil
          })
      {
        return receivePushReply(message, ref: ref, on: channel)
      }
      return receiveJoinReply(message)
    }
    guard let channel = liveChannel(forWireTopic: message.topic) else {
      logger.debug("Dropping '\(message.event)' for unknown topic '\(message.topic)'")
      return []
    }
    switch message.event {
    case ChannelEvent.broadcast:
      guard let broadcast = BroadcastMessage(message) else {
        logger.debug(
          "Dropping a broadcast without an event on '\(topic(of: channel))': \(message.payload)")
        return []
      }
      return [.deliver(channel, .broadcast(broadcast))]
    case ChannelEvent.postgresChanges:
      return receivePostgresChange(message, on: channel)
    case ChannelEvent.presenceState, ChannelEvent.presenceDiff:
      return receivePresence(message, on: channel)
    default:
      logger.debug("Received message with unhandled event type: \(message)")
      return []
    }
  }

  /// Delivers a binary (kind 4) broadcast frame to the live channel of its wire topic.
  mutating func receiveBinaryBroadcast(_ broadcast: DecodedBroadcast) -> [Effect] {
    guard let channel = liveChannel(forWireTopic: broadcast.topic) else {
      logger.debug("Dropping a binary broadcast for unknown topic '\(broadcast.topic)'")
      return []
    }
    return [.deliver(channel, .broadcast(BroadcastMessage(broadcast)))]
  }

  /// Delivers a Postgres change with the server bindings whose ids the frame lists.
  private func receivePostgresChange(_ message: RealtimeMessage, on channel: ChannelID) -> [Effect]
  {
    do {
      guard let data = try RealtimeChannel.postgresChangeData(in: message.payload) else {
        logger.debug("Expected \"data\" key in message payload.")
        return []
      }
      let change = try PostgresChange(payload: data)
      let ids = message.payload["ids"]?.arrayValue?.compactMap(\.intValue) ?? []
      let matched = channels[channel]?.serverChanges.filter { ids.contains($0.id) } ?? []
      return [.deliver(channel, .postgres(PostgresDelivery(change: change, matched: matched)))]
    } catch {
      logger.debug("Dropping a Postgres change on '\(topic(of: channel))': \(error)")
      return []
    }
  }

  /// Applies `presence_state` or `presence_diff` for the current join, and delivers the change
  /// with the new state unless the sync changed nothing. A diff before the join's first state
  /// waits for it.
  private mutating func receivePresence(_ message: RealtimeMessage, on channel: ChannelID)
    -> [Effect]
  {
    guard let currentJoinRef = channels[channel].map(\.currentJoinRef) else { return [] }
    // Presence for an earlier join carries that join's `join_ref`. Broadcast diffs carry none.
    if let joinRef = message.joinRef, joinRef != currentJoinRef {
      logger.debug("Ignoring presence for stale join_ref \(joinRef) on '\(topic(of: channel))'")
      return []
    }
    // Mutated in place, so the tracker's storage is not copied for each frame.
    let change =
      message.event == ChannelEvent.presenceState
      ? channels[channel]?.presence.applyState(message.payload)
      : channels[channel]?.presence.applyDiff(message.payload)
    guard let change, !change.isEmpty, let state = channels[channel]?.presence.state else {
      return []
    }
    return [.deliver(channel, .presence(change, state))]
  }
}

extension RealtimeMessage {
  /// The reason an error reply gives: its `response.reason`, or a `response` that is a string,
  /// or else `default`.
  func replyReason(default: String) -> String {
    let response = payload["response"]
    return response?.objectValue?["reason"]?.stringValue ?? response?.stringValue ?? `default`
  }
}
