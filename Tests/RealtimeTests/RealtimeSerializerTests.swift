//
//  RealtimeSerializerTests.swift
//
//
//  Created by Guilherme Souza on 12/02/26.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimeSerializerTests {
  let serializer = RealtimeSerializer()

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
    let array = try JSONDecoder().decode([JSONValue].self, from: Data(text.utf8))

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
    let array = try JSONDecoder().decode([JSONValue].self, from: Data(text.utf8))

    #expect(array.count == 5)
    #expect(array[0].stringValue == nil)
    #expect(array[1].stringValue == nil)
    #expect(array[2].stringValue == "phoenix")
    #expect(array[3].stringValue == "heartbeat")
  }

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

  @Test
  func decodeTextRejectsShortArraysWithDecodingKind() {
    do {
      _ = try serializer.decodeText("[1, 2, 3]")
      Issue.record("Expected failure")
    } catch let error as RealtimeError {
      #expect(error.kind == .decoding)
      #expect(error.message == "Expected JSON array with 5 elements, got 3.")
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

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

  @Test
  func encodeText_emptyPayload() throws {
    let message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "t", event: "e", payload: [:])
    let text = try serializer.encodeText(message)
    let decoded = try serializer.decodeText(text)
    #expect(decoded.payload == [:])
  }

  @Test
  func decodeTextRejectsArraysWithMoreThanFiveElements() {
    do {
      _ = try serializer.decodeText(#"[null, null, "t", "e", {}, "extra"]"#)
      Issue.record("Expected failure")
    } catch let error as RealtimeError {
      #expect(error.kind == .decoding)
      #expect(error.message == "Expected JSON array with 5 elements, got 6.")
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }
}
