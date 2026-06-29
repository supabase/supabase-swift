//
//  PhoenixSerializerTextTests.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Foundation
import Helpers
import Testing

@testable import RealtimeV3

@Suite struct PhoenixSerializerTextTests {
  let serializer = PhoenixSerializer()

  @Test func encodesJoinAsJSONArray() throws {
    let text = try serializer.encodeText(
      joinRef: "1", ref: "1", topic: "room:1", event: "phx_join", payload: [:]
    )
    let decoded = try JSONDecoder().decode([AnyJSON].self, from: Data(text.utf8))
    #expect(decoded.count == 5)
    #expect(decoded[0] == "1")
    #expect(decoded[2] == "room:1")
    #expect(decoded[3] == "phx_join")
    #expect(decoded[4] == AnyJSON.object([:]))
  }

  @Test func decodesReplyWithNullJoinRef() throws {
    let frame = #"[null,"7","room:1","phx_reply",{"status":"ok","response":{}}]"#
    let msg = try serializer.decodeText(frame, receivedAt: Date(timeIntervalSince1970: 0))
    #expect(msg.joinRef == nil)
    #expect(msg.ref == "7")
    #expect(msg.event == .reply)
    if case .json(let v) = msg.payload {
      #expect(v.objectValue?["status"] == "ok")
    } else {
      Issue.record("json")
    }
  }

  @Test func rejectsShortArray() {
    #expect(throws: (any Error).self) {
      try serializer.decodeText("[1,2,3]", receivedAt: Date())
    }
  }
}
