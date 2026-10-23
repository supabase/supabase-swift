//
//  RealtimePolicyTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import Foundation
import Phoenix
import Testing

@testable import Realtime

@Suite
struct ReconnectDecisionTests {
  @Test(arguments: [401, 403, 404])
  func stopsOnARefusedHandshake(status: Int) {
    #expect(
      reconnectDecision(
        httpStatus: status, closeCode: nil, attempt: 1, maxAttempts: 5, base: .seconds(1))
        == .stop)
  }

  @Test(arguments: [4000, 4001, 4999])
  func stopsOnAnApplicationCloseCode(code: Int) {
    #expect(
      reconnectDecision(
        httpStatus: nil, closeCode: code, attempt: 1, maxAttempts: 5, base: .seconds(1)) == .stop)
  }

  @Test
  func stopsAtMaxAttempts() {
    #expect(
      reconnectDecision(
        httpStatus: 500, closeCode: 1006, attempt: 5, maxAttempts: 5, base: .seconds(1)) == .stop)
    #expect(
      reconnectDecision(
        httpStatus: 500, closeCode: 1006, attempt: 4, maxAttempts: 5, base: .seconds(1)) != .stop)
  }

  @Test(arguments: [(1, 1, 2), (3, 4, 8), (20, 15, 30)])
  func waitsWithEqualJitterThatDoublesUpToTheCap(attempt: Int, low: Int, high: Int) {
    let decision = reconnectDecision(
      httpStatus: nil, closeCode: nil, attempt: attempt, maxAttempts: 100, base: .seconds(2))

    guard case .retry(let wait) = decision else {
      Issue.record("Expected a retry, got \(decision)")
      return
    }
    #expect(wait >= .seconds(low) && wait <= .seconds(high))
  }
}

@Suite
struct JoinReplyTests {
  let insert = PostgresJoinConfig(event: .insert, schema: "public", table: "todos")

  @Test
  func readsTheEchoedBindingsWithTheirIds() throws {
    let echoed = try serverChanges(fromJoinReply: [
      "postgres_changes": [["id": 7, "event": "INSERT", "schema": "public", "table": "todos"]]
    ])

    #expect(echoed.map(\.id) == [7])
    #expect(postgresChangesMatch(sent: [insert], server: echoed))
  }

  @Test
  func aReplyWithoutBindingsMatchesAJoinWithoutThem() throws {
    #expect(try serverChanges(fromJoinReply: [:]).isEmpty)
    #expect(postgresChangesMatch(sent: [], server: []))
  }

  @Test
  func mismatchesOnADifferentBindingOrAMissingOne() {
    var other = insert
    other.table = "other"
    var filtered = insert
    filtered.filter = "id=eq.1"

    #expect(!postgresChangesMatch(sent: [insert], server: [other]))
    #expect(!postgresChangesMatch(sent: [insert], server: [filtered]))
    #expect(!postgresChangesMatch(sent: [insert, insert], server: [insert]))
  }
}

@Suite
struct SupabaseFrameCodecTests {
  let codec = SupabaseFrameCodec()

  @Test
  func stampsTheSocketRefsIntoABroadcastTemplate() throws {
    let template = try BroadcastFrameCodec.encodePush(
      joinRef: nil, ref: nil, topic: "realtime:room", event: "e", jsonPayload: ["n": 1])

    let encoded = try codec.encode(
      OutboundFrame(
        joinRef: "3", ref: "12", topic: "realtime:room", event: "broadcast",
        payload: .binary(template)))

    let expected = try BroadcastFrameCodec.encodePush(
      joinRef: "3", ref: "12", topic: "realtime:room", event: "e", jsonPayload: ["n": 1])
    #expect(encoded == .binary(expected))
  }

  @Test
  func leavesOtherFramesToThePhoenixCodec() throws {
    let frame = OutboundFrame(
      joinRef: "1", ref: "2", topic: "realtime:room", event: "phx_join", payload: [:])

    #expect(try codec.encode(frame) == PhoenixFrameCodec().encode(frame))
  }

