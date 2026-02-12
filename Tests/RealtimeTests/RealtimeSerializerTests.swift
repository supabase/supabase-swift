//
//  RealtimeSerializerTests.swift
//
//
//  Created by Guilherme Souza on 12/02/26.
//

import XCTest

@testable import Realtime

final class RealtimeSerializerTests: XCTestCase {
  let serializer = RealtimeSerializer()

  // MARK: - Text Encoding

  func testEncodeText_withAllFields() throws {
    let message = RealtimeMessageV2(
      joinRef: "1",
      ref: "2",
      topic: "realtime:public:messages",
      event: "phx_join",
      payload: ["key": "value"]
    )

    let text = try serializer.encodeText(message)
    let array = try JSONDecoder().decode([AnyJSON].self, from: Data(text.utf8))

    XCTAssertEqual(array.count, 5)
    XCTAssertEqual(array[0].stringValue, "1")
    XCTAssertEqual(array[1].stringValue, "2")
    XCTAssertEqual(array[2].stringValue, "realtime:public:messages")
    XCTAssertEqual(array[3].stringValue, "phx_join")
    XCTAssertEqual(array[4].objectValue?["key"]?.stringValue, "value")
  }

  func testEncodeText_withNilRefs() throws {
    let message = RealtimeMessageV2(
      joinRef: nil,
      ref: nil,
      topic: "phoenix",
      event: "heartbeat",
      payload: [:]
    )

    let text = try serializer.encodeText(message)
    let array = try JSONDecoder().decode([AnyJSON].self, from: Data(text.utf8))

    XCTAssertEqual(array.count, 5)
    XCTAssertNil(array[0].stringValue)
    XCTAssertNil(array[1].stringValue)
    XCTAssertEqual(array[2].stringValue, "phoenix")
    XCTAssertEqual(array[3].stringValue, "heartbeat")
  }

  // MARK: - Text Decoding

  func testDecodeText_withAllFields() throws {
    let text = #"["1","2","realtime:test","phx_reply",{"status":"ok"}]"#
    let message = try serializer.decodeText(text)

    XCTAssertEqual(message.joinRef, "1")
    XCTAssertEqual(message.ref, "2")
    XCTAssertEqual(message.topic, "realtime:test")
    XCTAssertEqual(message.event, "phx_reply")
    XCTAssertEqual(message.payload["status"]?.stringValue, "ok")
  }

  func testDecodeText_withNullRefs() throws {
    let text = #"[null,null,"phoenix","heartbeat",{}]"#
    let message = try serializer.decodeText(text)

    XCTAssertNil(message.joinRef)
    XCTAssertNil(message.ref)
    XCTAssertEqual(message.topic, "phoenix")
    XCTAssertEqual(message.event, "heartbeat")
  }

  func testDecodeText_tooFewElements() {
    let text = #"["1","2","topic"]"#
    XCTAssertThrowsError(try serializer.decodeText(text))
  }

  // MARK: - Text Round-trip

  func testTextRoundTrip() throws {
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

    XCTAssertEqual(decoded.joinRef, original.joinRef)
    XCTAssertEqual(decoded.ref, original.ref)
    XCTAssertEqual(decoded.topic, original.topic)
    XCTAssertEqual(decoded.event, original.event)
    XCTAssertEqual(decoded.payload, original.payload)
  }

  // MARK: - Binary Encoding (type 0x03)

  func testEncodeBroadcastPush_jsonPayload() throws {
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
    XCTAssertEqual(data[0], RealtimeSerializer.BinaryKind.userBroadcastPush.rawValue)
    XCTAssertEqual(data[1], 1)  // joinRef length
    XCTAssertEqual(data[2], 1)  // ref length
    XCTAssertEqual(data[3], UInt8(topicLen))
    XCTAssertEqual(data[4], UInt8(eventLen))
    XCTAssertEqual(data[5], 0)  // metadata length
    XCTAssertEqual(data[6], RealtimeSerializer.PayloadEncoding.json.rawValue)

    // Verify string fields
    let headerSize = 7
    let joinRefStart = headerSize
    let refStart = joinRefStart + 1
    let topicStart = refStart + 1
    let eventStart = topicStart + topicLen
    let payloadStart = eventStart + eventLen

    XCTAssertEqual(String(data: data[joinRefStart..<refStart], encoding: .utf8), "1")
    XCTAssertEqual(String(data: data[refStart..<topicStart], encoding: .utf8), "2")
    XCTAssertEqual(String(data: data[topicStart..<eventStart], encoding: .utf8), "realtime:test")
    XCTAssertEqual(String(data: data[eventStart..<payloadStart], encoding: .utf8), "my_event")

    // Verify payload is valid JSON
    let payloadData = data[payloadStart...]
    let json = try JSONDecoder().decode(JSONObject.self, from: Data(payloadData))
    XCTAssertEqual(json["hello"]?.stringValue, "world")
  }

