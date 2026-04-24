//
//  PhoenixSerializerTests.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/26.
//

import Testing
import Foundation
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
    data.append(0x04)                          // kind = server broadcast
    data.append(UInt8(topic.utf8.count))       // topic_len
    data.append(UInt8(event.utf8.count))       // event_len
    data.append(0x00)                          // meta_len
    data.append(0x01)                          // encoding = json
    data.append(contentsOf: topic.utf8)
    data.append(contentsOf: event.utf8)
    data.append(payload)

    let broadcast = try PhoenixSerializer.decodeBinary(data)
    #expect(broadcast.topic == "room:1")
    #expect(broadcast.event == "chat")
  }
}