  @Test
  func refusesAMalformedTemplateWithAFixedDescription() {
    let frame = OutboundFrame(
      joinRef: "1", ref: "2", topic: "t", event: "broadcast", payload: .binary(Data([3, 1])))

    #expect(throws: SupabaseFrameError.malformedBroadcastPush) { try codec.encode(frame) }
  }

  @Test
  func decodesJSONKind4AsABroadcastMessage() throws {
    let frame = kind4Frame(
      topic: "realtime:room", event: "e", encoding: 1, payload: Data(#"{"n":1}"#.utf8))

    let decoded = try codec.decode(.binary(frame))

    #expect(decoded.topic == "realtime:room")
    guard case .message(let event, .json(let json)) = decoded.body else {
      Issue.record("Expected a JSON message, got \(decoded.body)")
      return
    }
    #expect(event == "broadcast")
    #expect(json["event"]?.stringValue == "e")
    #expect(json["payload"]?["n"] == .int(1))
  }

  @Test
  func decodesABinaryKind4AsABroadcastCarryingTheWholeFrame() throws {
    let frame = kind4Frame(
      topic: "realtime:room", event: "phx_close", encoding: 0, payload: Data([7]))

    let decoded = try codec.decode(.binary(frame))

    guard case .message(let event, .binary(let bytes)) = decoded.body else {
      Issue.record("Expected a binary message, got \(decoded.body)")
      return
    }
    #expect(event == "broadcast")
    #expect(bytes == frame)
  }

  @Test
  func refusesDeepJSONBeforeDecodingIt() {
    let deep = String(repeating: "{\"a\":", count: 65) + "1" + String(repeating: "}", count: 65)
    let frame = kind4Frame(topic: "t", event: "e", encoding: 1, payload: Data(deep.utf8))

    #expect(throws: SupabaseFrameError.nestedTooDeep) { try codec.decode(.binary(frame)) }
  }

  @Test
  func acceptsJSONAtTheDepthLimit() throws {
    let deep = String(repeating: "[", count: 63) + String(repeating: "]", count: 63)
    let frame = kind4Frame(
      topic: "t", event: "e", encoding: 1, payload: Data(#"{"a":\#(deep)}"#.utf8))

    _ = try codec.decode(.binary(frame))
  }

  @Test
  func errorDescriptionsCarryNoPayloadText() {
    let frame = kind4Frame(
      topic: "t", event: "e", encoding: 1, payload: Data(#"{"secret": nope"#.utf8))

    #expect(throws: SupabaseFrameError.malformedBroadcast) { try codec.decode(.binary(frame)) }
    for error in [
      SupabaseFrameError.malformedBroadcast, .malformedBroadcastPush, .nestedTooDeep,
    ] {
      #expect(!error.description.contains("secret"))
    }
  }
}

@Suite
struct PhoenixBridgeTests {
  @Test
  func aRejectedJoinCarriesTheServerReason() {
    let error = RealtimeError(
      channelFailure: ChannelError.rejected(.json(["reason": "Unauthorized: no access"])))

    #expect(error.message == "Unauthorized: no access")
  }

  @Test
  func aBroadcastOverTheSizeLimitIsPayloadTooLarge() {
    let error = RealtimeError(
      channelFailure: ChannelError.replyError(
        status: "error", response: .json(["error": "payload_size_exceeded"])))

    #expect(error.kind == .payloadTooLarge)
  }

  @Test
  func aPushTimeoutIsATimeout() {
    #expect(RealtimeError(channelFailure: ChannelError.timeout).kind == .timeout)
  }

  @Test
  func channelStatusesMapToTheV2Names() {
    #expect(RealtimeChannelStatus(ChannelStatus.unjoined) == .subscribing)
    #expect(RealtimeChannelStatus(ChannelStatus.errored(.connectionLost)) == .subscribing)
    #expect(RealtimeChannelStatus(ChannelStatus.joined) == .subscribed)
    #expect(RealtimeChannelStatus(ChannelStatus.leaving) == .unsubscribing)
    #expect(RealtimeChannelStatus(ChannelStatus.closed(.left)) == .unsubscribed)
    #expect(
      RealtimeClientStatus(SocketStatus.waitingToReconnect(attempt: 1, failure: .heartbeatTimedOut))
        == .connecting)
  }
}
