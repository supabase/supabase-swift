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
  case json(JSONValue)
  /// Raw bytes from a binary frame.
  case binary(Data)
}

/// A message sent to the channel with broadcast.
///
/// Read it from ``RealtimeChannel/broadcasts(event:)``:
///
/// ```swift
/// for await message in channel.broadcasts(event: "cursor") {
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

  /// Decodes the payload as `T`. A ``BroadcastPayload/binary(_:)`` payload is read as JSON.
  ///
  /// - Parameters:
  ///   - type: The type to decode. Can be inferred from context.
  ///   - decoder: The decoder to use. Defaults to the decoder the SDK uses for server responses.
  /// - Throws: ``RealtimeError`` of kind ``RealtimeError/Kind/decoding`` when the payload does not
  ///   decode as `T`. The underlying `DecodingError` is in ``RealtimeError/underlyingError``.
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
        kind: .decoding, message: "Broadcast \"\(event)\" did not decode as \(T.self).",
        isRetryable: false, underlyingError: error)
    }
  }

  /// Reads a text `broadcast` message. `nil` when the payload has no `event`.
  init?(_ message: RealtimeMessage) {
    guard let event = message.payload["event"]?.stringValue else { return nil }
    self.init(
      event: event,
      payload: .json(message.payload["payload"] ?? .null),
      meta: message.payload["meta"]?.objectValue
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
