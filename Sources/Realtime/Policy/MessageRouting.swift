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

/// A route holds no list of its own, so routing a message allocates nothing beyond the delivery.
struct ChannelRoute {
  let delivery: ChannelDelivery
  private let audience: Audience
  private let bindings: [ChannelBinding]

  fileprivate init(_ delivery: ChannelDelivery, _ audience: Audience, bindings: [ChannelBinding]) {
    self.delivery = delivery
    self.audience = audience
    self.bindings = bindings
  }

  /// Indexes into the bindings the route was computed from, in binding order.
  var listeners: [Int] {
    bindings.indices.filter { accepts(bindings[$0]) }
  }

  var hasListeners: Bool {
    bindings.contains(where: accepts)
  }

  func accepts(_ binding: ChannelBinding) -> Bool {
    switch (audience, binding) {
    case (.system, .system), (.presence, .presence):
      true
    case (.broadcast(let event), .broadcast(let listening)),
      (.broadcastData(let event), .broadcastData(let listening)):
      eventMatches(listening, event)
    case (.postgres(let ids, let serverChanges), .postgres(let change)):
      serverChanges.contains { server in
        ids.contains { $0.intValue == server.id } && server.matches(change)
      }
    default:
      false
    }
  }

  fileprivate enum Audience {
    case system
    case presence
    case broadcast(event: String)
    case broadcastData(event: String)
    /// `ids` are the server binding ids the change names, as the payload sent them.
    case postgres(ids: [JSONValue], serverChanges: [PostgresJoinConfig])
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
    return ChannelRoute(.system(message), .system, bindings: bindings)

  case .broadcast:
    guard let event = message.payload["event"]?.stringValue else {
      throw RealtimeError.decoding("Expected 'event' key in 'payload' for broadcast event.")
    }
    return broadcastRoute(message.payload, event: event, bindings: bindings)

  case .postgresChanges:
    guard let data = message.payload["data"] else {
      throw RealtimeError.decoding("Expected \"data\" key in message payload.")
    }
    let ids = message.payload["ids"]?.arrayValue ?? []
    let action = try makeAction(from: data.decode(as: PostgresActionData.self), rawMessage: message)
    return ChannelRoute(
      .postgres(action), .postgres(ids: ids, serverChanges: serverChanges), bindings: bindings)

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
    return ChannelRoute(.broadcastData(data), .broadcastData(event: event), bindings: bindings)
  }
}

private func broadcastRoute(
  _ json: JSONObject, event: String, bindings: [ChannelBinding]
) -> ChannelRoute {
  ChannelRoute(.broadcast(json), .broadcast(event: event), bindings: bindings)
}

private func presenceRoute(
  joins: [String: PresenceV2],
  leaves: [String: PresenceV2],
  rawMessage: RealtimeMessageV2,
  bindings: [ChannelBinding]
) -> ChannelRoute {
  let action = PresenceActionImpl(joins: joins, leaves: leaves, rawMessage: rawMessage)
  return ChannelRoute(.presence(action), .presence, bindings: bindings)
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
