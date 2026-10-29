//
//  RealtimeChannelTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import IssueReporting
import Helpers
import Logging
import Phoenix
import PhoenixTesting
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct RealtimeChannelTests {
  @Test
  func subscribeReportsStatusesInOrderAndReadsSubscribedWithoutAwait() async throws {
    let harness = RealtimeHarness()
    let channel = harness.client.channel("room")
    let statuses = channel.statusChange

    async let subscribed: Void = channel.subscribeWithError()
    let connection = await harness.transport.nextConnection()
    await connection.open()
    try await subscribed

    #expect(channel.status == .subscribed)
    #expect(await first(3, of: statuses) == [.unsubscribed, .subscribing, .subscribed])
  }

  @Test
  func joinPayloadCarriesConfigTokenAndVersion() async throws {
    let harness = RealtimeHarness { $0.headers[.authorization] = "Bearer user-token" }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room") {
      $0.broadcast.receiveOwnBroadcasts = true
      $0.isPrivate = true
    }
    let presenceStream = channel.presenceChange()

    try await channel.subscribeWithError()
    withExtendedLifetime(presenceStream) {}

    let join = await connection.nextSent("phx_join")
    let payload = join.payload.jsonObject
    #expect(join.topic == "realtime:room")
    #expect(payload["access_token"]?.stringValue == "user-token")
    #expect(payload["version"]?.stringValue?.hasPrefix("realtime-swift/") == true)
    let config: Helpers.JSONObject = payload["config"]?.objectValue ?? [:]
    let broadcast: Helpers.JSONObject = config["broadcast"]?.objectValue ?? [:]
    let presence: Helpers.JSONObject = config["presence"]?.objectValue ?? [:]
    #expect(config["private"] == .bool(true))
    #expect(broadcast["self"] == .bool(true))
    #expect(presence["enabled"] == .bool(true))
  }

  @Test
  func unsubscribeThenSubscribeTheSameInstanceDeliversBroadcasts() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()
    _ = await connection.nextSent("phx_join")

    await channel.unsubscribe()
    #expect(channel.status == .unsubscribed)
    _ = await connection.nextSent("phx_leave")

    let messages = channel.broadcastStream(event: "ping")
    try await channel.subscribeWithError()
    let rejoin = await connection.nextSent("phx_join")
    await connection.serverBroadcast(
      topic: "realtime:room", joinRef: rejoin.joinRef, event: "ping", payload: ["n": 1])

    #expect(channel.status == .subscribed)
    let received = await first(1, of: messages)
    #expect(received.first?["payload"]?.objectValue?["n"]?.intValue == 1)
  }

  @Test
  func cancellingTheReaderEndsItsStreamAndLeavesTheSiblingDelivering() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    let cancelled = channel.broadcastStream(event: "shared")
    let sibling = channel.broadcastStream(event: "shared")
    try await channel.subscribeWithError()
    let join = await connection.nextSent("phx_join")

    let reader = Task {
      for await _ in cancelled {}
      return "ended"
    }
    reader.cancel()
    #expect(await reader.value == "ended")

    await connection.serverBroadcast(
      topic: "realtime:room", joinRef: join.joinRef, event: "shared", payload: ["n": 2])
    let received = await first(1, of: sibling)
    #expect(received.first?["payload"]?.objectValue?["n"]?.intValue == 2)
  }

  @Test
  func twoStreamsOnOneEventEachGetEveryMessage() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    let one = channel.broadcastStream(event: "e")
    let two = channel.broadcastStream(event: "e")
    let everything = channel.broadcastStream(event: "*")
    try await channel.subscribeWithError()
    let join = await connection.nextSent("phx_join")

    for n in 1...2 {
      await connection.serverBroadcast(
        topic: "realtime:room", joinRef: join.joinRef, event: "e", payload: ["n": .int(n)])
    }

    let numbers = { (messages: [Helpers.JSONObject]) in
      messages.compactMap { $0["payload"]?.objectValue?["n"]?.intValue }
    }
    #expect(numbers(await first(2, of: one)) == [1, 2])
    #expect(numbers(await first(2, of: two)) == [1, 2])
    #expect(numbers(await first(2, of: everything)) == [1, 2])
  }

  @Test
  func rejectedJoinThrowsTheServerReasonAndLeavesTheSocketConnected() async throws {
    let reason = "Unauthorized: You do not have permissions to read from this Channel topic"
    let harness = RealtimeHarness(
      replies: .realtime(join: { _ in .error(["reason": .string(reason)]) }))
    try await harness.connect()
    let channel = harness.client.channel("private") { $0.isPrivate = true }

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.subscribeWithError()
    }

    #expect(error?.message == reason)
    #expect(error?.kind == .unauthorized)
    #expect(error?.isRetryable == false)
    #expect(channel.status == .unsubscribed)
    #expect(harness.client.status == .connected)
  }

  @Test
  func joinTimeoutsStopAtMaxRetryAttempts() async throws {
    let harness = RealtimeHarness(replies: .realtime(join: { _ in nil })) {
      $0.maxRetryAttempts = 1
      $0.timeout = .seconds(3)
    }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")

    let subscribing = Task { try await channel.subscribeWithError() }
    _ = await connection.nextSent("phx_join")
    await harness.advance(by: .seconds(3))
    #expect(channel.status == .subscribing)
    await harness.advance(by: RealtimeClientOptions.defaultTimeout)

    let error = await #expect(throws: RealtimeError.self) { try await subscribing.value }
    #expect(error?.kind == .maxRetryAttemptsReached)
    #expect(channel.status == .unsubscribed)
  }

  @Test
  func cancellingSubscribeRollsTheJoinBack() async throws {
    let harness = RealtimeHarness(replies: .realtime(join: { _ in nil }))
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    let statuses = channel.statusChange

    let subscribe = Task { try await channel.subscribeWithError() }
    _ = await connection.nextSent("phx_join")
    subscribe.cancel()

    await #expect(throws: CancellationError.self) { try await subscribe.value }
    _ = await connection.nextSent("phx_leave")
    let seen = await collect(statuses) { $0.count == 4 }
    #expect(seen == [.unsubscribed, .subscribing, .unsubscribing, .unsubscribed])
    #expect(channel.status == .unsubscribed)
  }

  @Test
  func postgresIdMismatchUnsubscribesAndThrows() async throws {
    let harness = RealtimeHarness(
      replies: .realtime(join: { _ in
        .ok([
          "postgres_changes": [
            ["id": 7, "event": "INSERT", "schema": "public", "table": "other"]
          ]
        ])
      }))
    let connection = try await harness.connect()
    let channel = harness.client.channel("db")
    let inserts = channel.postgresChange(InsertAction.self, table: "todos")

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.subscribeWithError()
    }
    withExtendedLifetime(inserts) {}

    #expect(error?.kind == .postgresChangesMismatch)
    #expect(channel.status == .unsubscribed)
    _ = await connection.nextSent("phx_leave")
  }

  @Test
  func postgresChangeReachesTheStreamWhoseBindingTheServerNamed() async throws {
    let harness = RealtimeHarness(
      replies: .realtime(join: { _ in
        .ok([
          "postgres_changes": [
            [
              "id": 7, "event": "INSERT", "schema": "public", "table": "todos", "filter": "id=eq.1",
            ],
            ["id": 8, "event": "DELETE", "schema": "public", "table": "todos"],
          ]
        ])
      }))
    let connection = try await harness.connect()
    let channel = harness.client.channel("db")
    let inserts = channel.postgresChange(
      InsertAction.self, table: "todos", filter: .eq("id", value: 1))
    let deletes = channel.postgresChange(DeleteAction.self, table: "todos")
    try await channel.subscribeWithError()
    let join = await connection.nextSent("phx_join")
    let sent = join.payload.jsonObject["config"]?.objectValue?["postgres_changes"]?.arrayValue
    #expect(sent?.count == 2)

    let commitTimestamp = try Helpers.JSONValue(Date(timeIntervalSince1970: 0)).phoenix
    await connection.serverSends(
      topic: "realtime:db", event: "postgres_changes",
      payload: [
        "ids": [7],
        "data": [
          "type": "INSERT", "record": ["id": 1], "columns": [["name": "id", "type": "int4"]],
          "commit_timestamp": commitTimestamp,
        ],
      ],
      joinRef: join.joinRef)

    let received = await first(1, of: inserts)
    #expect(received.first?.record["id"]?.intValue == 1)
    withExtendedLifetime(deletes) {}
  }

  @Test
  func broadcastWithAckWaitsForTheReplyAndThrowsItsError() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("room") { $0.broadcast.acknowledgeBroadcasts = true }
    try await channel.subscribeWithError()

    async let ok: Void = channel.broadcast(event: "e", message: ["n": 1])
    let first = await connection.nextBinary()
    let firstRefs = kind3Refs(first)
    #expect(first.first == 3)
    #expect(!firstRefs.ref.isEmpty)
    await connection.serverSends(
      topic: "realtime:room", event: "phx_reply",
      payload: ["status": "ok", "response": [:]], joinRef: firstRefs.joinRef, ref: firstRefs.ref)
    try await ok

    let rejected = Task { try await channel.broadcast(event: "e", message: ["n": 2]) }
    let second = kind3Refs(await connection.nextBinary())
    await connection.serverSends(
      topic: "realtime:room", event: "phx_reply",
      payload: ["status": "error", "response": ["reason": "payload too large"]],
      joinRef: second.joinRef, ref: second.ref)
    let error = await #expect(throws: RealtimeError.self) { try await rejected.value }
    #expect(error?.message.contains("payload too large") == true)
  }

  @Test
  func broadcastWithoutAckReturnsOnceSent() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()

    try await channel.broadcast(event: "bytes", data: Data([1, 2, 3]))

    let frame = await connection.nextBinary()
    let decoded = [UInt8](frame)
    #expect(decoded.first == 3)
    #expect(decoded.suffix(3) == [1, 2, 3])
  }

  @Test
  func broadcastBeforeSubscribeThrowsNotSubscribed() async throws {
    let harness = RealtimeHarness()
    let channel = harness.client.channel("room")

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.broadcast(event: "e", message: [:])
    }
    #expect(error?.kind == .notSubscribed)
  }

  @Test
  func kind4FramesReachTheirStreams() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    let json = channel.broadcastStream(event: "j")
    let bytes = channel.broadcastDataStream(event: "b")
    try await channel.subscribeWithError()

    await connection.receive(
      .binary(
        kind4Frame(
          topic: "realtime:room", event: "j", meta: Data(#"{"id":"m1"}"#.utf8),
          encoding: 1, payload: Data(#"{"n":5}"#.utf8))))
    await connection.receive(
      .binary(kind4Frame(topic: "realtime:room", event: "b", encoding: 0, payload: Data([9, 8]))))

    let message = await first(1, of: json).first
    #expect(message?["event"]?.stringValue == "j")
    #expect(message?["payload"]?.objectValue?["n"]?.intValue == 5)
    #expect(message?["meta"]?.objectValue?["id"]?.stringValue == "m1")
    #expect(await first(1, of: bytes) == [Data([9, 8])])
  }

  @Test
  func deepKind4IsDroppedAndTheSocketStaysConnected() async throws {
    let logs = LockIsolated<[String]>([])
    let harness = RealtimeHarness {
      var logger = Logger(label: "test") { _ in RecordingLogHandler(lines: logs) }
      logger.logLevel = .trace
      $0.logger = logger
    }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    let json = channel.broadcastStream(event: "j")
    try await channel.subscribeWithError()

    let deep = String(repeating: "[", count: 100) + String(repeating: "]", count: 100)
    await connection.receive(
      .binary(
        kind4Frame(
          topic: "realtime:room", event: "j", encoding: 1,
          payload: Data(#"{"n":\#(deep)}"#.utf8))))
    await connection.receive(
      .binary(
        kind4Frame(topic: "realtime:room", event: "j", encoding: 1, payload: Data(#"{"n":1}"#.utf8))
      ))

    let received = await first(1, of: json)
    #expect(received.first?["payload"]?.objectValue?["n"]?.intValue == 1)
    #expect(harness.client.status == .connected)
    #expect(logs.value.contains { $0.contains("nests JSON deeper") })
    #expect(!logs.value.contains { $0.contains("[[[") })
  }

  @Test
  func trackAndUntrackPushPresenceAndWait() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()

    try await channel.track(state: ["user": "a"])
    try await channel.untrack()

    let track = await connection.nextSent("presence").payload.jsonObject
    #expect(track["event"]?.stringValue == "track")
    #expect(track["payload"]?.objectValue?["user"]?.stringValue == "a")
    let untrack = await connection.nextSent("presence").payload.jsonObject
    #expect(untrack["event"]?.stringValue == "untrack")
  }

  @Test(.enabled(if: runsUnderSwiftTest))
  func joinShapingStreamAfterSubscribeReportsAnIssueAndEnds() async throws {
    let harness = RealtimeHarness()
    try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()
    let issues = IssueCollector()

    let late = withIssueReporters([issues]) {
      channel.postgresChange(AnyAction.self, table: "todos")
    }

    #expect(issues.count == 1)
    #expect(await first(1, of: late).isEmpty)
  }

  @Test
  func serverCloseEndsTheSubscription() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    let statuses = channel.statusChange
    try await channel.subscribeWithError()
    let join = await connection.nextSent("phx_join")

    await connection.serverSends(
      topic: "realtime:room", event: "phx_close", joinRef: join.joinRef)

    _ = await collect(statuses) { $0.last == .unsubscribed && $0.count > 1 }
    #expect(channel.status == .unsubscribed)
  }

  @Test
  func binaryBroadcastNamedLikeAControlEventStaysABroadcast() async throws {
    let harness = RealtimeHarness()
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    let bytes = channel.broadcastDataStream(event: "phx_close")
    try await channel.subscribeWithError()

    await connection.receive(
      .binary(
        kind4Frame(topic: "realtime:room", event: "phx_close", encoding: 0, payload: Data([1]))))

    #expect(await first(1, of: bytes) == [Data([1])])
    #expect(channel.status == .subscribed)
  }

  @Test(.enabled(if: hasImmediateTasks))
  func cancellingOneWaiterReturnsAtOnceAndLeavesTheSharedJoinRunning() async throws {
    let harness = RealtimeHarness(replies: .realtime(join: { _ in nil }))
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")

    let cancelled = Task.immediateIfAvailable { try await channel.subscribeWithError() }
    let waiting = Task.immediateIfAvailable { try await channel.subscribeWithError() }
    let join = await connection.nextSent("phx_join")
    cancelled.cancel()

    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(channel.status == .subscribing)
    await connection.reply(to: join)
    try await waiting.value
    #expect(channel.status == .subscribed)
  }

  @Test
  func subscribeStopsAtMaxRetryAttemptsWhileTheSocketKeepsReconnecting() async throws {
    let harness = RealtimeHarness {
      $0.reconnectDelay = .seconds(1)
      $0.maxRetryAttempts = 3
    }
    let channel = harness.client.channel("room")

    let subscribing = Task { try await channel.subscribeWithError() }
    await harness.transport.nextConnection().fail()
    for _ in 1...2 {
      await harness.advance(by: .seconds(30))
      let next = try #require(await harness.nextConnection())
      await next.fail()
    }

    let error = await #expect(throws: RealtimeError.self) { try await subscribing.value }
    #expect(error?.kind == .maxRetryAttemptsReached)
    #expect(channel.status == .unsubscribed)
    await harness.advance(by: .seconds(30))
    let next = try #require(await harness.nextConnection())
    await next.open()
    #expect(harness.client.status == .connected)
    #expect(harness.transport.connectionCount == 4)
  }

  @Test
  func subscribeDuringARejoinStopsAtMaxRetryAttempts() async throws {
    let harness = RealtimeHarness {
      $0.reconnectDelay = .seconds(1)
      $0.maxRetryAttempts = 2
    }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()
    await connection.fail()
    #expect(channel.status == .subscribing)

    let subscribing = Task { try await channel.subscribeWithError() }
    for _ in 1...2 {
      await harness.advance(by: .seconds(30))
      let next = try #require(await harness.nextConnection())
      await next.fail()
    }

    let error = await #expect(throws: RealtimeError.self) { try await subscribing.value }
    #expect(error?.kind == .maxRetryAttemptsReached)
    #expect(channel.status == .subscribing)
    #expect(harness.client.status == .connecting)
  }

  @Test
  func subscribeAfterDisconnectConnectsAgainAndReturnsOnceJoined() async throws {
    let harness = RealtimeHarness()
    try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()
    await harness.client.disconnect()
    #expect(channel.status == .subscribing)

    let subscribing = Task { try await channel.subscribeWithError() }
    let next = await harness.transport.nextConnection()
    await next.open()
    _ = await next.nextSent("phx_join")

    try await subscribing.value
    #expect(channel.status == .subscribed)
    #expect(harness.client.status == .connected)
  }

  @Test
  func subscribeAfterTheReconnectPolicyStoppedThrowsTheConnectError() async throws {
    let harness = RealtimeHarness { $0.reconnectDelay = .seconds(1) }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    try await channel.subscribeWithError()
    await connection.fail()
    await harness.advance(by: .seconds(1))
    await harness.transport.nextConnection().fail(httpStatus: 403)
    #expect(harness.client.status == .disconnected)

    let subscribing = Task { try await channel.subscribeWithError() }
    await harness.transport.nextConnection().fail(httpStatus: 401)

    let error = await #expect(throws: RealtimeError.self) { try await subscribing.value }
    #expect(error?.kind == .transport)
  }

  @Test
  func disconnectDuringTheFirstJoinThrowsNotConnected() async throws {
    let harness = RealtimeHarness(replies: .realtime(join: { _ in nil }))
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")

    let subscribing = Task { try await channel.subscribeWithError() }
    _ = await connection.nextSent("phx_join")
    await harness.client.disconnect()

    let error = await #expect(throws: RealtimeError.self) { try await subscribing.value }
    #expect(error?.kind == .notConnected)
    #expect(channel.status == .unsubscribed)
  }

  @Test
  func aCancelledSubscribeReturnsWhileTheCallbackHangsAndTheNextOneJoins() async throws {
    let callback = TokenCallback(nil)
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    try await harness.connect()
    let channel = harness.client.channel("room")
    callback.hold()

    let cancelled = Task { try await channel.subscribeWithError() }
    await callback.nextHeldCall()
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }

    let subscribing = Task.immediateIfAvailable { try await channel.subscribeWithError() }
    callback.release(returning: nil)

    try await subscribing.value
    #expect(channel.status == .subscribed)
  }

  @Test
  func cancelledSubscribeReturnsWhileTheServerHoldsTheLeaveReply() async throws {
    let harness = RealtimeHarness(replies: .none)
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")

    let cancelled = Task { try await channel.subscribeWithError() }
    let join = await connection.nextSent("phx_join")
    cancelled.cancel()
    let leave = await connection.nextSent("phx_leave")

    let outcome = try #require(
      await within(.seconds(5)) { await cancelled.result },
      "the cancelled subscribe returns before the leave reply")
    #expect(throws: CancellationError.self) { try outcome.get() }
    #expect(channel.status == .unsubscribing)

    let subscribing = Task.immediateIfAvailable { try await channel.subscribeWithError() }
    await connection.reply(to: leave)
    let rejoin = await connection.nextSent("phx_join")
    #expect(rejoin.joinRef != join.joinRef)
    await connection.reply(to: rejoin)
    try await subscribing.value
    #expect(channel.status == .subscribed)
  }

  @Test
  func cancelledSubscribeDuringTheRollbackReturnsWhileTheServerHoldsTheLeaveReply() async throws {
    let harness = RealtimeHarness(replies: .none)
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")

    let rolledBack = Task { try await channel.subscribeWithError() }
    let join = await connection.nextSent("phx_join")
    rolledBack.cancel()
    let leave = await connection.nextSent("phx_leave")
    let waiting = Task.immediateIfAvailable { try await channel.subscribeWithError() }
    waiting.cancel()

    let outcome = try #require(
      await within(.seconds(5)) { await waiting.result },
      "a cancelled subscribe that waits on the rollback returns before the leave reply")
    #expect(throws: CancellationError.self) { try outcome.get() }
    #expect(channel.status == .unsubscribing)

    await connection.reply(to: leave)
    let subscribing = Task.immediateIfAvailable { try await channel.subscribeWithError() }
    let rejoin = await connection.nextSent("phx_join")
    #expect(rejoin.joinRef != join.joinRef)
    await connection.reply(to: rejoin)
    try await subscribing.value
    await #expect(throws: CancellationError.self) { try await rolledBack.value }
    #expect(channel.status == .subscribed)
  }

  @Test
  func subscribeDuringTheRollbackJoinsOnlyAfterTheLeaveReply() async throws {
    let harness = RealtimeHarness(replies: .none)
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")

    let cancelled = Task { try await channel.subscribeWithError() }
    _ = await connection.nextSent("phx_join")
    cancelled.cancel()
    let leave = await connection.nextSent("phx_leave")
    try await Task.sleep(for: .milliseconds(200))
    #expect(channel.status == .unsubscribing, "the rollback ends only with the leave reply")

    let subscribing = Task.immediateIfAvailable { try await channel.subscribeWithError() }
    try await Task.sleep(for: .milliseconds(200))
    #expect(
      !connection.unreadSent.contains { $0.event == "phx_join" },
      "no join goes out before the leave reply")

    await connection.reply(to: leave)
    await connection.reply(to: await connection.nextSent("phx_join"))
    try await subscribing.value
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(channel.status == .subscribed)
  }

  @Test(arguments: [false, true])
  func subscribeAfterDisconnectWithoutConnectOnSubscribeStopsAtMaxRetryAttempts(
    subscribedBefore: Bool
  ) async throws {
    let harness = RealtimeHarness { $0.connectOnSubscribe = false }
    try await harness.connect()
    let channel = harness.client.channel("room")
    if subscribedBefore { try await channel.subscribeWithError() }
    await harness.client.disconnect()

    let outcome = LockIsolated<Result<Void, any Error>?>(nil)
    let subscribing = Task {
      do {
        try await channel.subscribeWithError()
        outcome.setValue(.success(()))
      } catch {
        outcome.setValue(.failure(error))
      }
    }
    for _ in 1...120 where outcome.value == nil {
      harness.clock.advance(by: .seconds(1))
      try await Task.sleep(for: .milliseconds(10))
    }
    subscribing.cancel()

    let error = #expect(throws: RealtimeError.self) { try outcome.value?.get() }
    #expect(error?.kind == .maxRetryAttemptsReached)
    #expect(harness.clock.now.offset >= .seconds(15))
    #expect(harness.transport.connectionCount == 1)
  }

  @Test
  func subscribeWithoutConnectOnSubscribeJoinsOnceTheClientConnects() async throws {
    let harness = RealtimeHarness { $0.connectOnSubscribe = false }
    let channel = harness.client.channel("room")

    let subscribing = Task { try await channel.subscribeWithError() }
    try #require(await harness.sleeper())
    harness.clock.advance(by: .seconds(1))
    try await harness.connect()

    try await subscribing.value
    #expect(channel.status == .subscribed)
  }
}

private var hasImmediateTasks: Bool {
  if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) { true } else { false }
}

private struct RecordingLogHandler: LogHandler {
  let lines: LockIsolated<[String]>
  var metadata: Logger.Metadata = [:]
  var logLevel: Logger.Level = .trace

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(event: LogEvent) {
    lines.withValue { $0.append("\(event.message)") }
  }
}
