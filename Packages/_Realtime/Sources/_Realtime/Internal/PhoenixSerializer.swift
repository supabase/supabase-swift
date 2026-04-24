//
//  PhoenixSerializer.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/26.
//

import Foundation

enum PhoenixSerializer {
  enum BinaryKind: UInt8 {
    case clientBroadcastPush = 3
    case serverBroadcast = 4
  }
  enum PayloadEncoding: UInt8 {
    case binary = 0
    case json = 1
  }

  // MARK: Text encode/decode

  static func encodeText(_ msg: PhoenixMessage) throws -> String {
    let array: [JSONValue] = [
      msg.joinRef.map { .string($0) } ?? .null,
      msg.ref.map { .string($0) } ?? .null,
      .string(msg.topic),
      .string(msg.event),
      .object(msg.payload),
    ]
    let data = try JSONEncoder().encode(array)
    guard let text = String(data: data, encoding: .utf8) else {
      throw RealtimeError.encoding(
        underlying: EncodingError.invalidValue(
          array,
          .init(codingPath: [], debugDescription: "UTF-8 conversion failed")
        )
      )
    }
    return text
  }

  static func decodeText(_ text: String) throws -> PhoenixMessage {
    let data = Data(text.utf8)
    let array = try JSONDecoder().decode([JSONValue].self, from: data)
    guard array.count >= 5 else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "Expected 5-element array, got \(array.count)")
        )
      )
    }
    let joinRef: String? = if case .string(let s) = array[0] { s } else { nil }
    let ref: String?     = if case .string(let s) = array[1] { s } else { nil }
    guard case .string(let topic)   = array[2],
          case .string(let event)   = array[3],
          case .object(let payload) = array[4]
    else {
      throw RealtimeError.decoding(
        type: "PhoenixMessage",
        underlying: DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "Unexpected element types in Phoenix array")
        )
      )
    }
    return PhoenixMessage(joinRef: joinRef, ref: ref, topic: topic, event: event, payload: payload)
  }

  // MARK: Binary decode (server->client, type 0x04)

  static func decodeBinary(_ data: Data) throws -> BinaryBroadcast {
    guard data.count >= 5 else {
      throw RealtimeError.decoding(
        type: "BinaryBroadcast",
        underlying: DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "Binary frame too short: \(data.count)")
        )
      )
    }
    let kind = data[data.startIndex]
    guard kind == BinaryKind.serverBroadcast.rawValue else {
      throw RealtimeError.decoding(
        type: "BinaryBroadcast",
        underlying: DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "Unexpected kind byte: \(kind)")
        )
      )
    }
    let topicLen = Int(data[data.startIndex + 1])
    let eventLen = Int(data[data.startIndex + 2])
    let metaLen  = Int(data[data.startIndex + 3])
    let encByte  = data[data.startIndex + 4]
    guard let encoding = PayloadEncoding(rawValue: encByte) else {
      throw RealtimeError.decoding(
        type: "BinaryBroadcast",
        underlying: DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "Unknown encoding byte: \(encByte)")
        )
      )
    }
    let headerSize = 5
    guard data.count >= headerSize + topicLen + eventLen + metaLen else {
      throw RealtimeError.decoding(
        type: "BinaryBroadcast",
        underlying: DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "Frame too short for declared field lengths")
        )
      )
    }
    var offset = data.startIndex + headerSize
    let topicData = data[offset..<(offset + topicLen)]; offset += topicLen
    let eventData = data[offset..<(offset + eventLen)]; offset += eventLen
    offset += metaLen
    let payloadData = data[offset...]
    guard let topic = String(data: topicData, encoding: .utf8),
          let event = String(data: eventData, encoding: .utf8) else {
      throw RealtimeError.decoding(
        type: "BinaryBroadcast",
        underlying: DecodingError.dataCorrupted(
          .init(codingPath: [], debugDescription: "UTF-8 decode failure in topic or event")
        )
      )
    }
    let payload: BinaryBroadcast.Payload
    switch encoding {
    case .json:
      let obj = try JSONDecoder().decode([String: JSONValue].self, from: Data(payloadData))
      payload = .json(obj)
    case .binary:
      payload = .binary(Data(payloadData))
    }
    return BinaryBroadcast(topic: topic, event: event, payload: payload)
  }

  // MARK: Binary encode (client->server, type 0x03)

  static func encodeBroadcastPush(
    joinRef: String?, ref: String?,
    topic: String, event: String,
    payload: [String: JSONValue]
  ) throws -> Data {
    let payloadData = try JSONEncoder().encode(payload)
    return try _encodePush(
      joinRef: joinRef, ref: ref, topic: topic, event: event,
      encoding: .json, payload: payloadData
    )
  }

  static func encodeBroadcastPush(
    joinRef: String?, ref: String?,
    topic: String, event: String,
    binaryPayload: Data
  ) throws -> Data {
    try _encodePush(
      joinRef: joinRef, ref: ref, topic: topic, event: event,
      encoding: .binary, payload: binaryPayload
    )
  }

  private static func _encodePush(
    joinRef: String?, ref: String?,
    topic: String, event: String,
    encoding: PayloadEncoding, payload: Data
  ) throws -> Data {
    let jrBytes = Data((joinRef ?? "").utf8)
    let rBytes  = Data((ref ?? "").utf8)
    let tBytes  = Data(topic.utf8)
    let eBytes  = Data(event.utf8)
    guard jrBytes.count <= 255 else {
      throw RealtimeError.encoding(underlying: EncodingError.invalidValue(joinRef ?? "", .init(codingPath: [], debugDescription: "joinRef exceeds 255 bytes (\(jrBytes.count))")))
    }
    guard rBytes.count <= 255 else {
      throw RealtimeError.encoding(underlying: EncodingError.invalidValue(ref ?? "", .init(codingPath: [], debugDescription: "ref exceeds 255 bytes (\(rBytes.count))")))
    }
    guard tBytes.count <= 255 else {
      throw RealtimeError.encoding(underlying: EncodingError.invalidValue(topic, .init(codingPath: [], debugDescription: "topic exceeds 255 bytes (\(tBytes.count))")))
    }
    guard eBytes.count <= 255 else {
      throw RealtimeError.encoding(underlying: EncodingError.invalidValue(event, .init(codingPath: [], debugDescription: "event exceeds 255 bytes (\(eBytes.count))")))
    }
    var out = Data()
    out.append(BinaryKind.clientBroadcastPush.rawValue)
    out.append(UInt8(jrBytes.count))
    out.append(UInt8(rBytes.count))
    out.append(UInt8(tBytes.count))
    out.append(UInt8(eBytes.count))
    out.append(0x00)               // meta_len = 0
    out.append(encoding.rawValue)
    out.append(jrBytes); out.append(rBytes); out.append(tBytes); out.append(eBytes)
    out.append(payload)
    return out
  }
}
