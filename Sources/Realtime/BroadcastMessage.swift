//
//  BroadcastMessage.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

public import Foundation

/// The payload of a broadcast message.
public enum BroadcastPayload: Sendable, Hashable {
  /// A JSON payload, from a text frame or a JSON-encoded binary frame.
  case json(JSONValue)
  /// Raw bytes from a binary frame.
  case binary(Data)
}

/// A message sent to the channel with broadcast.
public struct BroadcastMessage: Sendable, Hashable {
  /// The event name the sender chose.
  public var event: String
  /// The message payload.
  public var payload: BroadcastPayload
  /// The server's id for the message, set on database-originated broadcasts and on REST
  /// broadcasts sent with an id.
  public var id: UUID?
  /// Whether the server replayed this message from history when the channel joined.
  public var isReplayed: Bool

  /// Decodes the payload as `T`. A ``BroadcastPayload/binary(_:)`` payload is read as JSON.
  ///
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/decoding`` when the payload does not
  ///   decode.
  public func decode<T: Decodable>(
    as _: T.Type = T.self, decoder: JSONDecoder = .supabase()
  ) throws -> T {
    do {
      switch payload {
      case .json(let value): return try value.decode(as: T.self, decoder: decoder)
      case .binary(let data): return try decoder.decode(T.self, from: data)
      }
    } catch {
      throw RealtimeError(
        kind: .decoding, message: "broadcast \(event) did not decode as \(T.self)",
        underlyingError: error)
    }
  }

  /// A text `broadcast` message or a kind-4 binary broadcast; `nil` for anything else.
  package init?(_ inbound: ChannelInbound) {
    let meta: JSONObject?
    switch inbound {
    case .message(let message):
      guard message.event == "broadcast", let event = message.payload["event"]?.stringValue else {
        return nil
      }
      self.event = event
      payload = .json(message.payload["payload"] ?? .null)
      meta = message.payload["meta"]?.objectValue
    case .broadcast(let broadcast):
      event = broadcast.event
      switch broadcast.payload {
      case .json(let object): payload = .json(.object(object))
      case .binary(let data): payload = .binary(data)
      }
      meta = broadcast.meta
    case .resubscribed, .presenceChanged:
      return nil
    }
    id = meta?["id"]?.stringValue.flatMap(UUID.init(uuidString:))
    isReplayed = meta?["replayed"]?.boolValue ?? false
  }
}
