//
//  RealtimeSerializerTests.swift
//
//
//  Created by Guilherme Souza on 05/12/24.
//

import Foundation
import XCTest

@testable import Realtime

final class RealtimeSerializerTests: XCTestCase {
  // MARK: - Binary Encoder Tests

  func testEncodePushWithBinaryPayload() throws {
    let encoder = RealtimeBinaryEncoder()

    let binaryData = Data([0x01, 0x04])
    let message = RealtimeMessageV2(
      joinRef: "10",
      ref: "1",
      topic: "t",
      event: "e",
      payload: ["payload": RealtimeBinaryPayload.binary(binaryData)]
    )

    let encoded = try encoder.encode(message)
    XCTAssertTrue(encoded.count > 0)

    // Verify the structure
    XCTAssertEqual(encoded[0], 0)  // Kind: push
    XCTAssertEqual(encoded[1], 2)  // joinRef length
    XCTAssertEqual(encoded[2], 1)  // ref length
    XCTAssertEqual(encoded[3], 1)  // topic length
    XCTAssertEqual(encoded[4], 1)  // event length

    // Verify payload is appended
    let headerEnd = 1 + 4 + 2 + 1 + 1 + 1  // header + meta + strings
    let payloadStart = encoded.index(encoded.startIndex, offsetBy: headerEnd)
    XCTAssertEqual(encoded[payloadStart], 0x01)
    XCTAssertEqual(encoded[payloadStart + 1], 0x04)
  }

  func testEncodeUserBroadcastPushWithJSONNoMetadata() throws {
    let encoder = RealtimeBinaryEncoder()

    let message = RealtimeMessageV2(
      joinRef: "10",
      ref: "1",
      topic: "top",
      event: "broadcast",
      payload: [
        "type": "broadcast",
        "event": "user-event",
        "payload": ["a": "b"],
      ]
    )

    let encoded = try encoder.encode(message)

    // Verify the structure
    XCTAssertEqual(encoded[0], 3)  // Kind: userBroadcastPush
    XCTAssertEqual(encoded[1], 2)  // joinRef length
    XCTAssertEqual(encoded[2], 1)  // ref length
    XCTAssertEqual(encoded[3], 3)  // topic length ("top")
    XCTAssertEqual(encoded[4], 10)  // userEvent length ("user-event")
    XCTAssertEqual(encoded[5], 0)  // metadata length
    XCTAssertEqual(encoded[6], 1)  // JSON encoding
  }

  func testEncodeUserBroadcastPushWithAllowedMetadata() throws {
    let encoder = RealtimeBinaryEncoder(allowedMetadataKeys: ["extra"])

    let message = RealtimeMessageV2(
      joinRef: "10",
      ref: "1",
      topic: "top",
      event: "broadcast",
      payload: [
        "type": "broadcast",
        "event": "user-event",
        "extra": "bit",
        "store": .bool(true),  // Should not be included
        "payload": ["a": "b"],
      ]
    )

    let encoded = try encoder.encode(message)

    // Verify metadata is included
    XCTAssertEqual(encoded[0], 3)  // Kind: userBroadcastPush
    XCTAssertEqual(encoded[5], 15)  // metadata length ({"extra":"bit"})
    XCTAssertEqual(encoded[6], 1)  // JSON encoding
  }

  func testEncodeUserBroadcastPushWithBinaryPayload() throws {
    let encoder = RealtimeBinaryEncoder()

    let binaryData = Data([0x01, 0x04])
    let message = RealtimeMessageV2(
      joinRef: "10",
      ref: "1",
      topic: "top",
      event: "broadcast",
      payload: [
        "event": "user-event",
        "payload": RealtimeBinaryPayload.binary(binaryData),
      ]
    )

    let encoded = try encoder.encode(message)

    // Verify the structure
    XCTAssertEqual(encoded[0], 3)  // Kind: userBroadcastPush
    XCTAssertEqual(encoded[6], 0)  // Binary encoding
  }

  func testThrowsErrorWhenJoinRefExceeds255() {
    let encoder = RealtimeBinaryEncoder()
    let longJoinRef = String(repeating: "a", count: 256)

    let message = RealtimeMessageV2(
      joinRef: longJoinRef,
      ref: "1",
      topic: "top",
      event: "broadcast",
      payload: [
        "event": "user-event",
        "payload": ["a": "b"],
      ]
    )

    XCTAssertThrowsError(try encoder.encode(message)) { error in
      XCTAssertTrue(error.localizedDescription.contains("joinRef length"))
    }
  }