  func testEncodeBroadcastPush_binaryPayload() throws {
    let binaryPayload = Data([0x01, 0x02, 0x03, 0xFF])
    let data = try serializer.encodeBroadcastPush(
      joinRef: nil,
      ref: nil,
      topic: "realtime:test",
      event: "bin_event",
      binaryPayload: binaryPayload
    )

    XCTAssertEqual(data[0], RealtimeSerializer.BinaryKind.userBroadcastPush.rawValue)
    XCTAssertEqual(data[1], 0)  // joinRef length (nil)
    XCTAssertEqual(data[2], 0)  // ref length (nil)
    XCTAssertEqual(data[6], RealtimeSerializer.PayloadEncoding.binary.rawValue)

    // Extract payload
    let headerSize = 7
    let topicLen = Int(data[3])
    let eventLen = Int(data[4])
    let metaLen = Int(data[5])
    let payloadStart = headerSize + 0 + 0 + topicLen + eventLen + metaLen
    let extractedPayload = Data(data[payloadStart...])

    XCTAssertEqual(extractedPayload, binaryPayload)
  }

  func testEncodeBroadcastPush_nilRefs() throws {
    let data = try serializer.encodeBroadcastPush(
      joinRef: nil,
      ref: nil,
      topic: "t",
      event: "e",
      jsonPayload: [:]
    )

    XCTAssertEqual(data[1], 0)  // joinRef length
    XCTAssertEqual(data[2], 0)  // ref length
  }

  // MARK: - Binary Decoding (type 0x04)

  func testDecodeBinary_jsonPayload() throws {
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
    XCTAssertEqual(broadcast.topic, "realtime:test")
    XCTAssertEqual(broadcast.event, "my_event")
    if case .json(let json) = broadcast.payload {
      XCTAssertEqual(json["count"]?.intValue, 42)
    } else {
      XCTFail("Expected JSON payload")
    }
  }

  func testDecodeBinary_binaryPayload() throws {
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
    XCTAssertEqual(broadcast.topic, "realtime:test")
    XCTAssertEqual(broadcast.event, "bin")
    if case .binary(let data) = broadcast.payload {
      XCTAssertEqual(data, binaryPayload)
    } else {
      XCTFail("Expected binary payload")
    }
  }

  func testDecodeBinary_frameTooShort() {
    let data = Data([0x04, 0x01])
    XCTAssertThrowsError(try serializer.decodeBinary(data))
  }

  func testDecodeBinary_wrongKind() {
    var frame = Data()
    frame.append(0x01)  // wrong kind
    frame.append(0)
    frame.append(0)
    frame.append(0)
    frame.append(RealtimeSerializer.PayloadEncoding.json.rawValue)

    XCTAssertThrowsError(try serializer.decodeBinary(frame))
  }

  func testDecodeBinary_unknownEncoding() {
    var frame = Data()
    frame.append(RealtimeSerializer.BinaryKind.userBroadcast.rawValue)
    frame.append(0)
    frame.append(0)
    frame.append(0)
    frame.append(0xFF)  // unknown encoding

    XCTAssertThrowsError(try serializer.decodeBinary(frame))
  }

  // MARK: - Edge Cases

  func testEncodeText_emptyPayload() throws {
    let message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "t", event: "e", payload: [:])
    let text = try serializer.encodeText(message)
    let decoded = try serializer.decodeText(text)
    XCTAssertEqual(decoded.payload, [:])
  }

  func testDecodeBinary_emptyPayload() throws {
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
      XCTAssertTrue(data.isEmpty)
    } else {
      XCTFail("Expected binary payload")
    }
  }

  func testDecodeBinary_withMetadata() throws {
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
    XCTAssertEqual(broadcast.topic, "realtime:test")
    XCTAssertEqual(broadcast.event, "evt")
    if case .binary(let data) = broadcast.payload {
      XCTAssertEqual(data, Data([0x01]))
    } else {
      XCTFail("Expected binary payload")
    }
  }
}
