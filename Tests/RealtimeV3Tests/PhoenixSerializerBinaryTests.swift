//
//  PhoenixSerializerBinaryTests.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 27/06/26.
//

import Foundation
import Helpers
import Testing

@testable import RealtimeV3

@Suite struct PhoenixSerializerBinaryTests {
  let s = PhoenixSerializer()

  @Test func jsonPushHasCorrectHeader() throws {
    let data = try s.encodeBroadcastPush(
      joinRef: "1", ref: "2", topic: "t", event: "e", jsonPayload: ["a": 1]
    )
    #expect(data[data.startIndex] == 3)  // kind = userBroadcastPush
    #expect(data[data.startIndex + 6] == 1)  // encoding = json
  }

  @Test func decodesServerBinaryFrameAsBinaryPayload() throws {
    // kind=4, topicLen=1, eventLen=1, metaLen=0, encoding=0(binary), "t","e", payload bytes
    var frame = Data([4, 1, 1, 0, 0])
    frame.append(contentsOf: Array("t".utf8))
    frame.append(contentsOf: Array("e".utf8))
    frame.append(contentsOf: [0xDE, 0xAD])
    let msg = try s.decodeBinary(frame, receivedAt: Date(timeIntervalSince1970: 0))
    #expect(msg.topic == "t")
    #expect(msg.event == "broadcast")
    if case .binary(let d) = msg.payload {
      #expect(Array(d) == [0xDE, 0xAD])
    } else {
      Issue.record("binary")
    }
  }

  @Test func rejectsUnexpectedKind() {
    #expect(throws: (any Error).self) {
      try s.decodeBinary(Data([9, 0, 0, 0, 0]), receivedAt: Date())
    }
  }

  @Test func rejectsOversizedHeaderField() {
    let big = String(repeating: "x", count: 256)
    #expect(throws: (any Error).self) {
      try s.encodeBroadcastPush(
        joinRef: nil, ref: nil, topic: big, event: "e", binaryPayload: Data())
    }
  }
}
