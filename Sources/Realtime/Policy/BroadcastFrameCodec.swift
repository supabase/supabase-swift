//
//  BroadcastFrameCodec.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

package import Foundation
package import Helpers

/// Represents a decoded binary broadcast message from the server.
package struct DecodedBroadcast: Sendable {
  package let topic: String
  /// The user event name extracted from the binary frame.
  package let event: String
  /// The frame's metadata object, e.g. `id` and `replayed` on database-originated broadcasts.
  package var meta: JSONObject? = nil
  package let payload: Payload

  package enum Payload: Sendable {
    case json(JSONObject)
    case binary(Data)
  }
}

package enum BroadcastFrameCodec {
  package enum BinaryKind: UInt8 {
    /// Client -> server broadcast push.
    case userBroadcastPush = 3
    /// Server -> client broadcast.
    case userBroadcast = 4
  }

  package enum PayloadEncoding: UInt8 {
    case binary = 0
    case json = 1
  }

  /// Encodes a broadcast push as a kind 3 frame with a JSON payload.
  ///
  /// Binary frame format:
  /// ```
  /// [kind:1][joinRef_len:1][ref_len:1][topic_len:1][event_len:1][meta_len:1][encoding:1]
  /// [joinRef][ref][topic][event][metadata][payload]
  /// ```
  package static func encodePush(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    jsonPayload: JSONObject
  ) throws -> Data {
    try encodePush(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      encoding: .json,
      payload: JSONEncoder().encode(jsonPayload)
    )
  }

  /// Encodes a broadcast push as a kind 3 frame with a binary payload.
  package static func encodePush(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    binaryPayload: Data
  ) throws -> Data {
    try encodePush(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      encoding: .binary,
      payload: binaryPayload
    )
  }

  private static func encodePush(
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
    let metaBytes = Data()

    guard joinRefBytes.count <= 255,
      refBytes.count <= 255,
      topicBytes.count <= 255,
      eventBytes.count <= 255,
      metaBytes.count <= 255
    else {
      throw RealtimeError.encoding(
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

  /// Writes `joinRef` and `ref` into a kind 3 frame made by ``encodePush(joinRef:ref:topic:event:jsonPayload:)``
  /// or ``encodePush(joinRef:ref:topic:event:binaryPayload:)``, replacing the refs it holds.
  ///
  /// A channel makes the frame before the socket mints its refs, so the socket's codec stamps them.
  package static func stamp(_ frame: Data, joinRef: String?, ref: String?) throws -> Data {
    let bytes = [UInt8](frame)
    let headerSize = 7
    guard bytes.count >= headerSize, bytes[0] == BinaryKind.userBroadcastPush.rawValue,
      let encoding = PayloadEncoding(rawValue: bytes[6]), bytes[5] == 0
    else {
      throw RealtimeError.encoding("Not a kind 3 frame with empty metadata.")
    }
    let topicStart = headerSize + Int(bytes[1]) + Int(bytes[2])
    let eventStart = topicStart + Int(bytes[3])
    let payloadStart = eventStart + Int(bytes[4])
    guard payloadStart <= bytes.count,
      let topic = String(bytes: bytes[topicStart..<eventStart], encoding: .utf8),
      let event = String(bytes: bytes[eventStart..<payloadStart], encoding: .utf8)
    else {
      throw RealtimeError.encoding("Kind 3 frame is truncated.")
    }
    return try encodePush(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      encoding: encoding,
      payload: Data(bytes[payloadStart...])
    )
  }

  /// Decodes a kind 4 frame into a ``DecodedBroadcast``.
  ///
  /// Binary frame format:
  /// ```
  /// [kind:1][topic_len:1][event_len:1][meta_len:1][encoding:1]
  /// [topic][event][metadata][payload]
  /// ```
  package static func decode(_ data: Data) throws -> DecodedBroadcast {
    guard data.count >= 5 else {
      throw RealtimeError.decoding("Binary frame too short: \(data.count) bytes.")
    }

    let kind = data[data.startIndex]
    guard kind == BinaryKind.userBroadcast.rawValue else {
      throw RealtimeError.decoding(
        "Unexpected binary frame kind: \(kind), expected \(BinaryKind.userBroadcast.rawValue)."
      )
    }

    let topicLen = Int(data[data.startIndex + 1])
    let eventLen = Int(data[data.startIndex + 2])
    let metaLen = Int(data[data.startIndex + 3])
    let encodingByte = data[data.startIndex + 4]

    guard let encoding = PayloadEncoding(rawValue: encodingByte) else {
      throw RealtimeError.decoding("Unknown payload encoding: \(encodingByte).")
    }

    let headerSize = 5
    let expectedMinSize = headerSize + topicLen + eventLen + metaLen
    guard data.count >= expectedMinSize else {
      throw RealtimeError.decoding(
        "Binary frame too short for declared field lengths."
      )
    }

    var offset = data.startIndex + headerSize

    let topicData = data[offset..<(offset + topicLen)]
    offset += topicLen

    let eventData = data[offset..<(offset + eventLen)]
    offset += eventLen

    let metaData = data[offset..<(offset + metaLen)]
    offset += metaLen

    let payloadData = data[offset...]

    guard let topic = String(data: topicData, encoding: .utf8) else {
      throw RealtimeError.decoding("Failed to decode topic as UTF-8.")
    }
    guard let event = String(data: eventData, encoding: .utf8) else {
      throw RealtimeError.decoding("Failed to decode event as UTF-8.")
    }

    let meta = metaLen > 0 ? try JSONDecoder().decode(JSONObject.self, from: Data(metaData)) : nil

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
      meta: meta,
      payload: payload
    )
  }
}
