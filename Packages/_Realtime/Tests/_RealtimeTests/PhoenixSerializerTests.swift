//
//  PhoenixSerializerTests.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/26.
//

import Foundation
import Testing

@testable import _Realtime

@Suite struct PhoenixSerializerTests {
  @Test func roundTripTextFrame() throws {
    let msg = PhoenixMessage(
      joinRef: "1", ref: "2", topic: "room:1",
      event: "phx_join", payload: ["status": .string("ok")]
    )
    let frame = try PhoenixSerializer.encodeText(msg)
    let decoded = try PhoenixSerializer.decodeText(frame)
    #expect(decoded.joinRef == "1")
    #expect(decoded.ref == "2")
    #expect(decoded.topic == "room:1")
    #expect(decoded.event == "phx_join")
    #expect(decoded.payload["status"] == .string("ok"))
  }

  @Test func decodeTextWithNullRefs() throws {
    // [null, null, "phoenix", "heartbeat", {}]
    let json = "[null,null,\"phoenix\",\"heartbeat\",{}]"
    let decoded = try PhoenixSerializer.decodeText(json)
    #expect(decoded.joinRef == nil)
    #expect(decoded.ref == nil)
    #expect(decoded.topic == "phoenix")
    #expect(decoded.event == "heartbeat")
  }

  @Test func decodeBinaryBroadcast() throws {
    // Build a minimal type-0x04 binary frame
    let topic = "room:1"
    let event = "chat"
    let payload = Data("{\"msg\":\"hi\"}".utf8)

    var data = Data()
    data.append(0x04)  // kind = server broadcast
    data.append(UInt8(topic.utf8.count))  // topic_len
    data.append(UInt8(event.utf8.count))  // event_len
    data.append(0x00)  // meta_len
    data.append(0x01)  // encoding = json
    data.append(contentsOf: topic.utf8)
    data.append(contentsOf: event.utf8)
    data.append(payload)

    let broadcast = try PhoenixSerializer.decodeBinary(data)
    #expect(broadcast.topic == "room:1")
    #expect(broadcast.event == "chat")
    if case .json(let obj) = broadcast.payload {
      #expect(obj["msg"] == .string("hi"))
    } else {
      #expect(Bool(false), "Expected .json payload, got .binary")
    }
  }

  @Test func encodeBroadcastPushRoundTrip() throws {
    let encoded = try PhoenixSerializer.encodeBroadcastPush(
      joinRef: "1", ref: "2",
      topic: "room:1", event: "chat",
      payload: ["text": .string("hello"), "count": .int(42)]
    )
    // Decode it — but our decodeBinary expects type 0x04 (server), not 0x03 (client).
    // The client-encode format differs in header layout. Instead, verify the raw bytes.
    // Kind byte should be 0x03
    #expect(encoded[encoded.startIndex] == 0x03)
    // Verify the data can be re-parsed by checking the header fields
    let joinRefLen = Int(encoded[encoded.startIndex + 1])
    let refLen = Int(encoded[encoded.startIndex + 2])
    let topicLen = Int(encoded[encoded.startIndex + 3])
    let eventLen = Int(encoded[encoded.startIndex + 4])
    let metaLen = Int(encoded[encoded.startIndex + 5])
    let encByte = encoded[encoded.startIndex + 6]
    #expect(joinRefLen == 1)  // "1"
    #expect(refLen == 1)  // "2"
    #expect(topicLen == 6)  // "room:1"
    #expect(eventLen == 4)  // "chat"
    #expect(metaLen == 0)
    #expect(encByte == 0x01)  // json encoding
    // Verify the payload section contains valid JSON
    let headerAndFieldsSize = 7 + joinRefLen + refLen + topicLen + eventLen + metaLen
    let payloadData = Data(encoded.dropFirst(headerAndFieldsSize))
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: payloadData)
    #expect(decoded["text"] == .string("hello"))
    #expect(decoded["count"] == .int(42))
  }
}
