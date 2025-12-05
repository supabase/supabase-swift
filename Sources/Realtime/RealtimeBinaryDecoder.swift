//
//  RealtimeBinaryDecoder.swift
//
//
//  Created by Guilherme Souza on 05/12/24.
//

import Foundation

/// Binary decoder for Realtime V2 messages.
///
/// Supports decoding messages with:
/// - Binary payloads
/// - User broadcast messages with metadata
/// - Push, reply, broadcast, and user broadcast message types
final class RealtimeBinaryDecoder: Sendable {
  private let headerLength = 1
  private let metaLength = 4

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

  /// Decodes binary data into a Realtime message.
  /// - Parameter data: Binary data to decode
  /// - Returns: Decoded message
  func decode(_ data: Data) throws -> RealtimeMessageV2 {
    guard !data.isEmpty else {
      throw RealtimeError("Empty binary data")
    }

    let kind = data[0]

    guard let messageKind = MessageKind(rawValue: kind) else {
      throw RealtimeError("Unknown message kind: \(kind)")
    }

    switch messageKind {
    case .push:
      return try decodePush(data)
    case .reply:
      return try decodeReply(data)
    case .broadcast:
      return try decodeBroadcast(data)
    case .userBroadcast:
      return try decodeUserBroadcast(data)
    case .userBroadcastPush:
      throw RealtimeError("userBroadcastPush should not be received from server")
    }
  }

  // MARK: - Private Decoding Methods

  private func decodePush(_ data: Data) throws -> RealtimeMessageV2 {
    guard data.count >= headerLength + metaLength - 1 else {
      throw RealtimeError("Invalid push message length")
    }

    let joinRefSize = Int(data[1])
    let topicSize = Int(data[2])
    let eventSize = Int(data[3])

    var offset = headerLength + metaLength - 1  // pushes have no ref

    let joinRef = try decodeString(from: data, offset: offset, length: joinRefSize)
    offset += joinRefSize

    let topic = try decodeString(from: data, offset: offset, length: topicSize)
    offset += topicSize

    let event = try decodeString(from: data, offset: offset, length: eventSize)
    offset += eventSize

    let payloadData = data.subdata(in: offset..<data.count)
    let payload = try JSONSerialization.jsonObject(with: payloadData, options: [])
    let jsonPayload = try AnyJSON(value: payload).objectValue ?? [:]

    return RealtimeMessageV2(
      joinRef: joinRef,
      ref: nil,
      topic: topic,
      event: event,
      payload: jsonPayload
    )
  }

  private func decodeReply(_ data: Data) throws -> RealtimeMessageV2 {
    guard data.count >= headerLength + metaLength else {
      throw RealtimeError("Invalid reply message length")
    }

    let joinRefSize = Int(data[1])
    let refSize = Int(data[2])
    let topicSize = Int(data[3])
    let eventSize = Int(data[4])

    var offset = headerLength + metaLength

    let joinRef = try decodeString(from: data, offset: offset, length: joinRefSize)
    offset += joinRefSize

    let ref = try decodeString(from: data, offset: offset, length: refSize)
    offset += refSize

    let topic = try decodeString(from: data, offset: offset, length: topicSize)
    offset += topicSize

    let event = try decodeString(from: data, offset: offset, length: eventSize)
    offset += eventSize

    let responseData = data.subdata(in: offset..<data.count)
    let response = try JSONSerialization.jsonObject(with: responseData, options: [])
    let jsonResponse = try AnyJSON(value: response)

    // Reply messages have status in the event field and response in payload
    let payload: JSONObject = [
      "status": .string(event),
      "response": jsonResponse,
    ]

    return RealtimeMessageV2(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: "phx_reply",
      payload: payload
    )
  }

  private func decodeBroadcast(_ data: Data) throws -> RealtimeMessageV2 {
    guard data.count >= headerLength + 2 else {
      throw RealtimeError("Invalid broadcast message length")
    }

    let topicSize = Int(data[1])
    let eventSize = Int(data[2])

    var offset = headerLength + 2

    let topic = try decodeString(from: data, offset: offset, length: topicSize)
    offset += topicSize

    let event = try decodeString(from: data, offset: offset, length: eventSize)
    offset += eventSize

    let payloadData = data.subdata(in: offset..<data.count)
    let payload = try JSONSerialization.jsonObject(with: payloadData, options: [])
    let jsonPayload = try AnyJSON(value: payload).objectValue ?? [:]

    return RealtimeMessageV2(
      joinRef: nil,
      ref: nil,
      topic: topic,
      event: event,
      payload: jsonPayload
    )
  }

  private func decodeUserBroadcast(_ data: Data) throws -> RealtimeMessageV2 {
    guard data.count >= headerLength + 4 else {
      throw RealtimeError("Invalid user broadcast message length")
    }

    let topicSize = Int(data[1])
    let userEventSize = Int(data[2])
    let metadataSize = Int(data[3])
    let payloadEncoding = data[4]

    var offset = headerLength + 4

    let topic = try decodeString(from: data, offset: offset, length: topicSize)
    offset += topicSize

    let userEvent = try decodeString(from: data, offset: offset, length: userEventSize)
    offset += userEventSize

    let metadata = try decodeString(from: data, offset: offset, length: metadataSize)
    offset += metadataSize

    let payloadData = data.subdata(in: offset..<data.count)

    var payload: JSONObject = [
      "type": .string("broadcast"),
      "event": .string(userEvent),
    ]

    // Decode payload based on encoding type
    if payloadEncoding == PayloadEncoding.json.rawValue {
      let jsonPayload = try JSONSerialization.jsonObject(with: payloadData, options: [])
      payload["payload"] = try AnyJSON(value: jsonPayload)
    } else {
      // Binary payload - store as a special marker object with base64-encoded data
      payload["payload"] = .object([
        "__binary__": .bool(true),
        "data": .string(payloadData.base64EncodedString()),
      ])
    }

    // Add metadata if present
    if !metadata.isEmpty, let metadataData = metadata.data(using: .utf8) {
      let metaObject = try JSONSerialization.jsonObject(with: metadataData, options: [])
      payload["meta"] = try AnyJSON(value: metaObject)
    }

    return RealtimeMessageV2(
      joinRef: nil,
      ref: nil,
      topic: topic,
      event: "broadcast",
      payload: payload
    )
  }

  // MARK: - Helper Methods

  private func decodeString(from data: Data, offset: Int, length: Int) throws -> String {
    guard offset + length <= data.count else {
      throw RealtimeError("Invalid string offset/length")
    }

    let stringData = data.subdata(in: offset..<(offset + length))
    guard let string = String(data: stringData, encoding: .utf8) else {
      throw RealtimeError("Failed to decode string")
    }
    return string
  }
}

// MARK: - AnyJSON Extensions for Binary Support

extension AnyJSON {
  /// Creates an AnyJSON value from a Swift value.
  init(value: Any) throws {
    if let dict = value as? [String: Any] {
      var object: JSONObject = [:]
      for (key, val) in dict {
        object[key] = try AnyJSON(value: val)
      }
      self = .object(object)
    } else if let array = value as? [Any] {
      self = .array(try array.map { try AnyJSON(value: $0) })
    } else if let string = value as? String {
      self = .string(string)
    } else if let bool = value as? Bool {
      // Bool must be checked before Int because Bool can be cast to Int
      self = .bool(bool)
    } else if let int = value as? Int {
      self = .integer(int)
    } else if let double = value as? Double {
      self = .double(double)
    } else if value is NSNull {
      self = .null
    } else {
      throw RealtimeError("Unsupported JSON value type: \(type(of: value))")
    }
  }
}
