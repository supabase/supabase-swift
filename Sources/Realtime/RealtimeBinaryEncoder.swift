//
//  RealtimeBinaryEncoder.swift
//
//
//  Created by Guilherme Souza on 05/12/24.
//

import Foundation

/// Binary encoder for Realtime V2 messages.
///
/// Supports encoding messages with:
/// - Binary payloads
/// - User broadcast messages with metadata
/// - Reduced JSON encoding overhead
final class RealtimeBinaryEncoder: Sendable {
  private let headerLength = 1
  private let metaLength = 4
  private let userBroadcastPushMetaLength = 6

  enum MessageKind: UInt8 {
    case push = 0
    case reply = 1
    case broadcast = 2
    case userBroadcastPush = 3
    case userBroadcast = 4
  }

  enum PayloadEncoding: UInt8 {
    case binary = 0
    case json = 1
  }

  private let allowedMetadataKeys: [String]

  init(allowedMetadataKeys: [String] = []) {
    self.allowedMetadataKeys = allowedMetadataKeys
  }

  /// Encodes a Realtime message to binary format.
  /// - Parameter message: The message to encode
  /// - Returns: Binary data representation
  func encode(_ message: RealtimeMessageV2) throws -> Data {
    // Check if this is a user broadcast push
    if message.event == "broadcast",
      let event = message.payload["event"]?.stringValue
    {
      return try encodeUserBroadcastPush(message: message, userEvent: event)
    }

    // Check if this has a binary payload at top level
    if let binaryPayload = getBinaryPayload(from: message.payload) {
      return try encodePush(message: message, binaryPayload: binaryPayload)
    }

    // Fall back to JSON encoding
    return try encodeAsJSON(message)
  }

  // MARK: - Private Encoding Methods

  private func encodePush(message: RealtimeMessageV2, binaryPayload: Data) throws -> Data {
    let joinRef = message.joinRef ?? ""
    let ref = message.ref ?? ""
    let topic = message.topic
    let event = message.event

    try validateFieldLength(joinRef, name: "joinRef")
    try validateFieldLength(ref, name: "ref")
    try validateFieldLength(topic, name: "topic")
    try validateFieldLength(event, name: "event")

    let metaLength =
      self.metaLength + joinRef.utf8.count + ref.utf8.count + topic.utf8.count + event.utf8.count

    var header = Data(capacity: headerLength + metaLength)

    header.append(MessageKind.push.rawValue)
    header.append(UInt8(joinRef.utf8.count))
    header.append(UInt8(ref.utf8.count))
    header.append(UInt8(topic.utf8.count))
    header.append(UInt8(event.utf8.count))
    header.append(contentsOf: joinRef.utf8)
    header.append(contentsOf: ref.utf8)
    header.append(contentsOf: topic.utf8)
    header.append(contentsOf: event.utf8)

    var combined = header
    combined.append(binaryPayload)
    return combined
  }

  private func encodeUserBroadcastPush(
    message: RealtimeMessageV2,
    userEvent: String
  ) throws -> Data {
    let joinRef = message.joinRef ?? ""
    let ref = message.ref ?? ""
    let topic = message.topic

    // Extract the payload
    let payload = message.payload["payload"] ?? .null

    // Encode payload
    let encodedPayload: Data
    let encoding: PayloadEncoding

    if let binaryData = getBinaryPayload(from: ["payload": payload]) {
      encodedPayload = binaryData
      encoding = .binary
    } else {
      encodedPayload = try JSONSerialization.data(withJSONObject: payload.value, options: [])
      encoding = .json
    }

    // Extract metadata based on allowed keys
    let metadata: JSONObject
    if !allowedMetadataKeys.isEmpty {
      metadata = message.payload.filter { key, _ in
        allowedMetadataKeys.contains(key) && key != "event" && key != "payload" && key != "type"
      }
    } else {
      metadata = [:]
    }

    let metadataString: String
    if !metadata.isEmpty {
      let metadataData = try JSONSerialization.data(
        withJSONObject: metadata.mapValues(\.value),
        options: []
      )
      metadataString = String(data: metadataData, encoding: .utf8) ?? ""
    } else {
      metadataString = ""
    }

    // Validate lengths
    try validateFieldLength(joinRef, name: "joinRef")
    try validateFieldLength(ref, name: "ref")
    try validateFieldLength(topic, name: "topic")
    try validateFieldLength(userEvent, name: "userEvent")
    try validateFieldLength(metadataString, name: "metadata")

    let metaLength =
      userBroadcastPushMetaLength + joinRef.utf8.count + ref.utf8.count + topic.utf8.count
      + userEvent.utf8.count + metadataString.utf8.count

    var header = Data(capacity: headerLength + metaLength)

    header.append(MessageKind.userBroadcastPush.rawValue)
    header.append(UInt8(joinRef.utf8.count))
    header.append(UInt8(ref.utf8.count))
    header.append(UInt8(topic.utf8.count))
    header.append(UInt8(userEvent.utf8.count))
    header.append(UInt8(metadataString.utf8.count))
    header.append(encoding.rawValue)
    header.append(contentsOf: joinRef.utf8)
    header.append(contentsOf: ref.utf8)
    header.append(contentsOf: topic.utf8)
    header.append(contentsOf: userEvent.utf8)
    header.append(contentsOf: metadataString.utf8)

    var combined = header
    combined.append(encodedPayload)
    return combined
  }

  private func encodeAsJSON(_ message: RealtimeMessageV2) throws -> Data {
    try JSONEncoder().encode(message)
  }

  // MARK: - Helper Methods

  private func getBinaryPayload(from payload: JSONObject) -> Data? {
    // Check if there's a "payload" key with base64-encoded binary data marker
    guard let payloadValue = payload["payload"],
      case .object(let obj) = payloadValue,
      let isBinary = obj["__binary__"]?.boolValue,
      isBinary,
      let base64String = obj["data"]?.stringValue,
      let data = Data(base64Encoded: base64String)
    else {
      return nil
    }
    return data
  }

  private func validateFieldLength(_ field: String, name: String) throws {
    let length = field.utf8.count
    guard length <= 255 else {
      throw RealtimeError("\(name) length \(length) exceeds maximum of 255")
    }
  }
}
