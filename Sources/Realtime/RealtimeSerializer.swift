//
//  RealtimeSerializer.swift
//
//
//  Created by Guilherme Souza on 12/02/26.
//

import Foundation

/// Represents a decoded binary broadcast message from the server.
struct DecodedBroadcast: Sendable {
  let topic: String
  /// The user event name extracted from the binary frame.
  let event: String
  let payload: Payload

  enum Payload: Sendable {
    case json(JSONObject)
    case binary(Data)
  }
}

/// Handles encoding/decoding between ``RealtimeMessageV2`` and the Realtime protocol 2.0.0 wire format.
///
/// Protocol 2.0.0 uses:
/// - JSON array text frames for non-broadcast messages: `[joinRef, ref, topic, event, payload]`
/// - Binary frames for broadcast messages (type 0x03 client->server, type 0x04 server->client)
struct RealtimeSerializer: Sendable {
  enum BinaryKind: UInt8 {
    /// Client -> server broadcast push.
    case userBroadcastPush = 3
    /// Server -> client broadcast.
    case userBroadcast = 4
  }

  enum PayloadEncoding: UInt8 {
    case binary = 0
    case json = 1
  }

  // MARK: - Text encoding (JSON array format)

  /// Encodes a ``RealtimeMessageV2`` as a JSON array string: `[joinRef, ref, topic, event, payload]`.
  func encodeText(_ message: RealtimeMessageV2) throws -> String {
    var array: [AnyJSON] = [
      message.joinRef.map { .string($0) } ?? .null,
      message.ref.map { .string($0) } ?? .null,
      .string(message.topic),
      .string(message.event),
      .object(message.payload),
    ]

    let data = try JSONEncoder().encode(array)
    guard let text = String(data: data, encoding: .utf8) else {
      throw RealtimeError("Failed to encode message as UTF-8 string.")
    }
    return text
  }

  // MARK: - Text decoding (JSON array format)

  /// Decodes a JSON array string `[joinRef, ref, topic, event, payload]` into a ``RealtimeMessageV2``.
  func decodeText(_ text: String) throws -> RealtimeMessageV2 {
    let data = Data(text.utf8)
    let array = try JSONDecoder().decode([AnyJSON].self, from: data)

    guard array.count >= 5 else {
      throw RealtimeError(
        "Expected JSON array with 5 elements, got \(array.count)."
      )
    }

    let joinRef = array[0].stringValue
    let ref = array[1].stringValue
    guard let topic = array[2].stringValue else {
      throw RealtimeError("Expected string for topic at index 2.")
    }
    guard let event = array[3].stringValue else {
      throw RealtimeError("Expected string for event at index 3.")
    }
    guard let payload = array[4].objectValue else {
      throw RealtimeError("Expected object for payload at index 4.")
    }

    return RealtimeMessageV2(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      payload: payload
    )
  }

  // MARK: - Binary encoding (type 0x03 - client -> server)

  /// Encodes a broadcast push as a binary frame (type 0x03) with a JSON payload.
  ///
  /// Binary frame format:
  /// ```
  /// [kind:1][joinRef_len:1][ref_len:1][topic_len:1][event_len:1][meta_len:1][encoding:1]
  /// [joinRef][ref][topic][event][metadata][payload]
  /// ```
  func encodeBroadcastPush(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    jsonPayload: JSONObject
  ) throws -> Data {
    let payloadData = try JSONEncoder().encode(jsonPayload)
    return try _encodeBroadcastPush(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      encoding: .json,
      payload: payloadData
    )
  }

  /// Encodes a broadcast push as a binary frame (type 0x03) with a binary payload.
  func encodeBroadcastPush(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    binaryPayload: Data
  ) throws -> Data {
    try _encodeBroadcastPush(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      encoding: .binary,
      payload: binaryPayload
    )
  }

  private func _encodeBroadcastPush(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    encoding: PayloadEncoding,
    payload: Data
  ) throws -> Data {
    let joinRefBytes = Data((joinRef ?? "").utf8)
    let refBytes = Data((ref ?? "").utf8)
    let topicBytes = Data(topic.utf8)
    let eventBytes = Data(event.utf8)
    // No metadata for now (empty).
    let metaBytes = Data()

    guard joinRefBytes.count <= 255,
      refBytes.count <= 255,
      topicBytes.count <= 255,
      eventBytes.count <= 255,
      metaBytes.count <= 255
    else {
      throw RealtimeError(
        "Binary frame header fields must not exceed 255 bytes each."
      )
    }

    var data = Data()
    data.append(BinaryKind.userBroadcastPush.rawValue)
    data.append(UInt8(joinRefBytes.count))
    data.append(UInt8(refBytes.count))
    data.append(UInt8(topicBytes.count))
    data.append(UInt8(eventBytes.count))
    data.append(UInt8(metaBytes.count))
    data.append(encoding.rawValue)
    data.append(joinRefBytes)
    data.append(refBytes)
    data.append(topicBytes)
    data.append(eventBytes)
    data.append(metaBytes)
    data.append(payload)

    return data
  }

  // MARK: - Binary decoding (type 0x04 - server -> client)

  /// Decodes a binary frame (type 0x04) into a ``DecodedBroadcast``.
  ///
  /// Binary frame format:
  /// ```
  /// [kind:1][topic_len:1][event_len:1][meta_len:1][encoding:1]
  /// [topic][event][metadata][payload]
  /// ```
  func decodeBinary(_ data: Data) throws -> DecodedBroadcast {
    guard data.count >= 5 else {
      throw RealtimeError("Binary frame too short: \(data.count) bytes.")
    }

    let kind = data[data.startIndex]
    guard kind == BinaryKind.userBroadcast.rawValue else {
      throw RealtimeError(
        "Unexpected binary frame kind: \(kind), expected \(BinaryKind.userBroadcast.rawValue)."
      )
    }

    let topicLen = Int(data[data.startIndex + 1])
    let eventLen = Int(data[data.startIndex + 2])
    let metaLen = Int(data[data.startIndex + 3])
    let encodingByte = data[data.startIndex + 4]

    guard let encoding = PayloadEncoding(rawValue: encodingByte) else {
      throw RealtimeError("Unknown payload encoding: \(encodingByte).")
    }

    let headerSize = 5
    let expectedMinSize = headerSize + topicLen + eventLen + metaLen
    guard data.count >= expectedMinSize else {
      throw RealtimeError(
        "Binary frame too short for declared field lengths."
      )
    }

    var offset = data.startIndex + headerSize

    let topicData = data[offset..<(offset + topicLen)]
    offset += topicLen

    let eventData = data[offset..<(offset + eventLen)]
    offset += eventLen

    // Skip metadata for now.
    offset += metaLen

    let payloadData = data[offset...]

    guard let topic = String(data: topicData, encoding: .utf8) else {
      throw RealtimeError("Failed to decode topic as UTF-8.")
    }
    guard let event = String(data: eventData, encoding: .utf8) else {
      throw RealtimeError("Failed to decode event as UTF-8.")
    }

    let payload: DecodedBroadcast.Payload
    switch encoding {
    case .json:
      let jsonObject = try JSONDecoder().decode(JSONObject.self, from: Data(payloadData))
      payload = .json(jsonObject)
    case .binary:
      payload = .binary(Data(payloadData))
    }

    return DecodedBroadcast(
      topic: topic,
      event: event,
      payload: payload
    )
  }
}
