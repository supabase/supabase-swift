//
//  MessageRouting.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import Foundation
import Helpers

enum ChannelBinding: Sendable {
  case broadcast(event: String)
  case broadcastData(event: String)
  case postgres(PostgresJoinConfig)
  case presence
  case system
  /// A `statusChange` stream. No message reaches it; it keeps the bindings aligned with the
  /// channel's streams.
  case status
}

extension ChannelBinding {
  var isPresence: Bool {
    if case .presence = self { true } else { false }
  }
}

enum ChannelDelivery: Sendable {
  case broadcast(JSONObject)
  case broadcastData(Data)
  case postgres(AnyAction)
  case presence(any PresenceAction)
  case system(RealtimeMessageV2)
}

struct ChannelRoute {
  let delivery: ChannelDelivery
  /// Indexes into the bindings the route was computed from, in binding order.
  let listeners: [Int]

  fileprivate init(
    _ delivery: ChannelDelivery,
    bindings: [ChannelBinding],
    where accepts: (ChannelBinding) -> Bool
  ) {
    self.delivery = delivery
    listeners = bindings.indices.filter { accepts(bindings[$0]) }
  }
}

/// Decodes a channel message and decides which streams receive it.
///
/// - Parameters:
///   - bindings: The channel's open streams, in registration order.
///   - serverChanges: The `postgres_changes` bindings the server echoed back on join, with their
///     ids. A change reaches every postgres stream whose binding matches one of the server
///     bindings the change names.
/// - Returns: The route, or `nil` for an event that never reaches a stream.
/// - Throws: ``RealtimeError`` with kind `.decoding`, or a `DecodingError`, when the payload does
///   not have the shape its event needs.
func route(
  _ message: RealtimeMessageV2,
  bindings: [ChannelBinding],
  serverChanges: [PostgresJoinConfig]
) throws -> ChannelRoute? {
  switch message.eventType {
  case .system:
    return ChannelRoute(.system(message), bindings: bindings) {
      if case .system = $0 { true } else { false }
    }

  case .broadcast:
    guard let event = message.payload["event"]?.stringValue else {
      throw RealtimeError.decoding("Expected 'event' key in 'payload' for broadcast event.")
    }
    return broadcastRoute(message.payload, event: event, bindings: bindings)

  case .postgresChanges:
    guard let data = message.payload["data"] else {
      throw RealtimeError.decoding("Expected \"data\" key in message payload.")
    }
    let ids = message.payload["ids"]?.arrayValue?.compactMap(\.intValue) ?? []
    let action = try makeAction(from: data.decode(as: PostgresActionData.self), rawMessage: message)
    let matched = serverChanges.filter { ids.contains($0.id) }
    return ChannelRoute(.postgres(action), bindings: bindings) { binding in
      guard case .postgres(let change) = binding else { return false }
      return matched.contains { $0.matches(change) }
    }

  case .presenceDiff:
    let joins = try message.payload["joins"]?.decode(as: [String: PresenceV2].self) ?? [:]
    let leaves = try message.payload["leaves"]?.decode(as: [String: PresenceV2].self) ?? [:]
    return presenceRoute(joins: joins, leaves: leaves, rawMessage: message, bindings: bindings)

  case .presenceState:
    let joins = try message.payload.decode(as: [String: PresenceV2].self)
    return presenceRoute(joins: joins, leaves: [:], rawMessage: message, bindings: bindings)

  default:
    return nil
  }
}

/// Decides which streams receive a binary broadcast frame.
///
/// A JSON payload reaches the `broadcasts(event:)` streams in the same shape as a text
/// broadcast, with the frame's metadata as `meta`. A binary payload reaches the
/// `broadcastData(event:)` streams.
///
/// - Parameters:
///   - broadcast: The decoded kind 4 frame.
///   - bindings: The channel's open streams, in registration order.
func route(_ broadcast: DecodedBroadcast, bindings: [ChannelBinding]) -> ChannelRoute {
  let event = broadcast.event
  switch broadcast.payload {
  case .json(let json):
    var message: JSONObject = [
      "event": .string(event),
      "payload": .object(json),
      "type": "broadcast",
    ]
    message["meta"] = broadcast.meta.map(JSONValue.object)
    return broadcastRoute(message, event: event, bindings: bindings)

  case .binary(let data):
    return ChannelRoute(.broadcastData(data), bindings: bindings) {
      if case .broadcastData(let listening) = $0 { eventMatches(listening, event) } else { false }
    }
  }
}

private func broadcastRoute(
  _ json: JSONObject, event: String, bindings: [ChannelBinding]
) -> ChannelRoute {
  ChannelRoute(.broadcast(json), bindings: bindings) {
    if case .broadcast(let listening) = $0 { eventMatches(listening, event) } else { false }
  }
}

private func presenceRoute(
  joins: [String: PresenceV2],
  leaves: [String: PresenceV2],
  rawMessage: RealtimeMessageV2,
  bindings: [ChannelBinding]
) -> ChannelRoute {
  let action = PresenceActionImpl(joins: joins, leaves: leaves, rawMessage: rawMessage)
  return ChannelRoute(.presence(action), bindings: bindings, where: \.isPresence)
}

private func eventMatches(_ listening: String, _ event: String) -> Bool {
  listening == "*" || listening.lowercased() == event.lowercased()
}

private func makeAction(
  from data: PostgresActionData,
  rawMessage: RealtimeMessageV2
) throws -> AnyAction {
  switch data.type {
  case "UPDATE":
    return .update(
      UpdateAction(
        columns: data.columns,
        commitTimestamp: data.commitTimestamp,
        record: data.record ?? [:],
        oldRecord: data.oldRecord ?? [:],
        rawMessage: rawMessage
      )
    )

  case "DELETE":
    return .delete(
      DeleteAction(
        columns: data.columns,
        commitTimestamp: data.commitTimestamp,
        oldRecord: data.oldRecord ?? [:],
        rawMessage: rawMessage
      )
    )

  case "INSERT":
    return .insert(
      InsertAction(
        columns: data.columns,
        commitTimestamp: data.commitTimestamp,
        record: data.record ?? [:],
        rawMessage: rawMessage
      )
    )

  default:
    throw RealtimeError.decoding("Unknown event type: \(data.type)")
  }
}
