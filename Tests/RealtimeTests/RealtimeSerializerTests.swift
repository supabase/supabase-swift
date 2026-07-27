//
//  RealtimeSerializerTests.swift
//
//
//  Created by Guilherme Souza on 12/02/26.
//

import Foundation
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct RealtimeSerializerTests {
  let serializer = RealtimeSerializer()

  // MARK: - Text Encoding

  @Test
  func encodeText_withAllFields() throws {
    let message = RealtimeMessageV2(
      joinRef: "1",
      ref: "2",
      topic: "realtime:public:messages",
      event: "phx_join",
      payload: ["key": "value"]
    )

    let text = try serializer.encodeText(message)
    let array = try JSONDecoder().decode([AnyJSON].self, from: Data(text.utf8))

    #expect(array.count == 5)
    #expect(array[0].stringValue == "1")
    #expect(array[1].stringValue == "2")
    #expect(array[2].stringValue == "realtime:public:messages")
    #expect(array[3].stringValue == "phx_join")
    #expect(array[4].objectValue?["key"]?.stringValue == "value")
  }

  @Test
  func encodeText_withNilRefs() throws {
    let message = RealtimeMessageV2(
      joinRef: nil,
      ref: nil,
      topic: "phoenix",
      event: "heartbeat",
      payload: [:]
    )

    let text = try serializer.encodeText(message)
    let array = try JSONDecoder().decode([AnyJSON].self, from: Data(text.utf8))

    #expect(array.count == 5)
    #expect(array[0].stringValue == nil)
    #expect(array[1].stringValue == nil)
    #expect(array[2].stringValue == "phoenix")
    #expect(array[3].stringValue == "heartbeat")
  }

  // MARK: - Text Decoding

  @Test
  func decodeText_withAllFields() throws {
    let text = #"["1","2","realtime:test","phx_reply",{"status":"ok"}]"#
    let message = try serializer.decodeText(text)

    #expect(message.joinRef == "1")
    #expect(message.ref == "2")
    #expect(message.topic == "realtime:test")
    #expect(message.event == "phx_reply")
    #expect(message.payload["status"]?.stringValue == "ok")
  }

  @Test
  func decodeText_withNullRefs() throws {
    let text = #"[null,null,"phoenix","heartbeat",{}]"#
    let message = try serializer.decodeText(text)

    #expect(message.joinRef == nil)
    #expect(message.ref == nil)
    #expect(message.topic == "phoenix")
    #expect(message.event == "heartbeat")
  }

  @Test
  func decodeText_tooFewElements() {
    let text = #"["1","2","topic"]"#
    #expect(throws: (any Error).self) {
      try serializer.decodeText(text)
    }
  }

  // MARK: - Text Round-trip

  @Test
  func textRoundTrip() throws {
    let original = RealtimeMessageV2(
      joinRef: "join-1",
      ref: "ref-42",
      topic: "realtime:public:messages",
      event: "phx_join",
      payload: [
        "access_token": "token",
        "config": .object(["broadcast": .object(["ack": .bool(false)])]),
      ]
    )

    let text = try serializer.encodeText(original)
    let decoded = try serializer.decodeText(text)

    #expect(decoded.joinRef == original.joinRef)
    #expect(decoded.ref == original.ref)
    #expect(decoded.topic == original.topic)
    #expect(decoded.event == original.event)
    #expect(decoded.payload == original.payload)
  }

  // MARK: - Binary Encoding (type 0x03)

  @Test
  func encodeBroadcastPush_jsonPayload() throws {
    let data = try serializer.encodeBroadcastPush(
      joinRef: "1",
      ref: "2",
      topic: "realtime:test",
      event: "my_event",
      jsonPayload: ["hello": "world"]
    )

    // Verify header
    let topicLen = "realtime:test".utf8.count  // 13
    let eventLen = "my_event".utf8.count  // 8
    #expect(data[0] == RealtimeSerializer.BinaryKind.userBroadcastPush.rawValue)
    #expect(data[1] == 1)  // joinRef length
    #expect(data[2] == 1)  // ref length
    #expect(data[3] == UInt8(topicLen))
    #expect(data[4] == UInt8(eventLen))
    #expect(data[5] == 0)  // metadata length
    #expect(data[6] == RealtimeSerializer.PayloadEncoding.json.rawValue)

    // Verify string fields
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

    // Verify payload is valid JSON
    let payloadData = data[payloadStart...]
    let json = try JSONDecoder().decode(JSONObject.self, from: Data(payloadData))
    #expect(json["hello"]?.stringValue == "world")
  }

  @Test
  func encodeBroadcastPush_binaryPayload() throws {
    let binaryPayload = Data([0x01, 0x02, 0x03, 0xFF])
    let data = try serializer.encodeBroadcastPush(
      joinRef: nil,
      ref: nil,
      topic: "realtime:test",
      event: "bin_event",
      binaryPayload: binaryPayload
    )

    #expect(data[0] == RealtimeSerializer.BinaryKind.userBroadcastPush.rawValue)
    #expect(data[1] == 0)  // joinRef length (nil)
    #expect(data[2] == 0)  // ref length (nil)
    #expect(data[6] == RealtimeSerializer.PayloadEncoding.binary.rawValue)

    // Extract payload
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
    let data = try serializer.encodeBroadcastPush(
      joinRef: nil,
      ref: nil,
      topic: "t",
      event: "e",
      jsonPayload: [:]
    )

    #expect(data[1] == 0)  // joinRef length
    #expect(data[2] == 0)  // ref length
  }

  // MARK: - Binary Decoding (type 0x04)

  @Test
  func decodeBinary_jsonPayload() throws {
    let topic = "realtime:test"
    let event = "my_event"
    let jsonPayload: JSONObject = ["count": .integer(42)]
    let payloadData = try JSONEncoder().encode(jsonPayload)

    let topicBytes = Data(topic.utf8)
    let eventBytes = Data(event.utf8)

    var frame = Data()
    frame.append(RealtimeSerializer.BinaryKind.userBroadcast.rawValue)
    frame.append(UInt8(topicBytes.count))
    frame.append(UInt8(eventBytes.count))
    frame.append(0)  // metadata length
    frame.append(RealtimeSerializer.PayloadEncoding.json.rawValue)
    frame.append(topicBytes)
    frame.append(eventBytes)
    frame.append(payloadData)

    let broadcast = try serializer.decodeBinary(frame)
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
    frame.append(RealtimeSerializer.BinaryKind.userBroadcast.rawValue)
    frame.append(UInt8(topicBytes.count))
    frame.append(UInt8(eventBytes.count))
    frame.append(0)  // metadata length
    frame.append(RealtimeSerializer.PayloadEncoding.binary.rawValue)
    frame.append(topicBytes)
    frame.append(eventBytes)
    frame.append(binaryPayload)

    let broadcast = try serializer.decodeBinary(frame)
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
      try serializer.decodeBinary(data)
    }
  }

  @Test
  func decodeBinary_wrongKind() {
    var frame = Data()
    frame.append(0x01)  // wrong kind
    frame.append(0)
    frame.append(0)
    frame.append(0)
    frame.append(RealtimeSerializer.PayloadEncoding.json.rawValue)

    #expect(throws: (any Error).self) {
      try serializer.decodeBinary(frame)
    }
  }

  @Test
  func decodeBinary_unknownEncoding() {
    var frame = Data()
    frame.append(RealtimeSerializer.BinaryKind.userBroadcast.rawValue)
    frame.append(0)
    frame.append(0)
    frame.append(0)
    frame.append(0xFF)  // unknown encoding

    #expect(throws: (any Error).self) {
      try serializer.decodeBinary(frame)
    }
  }

  // MARK: - Edge Cases

  @Test
  func encodeText_emptyPayload() throws {
    let message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "t", event: "e", payload: [:])
    let text = try serializer.encodeText(message)
    let decoded = try serializer.decodeText(text)
    #expect(decoded.payload == [:])
  }

  @Test
  func decodeBinary_emptyPayload() throws {
    let topic = "t"
    let event = "e"

    var frame = Data()
    frame.append(RealtimeSerializer.BinaryKind.userBroadcast.rawValue)
    frame.append(UInt8(topic.utf8.count))
    frame.append(UInt8(event.utf8.count))
    frame.append(0)  // metadata length
    frame.append(RealtimeSerializer.PayloadEncoding.binary.rawValue)
    frame.append(Data(topic.utf8))
    frame.append(Data(event.utf8))
    // No payload bytes

    let broadcast = try serializer.decodeBinary(frame)
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
    frame.append(RealtimeSerializer.BinaryKind.userBroadcast.rawValue)
    frame.append(UInt8(topicBytes.count))
    frame.append(UInt8(eventBytes.count))
    frame.append(UInt8(metadata.count))
    frame.append(RealtimeSerializer.PayloadEncoding.binary.rawValue)
    frame.append(topicBytes)
    frame.append(eventBytes)
    frame.append(metadata)
    frame.append(binaryPayload)

    let broadcast = try serializer.decodeBinary(frame)
    #expect(broadcast.topic == "realtime:test")
    #expect(broadcast.event == "evt")
    if case .binary(let data) = broadcast.payload {
      #expect(data == Data([0x01]))
    } else {
      Issue.record("Expected binary payload")
    }
  }
}
