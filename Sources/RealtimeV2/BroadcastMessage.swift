//
//  BroadcastMessage.swift
//  Realtime
//
//  Created by Guilherme Souza on 29/10/26.
//

public import Foundation

/// The payload of a ``BroadcastMessage``.
public enum BroadcastPayload: Sendable, Hashable {
  /// A JSON payload, from a text frame or a JSON-encoded binary frame.
  case json(AnyJSON)
  /// Raw bytes from a binary frame.
  case binary(Data)
}

/// A message sent to the channel with broadcast.
///
/// Read it from ``RealtimeChannelV2/broadcasts(event:)``:
///
/// ```swift
/// for await message in await channel.broadcasts(event: "cursor") {
///   let cursor = try message.decode(as: Cursor.self)
/// }
/// ```
public struct BroadcastMessage: Sendable, Hashable {
  /// The event name the sender chose.
  public var event: String
  /// The message payload.
  public var payload: BroadcastPayload
  /// The server's id for the message. The server sets it on database-originated broadcasts.
  public var id: UUID?
  /// Whether the server replayed this message from history when the channel joined.
  public var isReplayed: Bool

  /// Creates a ``BroadcastMessage``.
  public init(
    event: String,
    payload: BroadcastPayload,
    id: UUID? = nil,
    isReplayed: Bool = false
  ) {
    self.event = event
    self.payload = payload
    self.id = id
    self.isReplayed = isReplayed
  }

  /// Decodes the payload as `T`. A ``BroadcastPayload/binary(_:)`` payload is read as JSON.
  ///
  /// - Parameters:
  ///   - type: The type to decode. Can be inferred from context.
  ///   - decoder: The decoder to use. `nil` uses `AnyJSON.decoder`.
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind-swift.struct/decoding`` when the
  ///   payload does not decode as `T`. The underlying `DecodingError` is in
  ///   ``RealtimeError/underlyingError``.
  public func decode<T: Decodable>(
    as _: T.Type = T.self, decoder: JSONDecoder? = nil
  ) throws -> T {
    let decoder = decoder ?? AnyJSON.decoder
    do {
      switch payload {
      case .json(let value): return try value.decode(as: T.self, decoder: decoder)
      case .binary(let data): return try decoder.decode(T.self, from: data)
      }
    } catch {
      throw RealtimeError.decoding(
        "Broadcast \"\(event)\" did not decode as \(T.self).", underlyingError: error)
    }
  }

  /// Reads the payload of a text `broadcast` message: `{event, payload, type, meta}`.
  init(event: String, envelope: JSONObject) {
    self.init(
      event: event,
      payload: .json(envelope["payload"] ?? .null),
      meta: envelope["meta"]?.objectValue
    )
  }

  /// Reads a binary (kind 4) broadcast frame.
  init(_ broadcast: DecodedBroadcast) {
    let payload: BroadcastPayload =
      switch broadcast.payload {
      case .json(let object): .json(.object(object))
      case .binary(let data): .binary(data)
      }
    self.init(event: broadcast.event, payload: payload, meta: broadcast.meta)
  }

  private init(event: String, payload: BroadcastPayload, meta: JSONObject?) {
    self.event = event
    self.payload = payload
    id = meta?["id"]?.stringValue.flatMap(UUID.init(uuidString:))
    isReplayed = meta?["replayed"]?.boolValue ?? false
  }
}
