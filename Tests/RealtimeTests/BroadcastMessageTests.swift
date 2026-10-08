//
//  BroadcastMessageTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import InlineSnapshotTesting
import SnapshotTestingCustomDump
import Testing

@testable import Realtime

@Suite
struct BroadcastMessageTests {
  struct Ping: Decodable, Equatable {
    let a: Int
  }

  private func text(_ payload: JSONObject, event: String = "broadcast") -> ChannelInbound {
    .message(
      RealtimeMessageV2(
        joinRef: nil, ref: nil, topic: "realtime:room", event: event, payload: payload))
  }

  @Test
  func textBroadcast() throws {
    let message = try #require(
      BroadcastMessage(text(["type": "broadcast", "event": "m", "payload": ["a": 1]])))

    assertInlineSnapshot(of: message, as: .customDump) {
      """
      BroadcastMessage(
        event: "m",
        payload: .json(
          .object(
            [
              "a": .integer(1)
            ]
          )
        ),
        id: nil,
        isReplayed: false
      )
      """
    }
    #expect(try message.decode(as: Ping.self) == Ping(a: 1))
  }

  @Test
  func databaseOriginatedTextBroadcastCarriesIDAndReplayed() throws {
    let message = try #require(
      BroadcastMessage(
        text([
          "type": "broadcast", "event": "INSERT", "payload": ["a": 1],
          "meta": ["id": "8A0C3E5B-6B0A-4C3E-9A5B-2B7C1D3E4F50", "replayed": true],
        ])))

    assertInlineSnapshot(of: message, as: .customDump) {
      """
      BroadcastMessage(
        event: "INSERT",
        payload: .json(
          .object(
            [
              "a": .integer(1)
            ]
          )
        ),
        id: UUID(8A0C3E5B-6B0A-4C3E-9A5B-2B7C1D3E4F50),
        isReplayed: true
      )
      """
    }
  }

  @Test
  func binaryBroadcastWithJSONPayload() throws {
    let message = try #require(
      BroadcastMessage(
        .broadcast(
          DecodedBroadcast(
            topic: "realtime:room", event: "m",
            meta: ["id": "8A0C3E5B-6B0A-4C3E-9A5B-2B7C1D3E4F50"], payload: .json(["a": 1])))))

    assertInlineSnapshot(of: message, as: .customDump) {
      """
      BroadcastMessage(
        event: "m",
        payload: .json(
          .object(
            [
              "a": .integer(1)
            ]
          )
        ),
        id: UUID(8A0C3E5B-6B0A-4C3E-9A5B-2B7C1D3E4F50),
        isReplayed: false
      )
      """
    }
    #expect(try message.decode(as: Ping.self) == Ping(a: 1))
  }

  @Test
  func binaryBroadcastWithABinaryPayload() throws {
    let message = try #require(
      BroadcastMessage(
        .broadcast(
          DecodedBroadcast(
            topic: "realtime:room", event: "m", payload: .binary(Data(#"{"a":2}"#.utf8))))))

    assertInlineSnapshot(of: message, as: .customDump) {
      """
      BroadcastMessage(
        event: "m",
        payload: .binary(Data(7 bytes)),
        id: nil,
        isReplayed: false
      )
      """
    }
    #expect(try message.decode(as: Ping.self) == Ping(a: 2))
  }

  @Test
  func otherInboundIsNotABroadcast() {
    #expect(BroadcastMessage(text(["status": "ok"], event: "system")) == nil)
    #expect(BroadcastMessage(.resubscribed) == nil)
  }

  @Test
  func decodeFailureThrowsADecodingError() throws {
    let message = try #require(
      BroadcastMessage(text(["type": "broadcast", "event": "m", "payload": ["a": "x"]])))

    let error = #expect(throws: RealtimeError.self) { try message.decode(as: Ping.self) }
    #expect(error?.kind == .decoding)
    #expect(error?.underlyingError is DecodingError)
  }
}
