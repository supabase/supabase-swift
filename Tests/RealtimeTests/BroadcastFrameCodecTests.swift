//
//  BroadcastFrameCodecTests.swift
//
//
//  Created by Guilherme Souza on 12/02/26.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct BroadcastFrameCodecTests {
  @Test
  func encodeBroadcastPush_jsonPayload() throws {
    let data = try BroadcastFrameCodec.encodePush(
      joinRef: "1",
      ref: "2",
      topic: "realtime:test",
      event: "my_event",
      jsonPayload: ["hello": "world"]
    )

    let topicLen = "realtime:test".utf8.count
    let eventLen = "my_event".utf8.count
    #expect(data[0] == BroadcastFrameCodec.BinaryKind.userBroadcastPush.rawValue)
    #expect(data[1] == 1)
    #expect(data[2] == 1)
    #expect(data[3] == UInt8(topicLen))
    #expect(data[4] == UInt8(eventLen))
    #expect(data[5] == 0)
    #expect(data[6] == BroadcastFrameCodec.PayloadEncoding.json.rawValue)

    let headerSize = 7
    let joinRefStart = headerSize
    let refStart = joinRefStart + 1
    let topicStart = refStart + 1
    let eventStart = topicStart + topicLen
    let payloadStart = eventStart + eventLen

    #expect(String(data: data[joinRefStart..<refStart], encoding: .utf8) == "1")
    #expect(String(data: data[refStart..<topicStart], encoding: .utf8) == "2")
    #expect(String(data: data[topicStart..<eventStart], encoding: .utf8) == "realtime:test")
    #expect(String(data: data[eventStart..<payloadStart], encoding: .utf8) == "my_event")

    let payloadData = data[payloadStart...]
    let json = try JSONDecoder().decode(JSONObject.self, from: Data(payloadData))
    #expect(json["hello"]?.stringValue == "world")
  }

  @Test
  func encodeBroadcastPush_binaryPayload() throws {
    let binaryPayload = Data([0x01, 0x02, 0x03, 0xFF])
    let data = try BroadcastFrameCodec.encodePush(
      joinRef: nil,
      ref: nil,
      topic: "realtime:test",
      event: "bin_event",
      binaryPayload: binaryPayload
    )

    #expect(data[0] == BroadcastFrameCodec.BinaryKind.userBroadcastPush.rawValue)
    #expect(data[1] == 0)
    #expect(data[2] == 0)
    #expect(data[6] == BroadcastFrameCodec.PayloadEncoding.binary.rawValue)

    let headerSize = 7
    let topicLen = Int(data[3])
    let eventLen = Int(data[4])
    let metaLen = Int(data[5])
    let payloadStart = headerSize + 0 + 0 + topicLen + eventLen + metaLen
    let extractedPayload = Data(data[payloadStart...])

    #expect(extractedPayload == binaryPayload)
  }

  @Test
  func encodeBroadcastPush_nilRefs() throws {
    let data = try BroadcastFrameCodec.encodePush(
      joinRef: nil,
      ref: nil,
      topic: "t",
      event: "e",
      jsonPayload: [:]
    )

    #expect(data[1] == 0)
    #expect(data[2] == 0)
  }

  @Test
  func decodeBinary_jsonPayload() throws {
    let topic = "realtime:test"
    let event = "my_event"
    let jsonPayload: JSONObject = ["count": .integer(42)]
    let payloadData = try JSONEncoder().encode(jsonPayload)

    let topicBytes = Data(topic.utf8)
    let eventBytes = Data(event.utf8)

    var frame = Data()
    frame.append(BroadcastFrameCodec.BinaryKind.userBroadcast.rawValue)
    frame.append(UInt8(topicBytes.count))
    frame.append(UInt8(eventBytes.count))
    frame.append(0)
    frame.append(BroadcastFrameCodec.PayloadEncoding.json.rawValue)
    frame.append(topicBytes)
    frame.append(eventBytes)
    frame.append(payloadData)

    let broadcast = try BroadcastFrameCodec.decode(frame)
    #expect(broadcast.topic == "realtime:test")
    #expect(broadcast.event == "my_event")
    if case .json(let json) = broadcast.payload {
      #expect(json["count"]?.intValue == 42)
    } else {
      Issue.record("Expected JSON payload")
    }
  }

  @Test
  func decodeBinary_binaryPayload() throws {
    let topic = "realtime:test"
    let event = "bin"
    let binaryPayload = Data([0xDE, 0xAD, 0xBE, 0xEF])

    let topicBytes = Data(topic.utf8)
    let eventBytes = Data(event.utf8)

    var frame = Data()
    frame.append(BroadcastFrameCodec.BinaryKind.userBroadcast.rawValue)
    frame.append(UInt8(topicBytes.count))
    frame.append(UInt8(eventBytes.count))
    frame.append(0)
    frame.append(BroadcastFrameCodec.PayloadEncoding.binary.rawValue)
    frame.append(topicBytes)
    frame.append(eventBytes)
    frame.append(binaryPayload)

    let broadcast = try BroadcastFrameCodec.decode(frame)
    #expect(broadcast.topic == "realtime:test")
    #expect(broadcast.event == "bin")
    if case .binary(let data) = broadcast.payload {
      #expect(data == binaryPayload)
    } else {
      Issue.record("Expected binary payload")
    }
  }

  @Test
  func decodeBinary_frameTooShort() {
    let data = Data([0x04, 0x01])
    #expect(throws: (any Error).self) {
      try BroadcastFrameCodec.decode(data)
    }
  }

  @Test
  func decodeBinary_wrongKind() {
    var frame = Data()
    frame.append(0x01)
    frame.append(0)
    frame.append(0)
    frame.append(0)
    frame.append(BroadcastFrameCodec.PayloadEncoding.json.rawValue)

    #expect(throws: (any Error).self) {
      try BroadcastFrameCodec.decode(frame)
    }
  }

  @Test
  func decodeBinary_unknownEncoding() {
    var frame = Data()
    frame.append(BroadcastFrameCodec.BinaryKind.userBroadcast.rawValue)
    frame.append(0)
    frame.append(0)
    frame.append(0)
    frame.append(0xFF)

    #expect(throws: (any Error).self) {
      try BroadcastFrameCodec.decode(frame)
    }
  }

  @Test
  func decodeBinary_emptyPayload() throws {
    let topic = "t"
    let event = "e"

    var frame = Data()
    frame.append(BroadcastFrameCodec.BinaryKind.userBroadcast.rawValue)
    frame.append(UInt8(topic.utf8.count))
    frame.append(UInt8(event.utf8.count))
    frame.append(0)
    frame.append(BroadcastFrameCodec.PayloadEncoding.binary.rawValue)
    frame.append(Data(topic.utf8))
    frame.append(Data(event.utf8))

    let broadcast = try BroadcastFrameCodec.decode(frame)
    if case .binary(let data) = broadcast.payload {
      #expect(data.isEmpty)
    } else {
      Issue.record("Expected binary payload")
    }
  }

  @Test
  func decodeBinary_withMetadata() throws {
    let topic = "realtime:test"
    let event = "evt"
    let metadata = Data("{\"key\":\"val\"}".utf8)
    let binaryPayload = Data([0x01])

    let topicBytes = Data(topic.utf8)
    let eventBytes = Data(event.utf8)

    var frame = Data()
    frame.append(BroadcastFrameCodec.BinaryKind.userBroadcast.rawValue)
    frame.append(UInt8(topicBytes.count))
    frame.append(UInt8(eventBytes.count))
    frame.append(UInt8(metadata.count))
    frame.append(BroadcastFrameCodec.PayloadEncoding.binary.rawValue)
    frame.append(topicBytes)
    frame.append(eventBytes)
    frame.append(metadata)
    frame.append(binaryPayload)

    let broadcast = try BroadcastFrameCodec.decode(frame)
    #expect(broadcast.topic == "realtime:test")
    #expect(broadcast.event == "evt")
    if case .binary(let data) = broadcast.payload {
      #expect(data == Data([0x01]))
    } else {
      Issue.record("Expected binary payload")
    }
  }

  enum HeaderField: CaseIterable {
    case joinRef, ref, topic, event
  }

  private func encodePush(_ field: HeaderField, value: String) throws -> Data {
    try BroadcastFrameCodec.encodePush(
      joinRef: field == .joinRef ? value : "1",
      ref: field == .ref ? value : "2",
      topic: field == .topic ? value : "realtime:test",
      event: field == .event ? value : "evt",
      jsonPayload: [:]
    )
  }

  @Test(arguments: HeaderField.allCases)
  func encodeBroadcastPushAcceptsHeaderFieldsOf255Bytes(_ field: HeaderField) throws {
    let data = try encodePush(field, value: String(repeating: "a", count: 255))
    #expect(data.contains(255))
  }

  @Test(arguments: HeaderField.allCases)
  func encodeBroadcastPushRejectsHeaderFieldsOver255BytesWithEncodingKind(_ field: HeaderField) {
    do {
      _ = try encodePush(field, value: String(repeating: "a", count: 256))
      Issue.record("Expected failure")
    } catch let error as RealtimeError {
      #expect(error.kind == .encoding)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func encodeBroadcastPushCountsBytesNotCharacters() {
    #expect(throws: RealtimeError.self) {
      try encodePush(.topic, value: String(repeating: "é", count: 128))
    }
  }

  private func userBroadcastFrame(
    topic: String = "realtime:test",
    event: String = "evt",
    metadata: Data = Data(),
    encoding: BroadcastFrameCodec.PayloadEncoding,
    payload: Data
  ) -> Data {
    var frame = Data()
    frame.append(BroadcastFrameCodec.BinaryKind.userBroadcast.rawValue)
    frame.append(UInt8(topic.utf8.count))
    frame.append(UInt8(event.utf8.count))
    frame.append(UInt8(metadata.count))
    frame.append(encoding.rawValue)
    frame.append(Data(topic.utf8))
    frame.append(Data(event.utf8))
    frame.append(metadata)
    frame.append(payload)
    return frame
  }

  @Test
  func decodeBinaryJSONEncodingWithDatabaseMetadata() throws {
    let frame = userBroadcastFrame(
      event: "INSERT",
      metadata: Data(#"{"id":"0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d","replayed":true}"#.utf8),
      encoding: .json,
      payload: Data(#"{"record":{"id":1}}"#.utf8)
    )

    let broadcast = try BroadcastFrameCodec.decode(frame)

    #expect(broadcast.event == "INSERT")
    #expect(broadcast.meta?["id"]?.stringValue == "0b8a1e2c-77c4-4f1b-9d2a-3f5e6a7b8c9d")
    #expect(broadcast.meta?["replayed"]?.boolValue == true)
    guard case .json(let json) = broadcast.payload else {
      Issue.record("Expected JSON payload")
      return
    }
    #expect(json["record"]?.objectValue?["id"]?.intValue == 1)
  }

  @Test
  func decodeBinaryRawEncodingWithDatabaseMetadata() throws {
    let bytes = Data([0x00, 0xFF, 0x10, 0x80])
    let frame = userBroadcastFrame(
      metadata: Data(#"{"id":"abc","replayed":false}"#.utf8),
      encoding: .binary,
      payload: bytes
    )

    let broadcast = try BroadcastFrameCodec.decode(frame)

    #expect(broadcast.meta?["id"]?.stringValue == "abc")
    #expect(broadcast.meta?["replayed"]?.boolValue == false)
    guard case .binary(let data) = broadcast.payload else {
      Issue.record("Expected binary payload")
      return
    }
    #expect(data == bytes)
  }

  @Test
  func decodeBinaryWithoutMetadataHasNilMeta() throws {
    let frame = userBroadcastFrame(encoding: .json, payload: Data("{}".utf8))
    #expect(try BroadcastFrameCodec.decode(frame).meta == nil)
  }

  @Test
  func decodeBinaryAccepts255ByteMetadata() throws {
    let prefix = #"{"id":""#
    let suffix = #""}"#
    let id = String(repeating: "x", count: 255 - prefix.utf8.count - suffix.utf8.count)
    let metadata = Data((prefix + id + suffix).utf8)
    #expect(metadata.count == 255)

    let frame = userBroadcastFrame(
      metadata: metadata, encoding: .binary, payload: Data([0x2A]))
    let broadcast = try BroadcastFrameCodec.decode(frame)

    #expect(broadcast.meta?["id"]?.stringValue == id)
    guard case .binary(let data) = broadcast.payload else {
      Issue.record("Expected binary payload")
      return
    }
    #expect(data == Data([0x2A]))
  }

  @Test
  func decodeBinaryRejectsMetadataLongerThanTheFrame() {
    var frame = userBroadcastFrame(encoding: .binary, payload: Data())
    frame[3] = 255
    #expect(throws: RealtimeError.self) {
      try BroadcastFrameCodec.decode(frame)
    }
  }
}
