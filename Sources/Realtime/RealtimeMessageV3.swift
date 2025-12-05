//
//  RealtimeMessageV3.swift
//
//
//  Created by Guilherme Souza on 05/12/24.
//

import Foundation

/// Payload type that can represent either JSON or binary data.
public enum RealtimePayload: Sendable, Hashable {
  /// JSON payload represented as a dictionary
  case json(JSONObject)
  /// Binary payload
  case binary(Data)

  /// Returns the JSON object if this is a JSON payload
  public var jsonValue: JSONObject? {
    if case .json(let object) = self {
      return object
    }
    return nil
  }

  /// Returns the binary data if this is a binary payload
  public var binaryValue: Data? {
    if case .binary(let data) = self {
      return data
    }
    return nil
  }

  /// Helper to get a value from the JSON payload
  public subscript(key: String) -> AnyJSON? {
    jsonValue?[key]
  }
}

extension RealtimePayload: Codable {
  public init(from decoder: any Decoder) throws {
    // When decoding, we always decode as JSON
    let container = try decoder.singleValueContainer()
    let object = try container.decode(JSONObject.self)
    self = .json(object)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .json(let object):
      try container.encode(object)
    case .binary(let data):
      try container.encode(data)
      // Binary payloads should be encoded using the binary encoder, not JSONEncoder
      throw EncodingError.invalidValue(
        self,
        EncodingError.Context(
          codingPath: encoder.codingPath,
          debugDescription: "Binary payloads must be encoded using RealtimeBinaryEncoder"
        )
      )
    }
  }
}

/// V3 Realtime message with proper support for both JSON and binary payloads.
///
/// This type is designed to work seamlessly with the V2 serializer while maintaining
/// backward compatibility through conversion to/from `RealtimeMessageV2`.
public struct RealtimeMessageV3: Hashable, Sendable {
  public let joinRef: String?
  public let ref: String?
  public let topic: String
  public let event: String
  public let payload: RealtimePayload

  public init(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    payload: RealtimePayload
  ) {
    self.joinRef = joinRef
    self.ref = ref
    self.topic = topic
    self.event = event
    self.payload = payload
  }

  /// Convenience initializer for JSON payloads
  public init(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    payload: JSONObject
  ) {
    self.init(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      payload: .json(payload)
    )
  }

  /// Convenience initializer for binary payloads
  public init(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    binaryPayload: Data
  ) {
    self.init(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      payload: .binary(binaryPayload)
    )
  }

  /// Status for the received message if any.
  public var status: PushStatus? {
    payload["status"]
      .flatMap(\.stringValue)
      .flatMap(PushStatus.init(rawValue:))
  }

  /// Converts to V2 message format (for backward compatibility)
  public func toV2() -> RealtimeMessageV2 {
    let jsonPayload: JSONObject
    switch payload {
    case .json(let object):
      jsonPayload = object
    case .binary(let data):
      // Wrap binary data in the special marker format
      jsonPayload = ["payload": RealtimeBinaryPayload.binary(data)]
    }

    return RealtimeMessageV2(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      payload: jsonPayload
    )
  }

  /// Creates from V2 message format
  public static func fromV2(_ message: RealtimeMessageV2) -> RealtimeMessageV3 {
    // Check if this is a direct binary payload (not a broadcast message with nested binary)
    // A direct binary payload would have just the "payload" key with binary marker
    if message.payload.count == 1,
      let payloadValue = message.payload["payload"],
      let binaryData = RealtimeBinaryPayload.data(from: payloadValue)
    {
      return RealtimeMessageV3(
        joinRef: message.joinRef,
        ref: message.ref,
        topic: message.topic,
        event: message.event,
        binaryPayload: binaryData
      )
    }

    // Otherwise it's a JSON payload (including broadcast messages with nested binary)
    return RealtimeMessageV3(
      joinRef: message.joinRef,
      ref: message.ref,
      topic: message.topic,
      event: message.event,
      payload: message.payload
    )
  }
}

extension RealtimeMessageV3: Codable {
  private enum CodingKeys: String, CodingKey {
    case joinRef = "join_ref"
    case ref
    case topic
    case event
    case payload
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    joinRef = try container.decodeIfPresent(String.self, forKey: .joinRef)
    ref = try container.decodeIfPresent(String.self, forKey: .ref)
    topic = try container.decode(String.self, forKey: .topic)
    event = try container.decode(String.self, forKey: .event)
    payload = try container.decode(RealtimePayload.self, forKey: .payload)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(joinRef, forKey: .joinRef)
    try container.encodeIfPresent(ref, forKey: .ref)
    try container.encode(topic, forKey: .topic)
    try container.encode(event, forKey: .event)
    try container.encode(payload, forKey: .payload)
  }
}

extension RealtimeMessageV3: HasRawMessage {
  public var rawMessage: RealtimeMessageV2 {
    toV2()
  }
}
