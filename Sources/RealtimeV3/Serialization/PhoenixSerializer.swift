//
//  PhoenixSerializer.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Foundation
import Helpers

/// Handles encoding/decoding between `PhoenixMessage` and the Phoenix protocol 2.0.0 wire format.
///
/// Text frames use a JSON array format: `[joinRef, ref, topic, event, payload]`.
struct PhoenixSerializer: Sendable {

  // MARK: - Text encoding (JSON array format)

  /// Encodes a Phoenix message as a JSON array string: `[joinRef, ref, topic, event, payload]`.
  func encodeText(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    payload: JSONObject
  ) throws -> String {
    let array: [AnyJSON] = [
      joinRef.map { .string($0) } ?? .null,
      ref.map { .string($0) } ?? .null,
      .string(topic),
      .string(event),
      .object(payload),
    ]

    let data: Data
    do {
      data = try JSONEncoder().encode(array)
    } catch {
      throw RealtimeError.encoding(underlying: error)
    }

    guard let text = String(data: data, encoding: .utf8) else {
      struct UTF8EncodingError: Error & Sendable {
        let message = "Failed to encode message as UTF-8 string."
      }
      throw RealtimeError.encoding(underlying: UTF8EncodingError())
    }
    return text
  }

  // MARK: - Binary encoding (type 0x03 - client -> server)

  /// Byte value for the binary frame kind field.
  private enum BinaryKind: UInt8 {
    /// Client -> server broadcast push.
    case userBroadcastPush = 3
    /// Server -> client broadcast.
    case userBroadcast = 4
  }

  /// Indicates whether the binary frame payload is raw bytes or JSON-encoded.
  private enum PayloadEncoding: UInt8 {
    case binary = 0
    case json = 1
  }

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
    let payloadData: Data
    do {
      payloadData = try JSONEncoder().encode(jsonPayload)
    } catch {
      throw RealtimeError.encoding(underlying: error)
    }
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
    struct OversizedHeaderField: Error & Sendable {
      let message = "Binary frame header fields must not exceed 255 bytes each."
    }

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
      throw RealtimeError.encoding(underlying: OversizedHeaderField())
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

  /// Decodes a binary frame (type 0x04) into a `PhoenixMessage`.
  ///
  /// Binary frame format:
  /// ```
  /// [kind:1][topic_len:1][event_len:1][meta_len:1][encoding:1]
  /// [topic][event][metadata][payload]
  /// ```
  ///
  /// The returned message always has `event = "broadcast"`, `joinRef = nil`, and `ref = nil`.
  func decodeBinary(_ data: Data, receivedAt: Date) throws -> PhoenixMessage {
    struct StructuralError: Error & Sendable {
      let message: String
    }

    guard data.count >= 5 else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Binary frame too short: \(data.count) bytes.")
      )
    }

    let kind = data[data.startIndex]
    guard kind == BinaryKind.userBroadcast.rawValue else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(
          message:
            "Unexpected binary frame kind: \(kind), expected \(BinaryKind.userBroadcast.rawValue)."
        )
      )
    }

    let topicLen = Int(data[data.startIndex + 1])
    let eventLen = Int(data[data.startIndex + 2])
    let metaLen = Int(data[data.startIndex + 3])
    let encodingByte = data[data.startIndex + 4]

    guard let encoding = PayloadEncoding(rawValue: encodingByte) else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Unknown payload encoding: \(encodingByte).")
      )
    }

    let headerSize = 5
    let expectedMinSize = headerSize + topicLen + eventLen + metaLen
    guard data.count >= expectedMinSize else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Binary frame too short for declared field lengths.")
      )
    }

    var offset = data.startIndex + headerSize

    let topicData = data[offset..<(offset + topicLen)]
    offset += topicLen

    // Ignore the user-facing event field from the frame; the Phoenix event for all binary
    // broadcast frames is "broadcast".
    offset += eventLen

    // Skip metadata for now.
    offset += metaLen

    let payloadData = data[offset...]

    guard let topic = String(data: topicData, encoding: .utf8) else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Failed to decode topic as UTF-8.")
      )
    }

    let payload: PhoenixPayload
    switch encoding {
    case .json:
      do {
        let jsonObject = try JSONDecoder().decode(JSONObject.self, from: Data(payloadData))
        payload = .json(.object(jsonObject))
      } catch {
        throw RealtimeError.decoding(type: "PhoenixMessage", underlying: error)
      }
    case .binary:
      payload = .binary(Data(payloadData))
    }

    return PhoenixMessage(
      joinRef: nil,
      ref: nil,
      topic: topic,
      event: .broadcast,
      payload: payload,
      receivedAt: receivedAt
    )
  }

  // MARK: - Text decoding (JSON array format)

  /// Decodes a JSON array string `[joinRef, ref, topic, event, payload]` into a `PhoenixMessage`.
  func decodeText(_ text: String, receivedAt: Date) throws -> PhoenixMessage {
    struct StructuralError: Error & Sendable {
      let message: String
    }

    let data = Data(text.utf8)
    let array: [AnyJSON]
    do {
      array = try JSONDecoder().decode([AnyJSON].self, from: data)
    } catch {
      throw RealtimeError.decoding(type: "PhoenixMessage", underlying: error)
    }

    guard array.count >= 5 else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(
          message: "Expected JSON array with 5 elements, got \(array.count)."
        )
      )
    }

    let joinRef = array[0].stringValue
    let ref = array[1].stringValue

    guard let topic = array[2].stringValue else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Expected string for topic at index 2.")
      )
    }
    guard let eventString = array[3].stringValue else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Expected string for event at index 3.")
      )
    }
    guard let payloadObject = array[4].objectValue else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: StructuralError(message: "Expected object for payload at index 4.")
      )
    }

    return PhoenixMessage(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: PhoenixEvent(rawValue: eventString),
      payload: .json(.object(payloadObject)),
      receivedAt: receivedAt
    )
  }
}