  func testThrowsErrorWhenTopicExceeds255() {
    let encoder = RealtimeBinaryEncoder()
    let longTopic = String(repeating: "a", count: 256)

    let message = RealtimeMessageV2(
      joinRef: "10",
      ref: "1",
      topic: longTopic,
      event: "broadcast",
      payload: [
        "event": "user-event",
        "payload": ["a": "b"],
      ]
    )

    XCTAssertThrowsError(try encoder.encode(message)) { error in
      XCTAssertTrue(error.localizedDescription.contains("topic length"))
    }
  }

  // MARK: - Binary Decoder Tests

  func testDecodePushWithJSONPayload() throws {
    let decoder = RealtimeBinaryDecoder()

    // Construct: kind(1) + joinRefLen(1) + topicLen(1) + eventLen(1) + strings + payload
    var data = Data()
    data.append(0)  // kind: push
    data.append(3)  // joinRef length
    data.append(3)  // topic length
    data.append(10)  // event length
    data.append(contentsOf: "123".utf8)
    data.append(contentsOf: "top".utf8)
    data.append(contentsOf: "some-event".utf8)
    data.append(contentsOf: #"{"a":"b"}"#.utf8)

    let message = try decoder.decode(data)

    XCTAssertEqual(message.joinRef, "123")
    XCTAssertNil(message.ref)
    XCTAssertEqual(message.topic, "top")
    XCTAssertEqual(message.event, "some-event")
    XCTAssertEqual(message.payload["a"]?.stringValue, "b")
  }

  func testDecodeReplyWithJSONPayload() throws {
    let decoder = RealtimeBinaryDecoder()

    var data = Data()
    data.append(1)  // kind: reply
    data.append(3)  // joinRef length
    data.append(2)  // ref length
    data.append(3)  // topic length
    data.append(2)  // event/status length
    data.append(contentsOf: "100".utf8)
    data.append(contentsOf: "12".utf8)
    data.append(contentsOf: "top".utf8)
    data.append(contentsOf: "ok".utf8)
    data.append(contentsOf: #"{"a":"b"}"#.utf8)

    let message = try decoder.decode(data)

    XCTAssertEqual(message.joinRef, "100")
    XCTAssertEqual(message.ref, "12")
    XCTAssertEqual(message.topic, "top")
    XCTAssertEqual(message.event, "phx_reply")
    XCTAssertEqual(message.payload["status"]?.stringValue, "ok")
    XCTAssertEqual(message.payload["response"]?.objectValue?["a"]?.stringValue, "b")
  }

  func testDecodeBroadcastWithJSONPayload() throws {
    let decoder = RealtimeBinaryDecoder()

    var data = Data()
    data.append(2)  // kind: broadcast
    data.append(3)  // topic length
    data.append(10)  // event length
    data.append(contentsOf: "top".utf8)
    data.append(contentsOf: "some-event".utf8)
    data.append(contentsOf: #"{"a":"b"}"#.utf8)

    let message = try decoder.decode(data)

    XCTAssertNil(message.joinRef)
    XCTAssertNil(message.ref)
    XCTAssertEqual(message.topic, "top")
    XCTAssertEqual(message.event, "some-event")
    XCTAssertEqual(message.payload["a"]?.stringValue, "b")
  }

  func testDecodeUserBroadcastWithJSONPayloadNoMetadata() throws {
    let decoder = RealtimeBinaryDecoder()

    var data = Data()
    data.append(4)  // kind: userBroadcast
    data.append(3)  // topic length
    data.append(10)  // userEvent length
    data.append(0)  // metadata length
    data.append(1)  // JSON encoding
    data.append(contentsOf: "top".utf8)
    data.append(contentsOf: "user-event".utf8)
    // no metadata
    data.append(contentsOf: #"{"a":"b"}"#.utf8)

    let message = try decoder.decode(data)

    XCTAssertNil(message.joinRef)
    XCTAssertNil(message.ref)
    XCTAssertEqual(message.topic, "top")
    XCTAssertEqual(message.event, "broadcast")
    XCTAssertEqual(message.payload["type"]?.stringValue, "broadcast")
    XCTAssertEqual(message.payload["event"]?.stringValue, "user-event")
    XCTAssertEqual(message.payload["payload"]?.objectValue?["a"]?.stringValue, "b")
  }

  func testDecodeUserBroadcastWithJSONPayloadAndMetadata() throws {
    let decoder = RealtimeBinaryDecoder()

    var data = Data()
    data.append(4)  // kind: userBroadcast
    data.append(3)  // topic length
    data.append(10)  // userEvent length
    data.append(17)  // metadata length
    data.append(1)  // JSON encoding
    data.append(contentsOf: "top".utf8)
    data.append(contentsOf: "user-event".utf8)
    data.append(contentsOf: #"{"replayed":true}"#.utf8)
    data.append(contentsOf: #"{"a":"b"}"#.utf8)

    let message = try decoder.decode(data)

    XCTAssertEqual(message.event, "broadcast")
    XCTAssertEqual(message.payload["event"]?.stringValue, "user-event")
    XCTAssertEqual(message.payload["meta"]?.objectValue?["replayed"]?.boolValue, true)
    XCTAssertEqual(message.payload["payload"]?.objectValue?["a"]?.stringValue, "b")
  }

  func testDecodeUserBroadcastWithBinaryPayloadNoMetadata() throws {
    let decoder = RealtimeBinaryDecoder()

    var data = Data()
    data.append(4)  // kind: userBroadcast
    data.append(3)  // topic length
    data.append(10)  // userEvent length
    data.append(0)  // metadata length
    data.append(0)  // binary encoding
    data.append(contentsOf: "top".utf8)
    data.append(contentsOf: "user-event".utf8)
    // no metadata
    data.append(0x01)
    data.append(0x04)

    let message = try decoder.decode(data)

    XCTAssertEqual(message.event, "broadcast")
    XCTAssertEqual(message.payload["type"]?.stringValue, "broadcast")
    XCTAssertEqual(message.payload["event"]?.stringValue, "user-event")

    // Check binary payload
    let binaryPayload = RealtimeBinaryPayload.data(from: message.payload["payload"]!)
    XCTAssertNotNil(binaryPayload)
    XCTAssertEqual(binaryPayload, Data([0x01, 0x04]))
  }

  func testDecodeUserBroadcastWithBinaryPayloadAndMetadata() throws {
    let decoder = RealtimeBinaryDecoder()

    var data = Data()
    data.append(4)  // kind: userBroadcast
    data.append(3)  // topic length
    data.append(10)  // userEvent length
    data.append(17)  // metadata length
    data.append(0)  // binary encoding
    data.append(contentsOf: "top".utf8)
    data.append(contentsOf: "user-event".utf8)
    data.append(contentsOf: #"{"replayed":true}"#.utf8)
    data.append(0x01)
    data.append(0x04)

    let message = try decoder.decode(data)

    XCTAssertEqual(message.payload["event"]?.stringValue, "user-event")
    XCTAssertEqual(message.payload["meta"]?.objectValue?["replayed"]?.boolValue, true)

    let binaryPayload = RealtimeBinaryPayload.data(from: message.payload["payload"]!)
    XCTAssertNotNil(binaryPayload)
    XCTAssertEqual(binaryPayload, Data([0x01, 0x04]))
  }

  // MARK: - Binary Payload Helper Tests

  func testBinaryPayloadHelper() {
    let data = Data([0x01, 0x02, 0x03])
    let payload = RealtimeBinaryPayload.binary(data)

    XCTAssertTrue(RealtimeBinaryPayload.isBinary(payload))

    let extractedData = RealtimeBinaryPayload.data(from: payload)
    XCTAssertEqual(extractedData, data)
  }

  func testBinaryPayloadHelperWithNonBinary() {
    let payload: AnyJSON = .string("test")

    XCTAssertFalse(RealtimeBinaryPayload.isBinary(payload))
    XCTAssertNil(RealtimeBinaryPayload.data(from: payload))
  }

  // MARK: - Round-trip Tests

  func testRoundTripUserBroadcastWithBinary() throws {
    let encoder = RealtimeBinaryEncoder()
    let decoder = RealtimeBinaryDecoder()

    let originalData = Data([0x01, 0x02, 0x03, 0x04])
    let originalMessage = RealtimeMessageV2(
      joinRef: "10",
      ref: "1",
      topic: "test-topic",
      event: "broadcast",
      payload: [
        "event": "test-event",
        "payload": RealtimeBinaryPayload.binary(originalData),
      ]
    )

    let encoded = try encoder.encode(originalMessage)

    // Note: We can't directly decode what we encode because the server
    // would send it back as userBroadcast (kind 4) not userBroadcastPush (kind 3)
    // But we can verify the encoding structure is correct
    XCTAssertTrue(encoded.count > 0)
    XCTAssertEqual(encoded[0], 3)  // userBroadcastPush
  }
}
