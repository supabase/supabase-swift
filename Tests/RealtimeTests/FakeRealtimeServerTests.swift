//
//  FakeRealtimeServerTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

@Suite
struct FakeRealtimeServerTests {
  let serializer = RealtimeSerializer()

  private func join(
    topic: String = "realtime:room", ref: String = "1", postgresChanges: [JSONObject] = []
  ) -> RealtimeMessageV2 {
    RealtimeMessageV2(
      joinRef: ref, ref: ref, topic: topic, event: "phx_join",
      payload: ["config": ["postgres_changes": .array(postgresChanges.map(JSONValue.object))]])
  }

  private func send(_ message: RealtimeMessageV2, over connection: any WebSocketConnection)
    async throws
  {
    try await connection.send(.text(try serializer.encodeText(message)))
  }

  private func record(_ connection: any WebSocketConnection) -> LockIsolated<[WebSocketEvent]> {
    let events = LockIsolated([WebSocketEvent]())
    Task {
      for await event in connection.events {
        events.withValue { $0.append(event) }
      }
    }
    return events
  }

  private func firstMessage(in events: LockIsolated<[WebSocketEvent]>) async throws
    -> RealtimeMessageV2
  {
    #expect(await waitUntil { !events.value.isEmpty })
    guard case .frame(.text(let text)) = try #require(events.value.first) else {
      throw LoopbackError(message: "expected a text frame, got \(events.value)")
    }
    return try serializer.decodeText(text)
  }

  @Test
  func connectCountsConnectionsAndMarksTheServerConnected() async throws {
    let server = FakeRealtimeServer()
    #expect(server.connectCount == 0)
    #expect(!server.isConnected)

    _ = try await server.transport.connect(to: URL(string: "ws://fake")!, headerFields: [:])

    #expect(server.connectCount == 1)
    #expect(server.isConnected)
  }

  @Test
  func refusedUpgradeThrowsTheConfiguredStatusOnceThenAcceptsAgain() async throws {
    let server = FakeRealtimeServer()
    server.refuseNextUpgrade(status: 403)

    let error = await #expect(throws: RealtimeError.self) {
      _ = try await server.transport.connect(to: URL(string: "ws://fake")!, headerFields: [:])
    }
    #expect(error?.kind == .transport)
    #expect(error?.isRetryable == false)
    #expect(error?.message.contains("403") == true)

    _ = try await server.transport.connect(to: URL(string: "ws://fake")!, headerFields: [:])
    #expect(server.connectCount == 1)
  }

  @Test
  func recordsEveryClientFrameInSendOrder() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])

    try await connection.send(.text("a"))
    try await connection.send(.binary(Data([1])))
    try await connection.send(.text("c"))

    #expect(server.sentFrames == [.text("a"), .binary(Data([1])), .text("c")])
  }

  @Test
  func repliesOkToAJoinAndEchoesPostgresBindingsWithIntegerIDs() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)

    let binding: JSONObject = ["event": "INSERT", "schema": "public", "table": "todos"]
    try await send(join(ref: "7", postgresChanges: [binding]), over: connection)

    let reply = try await firstMessage(in: events)
    #expect(reply.event == "phx_reply")
    #expect(reply.ref == "7")
    #expect(reply.joinRef == "7")
    #expect(reply.topic == "realtime:room")
    #expect(reply.payload["status"] == "ok")
    let echoed = reply.payload["response"]?.objectValue?["postgres_changes"]?.arrayValue
    #expect(echoed?.count == 1)
    #expect(echoed?.first?.objectValue?["table"] == "todos")
    #expect(echoed?.first?.objectValue?["id"]?.intValue != nil)
    #expect(server.sentMessages.map(\.event) == ["phx_join"])
  }

  @Test
  func repliesWithTheConfiguredJoinErrorAfterTheDelayOnTheInjectedClock() async throws {
    let clock = TestClock()
    let server = FakeRealtimeServer(clock: clock)
    server.joinReply = .error(reason: "Unauthorized: nope")
    server.joinReplyDelay = .seconds(5)
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)

    try await send(join(), over: connection)
    await Task.megaYield()
    #expect(events.value.isEmpty)

    await clock.advance(by: .seconds(5))
    let reply = try await firstMessage(in: events)
    #expect(reply.payload["status"] == "error")
    #expect(reply.payload["response"]?.objectValue?["reason"] == "Unauthorized: nope")
  }

  @Test
  func staysSilentOnJoinWhenConfiguredOrWhenDroppingFrames() async throws {
    for configure in [
      { (s: FakeRealtimeServer) in s.joinReply = .silent },
      { (s: FakeRealtimeServer) in s.dropsClientFrames = true },
    ] {
      let server = FakeRealtimeServer()
      configure(server)
      let connection = try await server.transport.connect(
        to: URL(string: "ws://fake")!, headerFields: [:])
      let events = record(connection)

      try await send(join(), over: connection)
      await Task.megaYield()
      #expect(events.value.isEmpty)
      #expect(server.sentFrames.count == 1)
    }
  }

  @Test
  func repliesToHeartbeatsUnlessToldNotTo() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)
    let heartbeat = RealtimeMessageV2(
      joinRef: nil, ref: "3", topic: "phoenix", event: "heartbeat", payload: [:])

    try await send(heartbeat, over: connection)
    let reply = try await firstMessage(in: events)
    #expect(reply.topic == "phoenix")
    #expect(reply.ref == "3")
    #expect(reply.payload["status"] == "ok")

    server.repliesToHeartbeats = false
    try await send(heartbeat, over: connection)
    await Task.megaYield()
    #expect(events.value.count == 1)
  }

  @Test
  func leaveGetsAnOkReplyThenACloseWithTheJoinRef() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)

    try await send(join(ref: "1"), over: connection)
    try await send(
      RealtimeMessageV2(
        joinRef: "1", ref: "2", topic: "realtime:room", event: "phx_leave", payload: [:]),
      over: connection)

    #expect(await waitUntil { events.value.count == 3 })
    let messages = try events.value.compactMap { event -> RealtimeMessageV2? in
      guard case .frame(.text(let text)) = event else { return nil }
      return try serializer.decodeText(text)
    }
    #expect(messages.map(\.event) == ["phx_reply", "phx_reply", "phx_close"])
    #expect(messages[1].ref == "2")
    #expect(messages[2].joinRef == "1")
  }

  @Test
  func acknowledgesBroadcastsOnlyWhenEnabled() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)
    let broadcast = RealtimeMessageV2(
      joinRef: "1", ref: "9", topic: "realtime:room", event: "broadcast",
      payload: ["type": "broadcast", "event": "ping", "payload": [:]])

    try await send(broadcast, over: connection)
    await Task.megaYield()
    #expect(events.value.isEmpty)

    server.acknowledgesBroadcasts = true
    try await send(broadcast, over: connection)
    let reply = try await firstMessage(in: events)
    #expect(reply.ref == "9")
    #expect(reply.payload["status"] == "ok")
  }

  @Test
  func decodesAKind3BinaryBroadcastPushIntoSentMessages() async throws {
    let server = FakeRealtimeServer()
    server.acknowledgesBroadcasts = true
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)

    let frame = try serializer.encodeBroadcastPush(
      joinRef: "1", ref: "4", topic: "realtime:room", event: "ping", jsonPayload: ["n": 1])
    try await connection.send(.binary(frame))

    let message = try #require(server.sentMessages.first)
    #expect(message.event == "broadcast")
    #expect(message.ref == "4")
    #expect(message.joinRef == "1")
    #expect(message.payload["event"] == "ping")
    #expect(message.payload["payload"]?.objectValue?["n"] == 1)

    let reply = try await firstMessage(in: events)
    #expect(reply.ref == "4")
  }

  @Test
  func pushesBroadcastsAsKind4BinaryFramesWithMetadata() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)

    server.pushBroadcast(
      topic: "realtime:room", event: "ping", payload: ["n": 1], meta: ["id": "abc"])
    server.pushBroadcast(topic: "realtime:room", event: "blob", data: Data([9, 9]))

    #expect(await waitUntil { events.value.count == 2 })
    guard case .frame(.binary(let json)) = events.value[0],
      case .frame(.binary(let binary)) = events.value[1]
    else {
      Issue.record("expected binary frames, got \(events.value)")
      return
    }
    let first = try serializer.decodeBinary(json)
    #expect(first.topic == "realtime:room")
    #expect(first.event == "ping")
    #expect(first.meta == ["id": "abc"])
    if case .json(let object) = first.payload {
      #expect(object == ["n": 1])
    } else {
      Issue.record("expected json payload")
    }
    let second = try serializer.decodeBinary(binary)
    if case .binary(let data) = second.payload {
      #expect(data == Data([9, 9]))
    } else {
      Issue.record("expected binary payload")
    }
  }

  @Test
  func channelPushesUseTheCurrentJoinRefAndFastlanePushesUseNone() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)
    try await send(join(ref: "5"), over: connection)
    #expect(await waitUntil { events.value.count == 1 })

    server.pushSystem(
      topic: "realtime:room", status: "ok", message: "Subscribed to PostgreSQL",
      extension: "postgres_changes")
    server.pushPresenceState(topic: "realtime:room", state: ["u1": ["metas": []]])
    server.pushPresenceDiff(topic: "realtime:room", joins: [:], leaves: [:])
    server.pushPostgresChanges(topic: "realtime:room", ids: [1], data: ["type": "INSERT"])
    server.errorChannel(topic: "realtime:room")
    server.closeChannel(topic: "realtime:room")

    #expect(await waitUntil { events.value.count == 7 })
    let messages = try events.value.dropFirst().compactMap { event -> RealtimeMessageV2? in
      guard case .frame(.text(let text)) = event else { return nil }
      return try serializer.decodeText(text)
    }
    #expect(
      messages.map(\.event) == [
        "system", "presence_state", "presence_diff", "postgres_changes", "phx_error",
        "phx_close",
      ])
    #expect(messages.map(\.joinRef) == ["5", "5", nil, nil, "5", "5"])
    #expect(messages[0].payload["extension"] == "postgres_changes")
    #expect(messages[0].payload["channel"] == "room")
    #expect(messages[3].payload["ids"] == [1])
  }

  @Test
  func deliversRawFramesVerbatim() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)

    server.deliver(.text("not json"))
    server.deliver(.binary(Data([0xFF])))

    #expect(await waitUntil { events.value.count == 2 })
    #expect(events.value == [.frame(.text("not json")), .frame(.binary(Data([0xFF])))])
  }

  @Test
  func serverCloseIsTheFinalEventAndDisconnects() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)

    server.closeConnection(code: WebSocketCloseCode(rawValue: 4000), reason: "kicked")

    #expect(await waitUntil { events.value.count == 1 })
    #expect(events.value == [.closed(code: WebSocketCloseCode(rawValue: 4000), reason: "kicked")])
    #expect(!server.isConnected)
    let error = await #expect(throws: RealtimeError.self) {
      try await connection.send(.text("late"))
    }
    #expect(error?.kind == .notConnected)
  }

  @Test
  func clientCloseIsRecordedAndEchoedAsTheFinalEvent() async throws {
    let server = FakeRealtimeServer()
    let connection = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let events = record(connection)

    await connection.close(code: .normalClosure, reason: "bye")

    #expect(await waitUntil { events.value.count == 1 })
    #expect(events.value == [.closed(code: .normalClosure, reason: "bye")])
    #expect(server.clientCloseCode == .normalClosure)
    #expect(!server.isConnected)
  }

  @Test
  func pushesGoToTheNewestConnectionAfterAReconnect() async throws {
    let server = FakeRealtimeServer()
    let first = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let firstEvents = record(first)
    server.closeConnection(code: .abnormalClosure, reason: nil)
    let second = try await server.transport.connect(
      to: URL(string: "ws://fake")!, headerFields: [:])
    let secondEvents = record(second)

    server.deliver(.text("hello again"))

    #expect(await waitUntil { secondEvents.value.count == 1 })
    #expect(server.connectCount == 2)
    #expect(await waitUntil { firstEvents.value == [.closed(code: .abnormalClosure, reason: nil)] })
  }
}
