//
//  RealtimeChannelTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct RealtimeChannelTests {
  let clock = TestClock()
  let server: FakeRealtimeServer
  let engine: RealtimeEngine
  let http = RecordingTransport()
  let wireTopic = "realtime:room"

  init() {
    server = FakeRealtimeServer(clock: clock)
    var configuration = RealtimeEngineConfiguration(url: URL(string: "ws://fake")!)
    configuration.accessToken = { "token" }
    engine = RealtimeEngine(configuration: configuration, transport: server.transport, clock: clock)
  }

  private func makeChannel(
    accessToken: String? = "test-token",
    configure: (inout RealtimeChannelConfiguration) -> Void = { _ in }
  ) -> RealtimeChannel {
    var configuration = RealtimeChannelConfiguration()
    configure(&configuration)
    let rest = RealtimeREST(
      baseURL: URL(string: "https://localhost:54321/realtime/v1")!, apikey: "test-key",
      http: HTTPClientConfiguration(transport: http), timeout: .seconds(10), clock: clock,
      accessToken: { accessToken })
    return RealtimeChannel(topic: "room", configuration: configuration, engine: engine, rest: rest)
  }

  private var joins: [RealtimeMessageV2] { server.sentMessages.filter { $0.event == "phx_join" } }

  /// A sleeper reaches the clock only once its task has run, and an advance made before that
  /// strands it.
  private func settle() async {
    for _ in 0..<1_000 { await Task.yield() }
  }

  private func postgresData(_ type: String, id: Int) -> JSONObject {
    [
      "type": .string(type), "schema": "public", "table": "todos",
      "commit_timestamp": "2026-10-08T10:00:00.000Z",
      "columns": [["name": "id", "type": "int8"]],
      "record": type == "DELETE" ? .null : ["id": .integer(id)],
      "old_record": type == "INSERT" ? .null : ["id": .integer(id)],
      "errors": .null,
    ]
  }

  private func pushPostgresReady() {
    server.pushSystem(
      topic: wireTopic, status: "ok", message: "Subscribed to PostgreSQL",
      extension: "postgres_changes")
  }

  // MARK: - Lifecycle

  @Test
  func subscribeJoinsTheWireTopicAndReportsSubscribed() async throws {
    let channel = makeChannel()

    try await channel.subscribe()

    #expect(channel.status.isSubscribed)
    #expect(channel.topic == "room")
    #expect(joins.map(\.topic) == [wireTopic])
  }

  @Test
  func statusChangesStartsWithTheCurrentStatus() async throws {
    let channel = makeChannel()
    var statuses = channel.statusChanges.makeAsyncIterator()

    guard case .unsubscribed? = await statuses.next() else {
      Issue.record("expected the current status first")
      return
    }
    try await channel.subscribe()

    var sawSubscribed = false
    while let status = await statuses.next() {
      if status.isSubscribed {
        sawSubscribed = true
        break
      }
    }
    #expect(sawSubscribed)
  }

  @Test
  func unsubscribeLeavesTheChannel() async throws {
    let channel = makeChannel()
    try await channel.subscribe()

    await channel.unsubscribe()

    guard case .unsubscribed = channel.status else {
      Issue.record("expected .unsubscribed, got \(channel.status)")
      return
    }
    #expect(server.sentMessages.contains { $0.event == "phx_leave" && $0.topic == wireTopic })
  }

  // MARK: - Broadcast

  @Test
  func broadcastsMatchTheEventExactly() async throws {
    let channel = makeChannel()
    var messages = channel.broadcasts(event: "a").makeAsyncIterator()
    try await channel.subscribe()

    server.pushBroadcast(topic: wireTopic, event: "b", payload: ["n": 1])
    server.pushBroadcast(topic: wireTopic, event: "A", payload: ["n": 2])
    server.pushBroadcast(topic: wireTopic, event: "a", payload: ["n": 3])

    let message = await messages.next()
    #expect(message?.event == "a")
    #expect(message?.payload == .json(["n": 3]))
  }

  @Test
  func broadcastBeforeSubscribeThrowsNotSubscribed() async {
    let channel = makeChannel()

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.broadcast(event: "a", payload: ["n": 1])
    }
    #expect(error?.kind == .notSubscribed)
  }

  @Test
  func broadcastSendsTheEventAndPayload() async throws {
    let channel = makeChannel()
    try await channel.subscribe()

    try await channel.broadcast(event: "a", payload: ["n": 1])
    try await channel.broadcast(event: "bin", data: Data([1, 2, 3]))

    await waitUntil { server.sentMessages.filter { $0.event == "broadcast" }.count == 2 }
    let broadcasts = server.sentMessages.filter { $0.event == "broadcast" }
    #expect(broadcasts.map(\.topic) == [wireTopic, wireTopic])
    #expect(broadcasts.first?.payload == ["type": "broadcast", "event": "a", "payload": ["n": 1]])
    #expect(broadcasts.last?.payload["event"] == "bin")
  }

  @Test
  func acknowledgedBroadcastResolvesOnTheReply() async throws {
    server.acknowledgesBroadcasts = true
    let channel = makeChannel { $0.broadcast.acknowledge = true }
    try await channel.subscribe()

    try await channel.broadcast(event: "a", payload: ["n": 1])
  }

  @Test
  func acknowledgedBroadcastWithoutAReplyTimesOut() async throws {
    let channel = makeChannel { $0.broadcast.acknowledge = true }
    try await channel.subscribe()

    let sending = Task { try await channel.broadcast(event: "a", payload: ["n": 1]) }
    await waitUntil { server.sentMessages.contains { $0.event == "broadcast" } }
    await settle()
    await clock.advance(by: .seconds(15))

    do {
      try await sending.value
      Issue.record("expected a timeout")
    } catch let error as RealtimeError {
      #expect(error.kind == .timeout)
    }
  }

  @Test
  func acknowledgedBroadcastOverTheSizeLimitThrowsPayloadTooLarge() async throws {
    let channel = makeChannel { $0.broadcast.acknowledge = true }
    try await channel.subscribe()

    let sending = Task { try await channel.broadcast(event: "a", payload: ["n": 1]) }
    await waitUntil { server.sentMessages.contains { $0.event == "broadcast" } }
    let push = try #require(server.sentMessages.last { $0.event == "broadcast" })
    server.push(
      RealtimeMessageV2(
        joinRef: push.joinRef, ref: push.ref, topic: wireTopic, event: "phx_reply",
        payload: ["status": "error", "response": "payload_size_exceeded"]))

    do {
      try await sending.value
      Issue.record("expected payloadTooLarge")
    } catch let error as RealtimeError {
      #expect(error.kind == .payloadTooLarge)
    }
  }

  // MARK: - Events

  @Test
  func systemMessagesBecomeChannelEvents() async throws {
    let channel = makeChannel()
    var events = channel.events.makeAsyncIterator()
    try await channel.subscribe()

    server.pushSystem(topic: wireTopic, status: "ok", message: "hello")
    pushPostgresReady()
    server.pushSystem(
      topic: wireTopic, status: "error", message: "bad filter", extension: "postgres_changes")

    guard case .serverMessage(let message)? = await events.next() else {
      Issue.record("expected a server message")
      return
    }
    #expect(message.message == "hello")
    #expect(message.extension == "system")
    guard case .postgresChangesReady? = await events.next() else {
      Issue.record("expected postgresChangesReady")
      return
    }
    guard case .postgresChangesFailed("bad filter")? = await events.next() else {
      Issue.record("expected postgresChangesFailed")
      return
    }
    #expect(channel.status.isSubscribed, "a postgres_changes error does not close the channel")
  }

  // MARK: - Postgres changes

  @Test
  func subscribeWithABindingWaitsForPostgresChangesReady() async throws {
    let channel = makeChannel()
    _ = channel.postgresChanges(table: "todos")
    let finished = LockIsolated(false)

    let subscribing = Task {
      try await channel.subscribe()
      finished.setValue(true)
    }
    await waitUntil { channel.status.isSubscribed }
    await settle()
    #expect(!finished.value)

    pushPostgresReady()
    try await subscribing.value
    #expect(finished.value)
  }

  @Test
  func subscribeThrowsWhenPostgresChangesFail() async throws {
    let channel = makeChannel()
    _ = channel.postgresChanges(table: "todos")

    let subscribing = Task { try await channel.subscribe() }
    await waitUntil { channel.status.isSubscribed }
    server.pushSystem(
      topic: wireTopic, status: "error", message: "bad filter", extension: "postgres_changes")

    do {
      try await subscribing.value
      Issue.record("expected a failure")
    } catch let error as RealtimeError {
      #expect(error.kind == .server)
      #expect(error.message == "bad filter")
    }
  }

  @Test
  func subscribeTimesOutWithoutPostgresChangesReady() async throws {
    let channel = makeChannel()
    _ = channel.postgresChanges(table: "todos")

    let subscribing = Task { try await channel.subscribe() }
    await waitUntil { channel.status.isSubscribed }
    await settle()
    await clock.advance(by: .seconds(15))

    do {
      try await subscribing.value
      Issue.record("expected a timeout")
    } catch let error as RealtimeError {
      #expect(error.kind == .timeout)
    }
  }

  @Test
  func cancellingSubscribeWhileWaitingForPostgresChangesThrowsCancellation() async throws {
    let channel = makeChannel()
    _ = channel.postgresChanges(table: "todos")

    let subscribing = Task { try await channel.subscribe() }
    await waitUntil { channel.status.isSubscribed }
    await settle()
    subscribing.cancel()

    do {
      try await subscribing.value
      Issue.record("expected a cancellation")
    } catch {
      #expect(error is CancellationError, "got \(error)")
    }
  }

  @Test
  func bindingAddedDuringTheJoinIsSentAndRouted() async throws {
    server.joinReplyDelay = .seconds(1)
    let channel = makeChannel()
    var inserts = channel.postgresChanges(event: .insert, table: "todos").makeAsyncIterator()

    let subscribing = Task { try await channel.subscribe() }
    await waitUntil { joins.count == 1 }
    var deletes = channel.postgresChanges(event: .delete, table: "todos").makeAsyncIterator()
    await waitUntil { joins.count == 2 }
    await settle()
    await clock.advance(by: .seconds(1))
    await waitUntil { channel.status.isSubscribed }
    pushPostgresReady()
    try await subscribing.value

    let bindings = joins.last?.payload["config"]?.objectValue?["postgres_changes"]?.arrayValue
    #expect(bindings?.count == 2)
    let ids = engine.mirror.postgresChangeIDs(wireTopic)
    try #require(ids.count == 2)
    server.pushPostgresChanges(topic: wireTopic, ids: [ids[1]], data: postgresData("DELETE", id: 5))
    server.pushPostgresChanges(topic: wireTopic, ids: [ids[0]], data: postgresData("INSERT", id: 6))

    let insert = await inserts.next()
    let delete = await deletes.next()
    #expect(insert?.record?["id"] == 6)
    #expect(delete?.oldRecord?["id"] == 5)
  }

  @Test
  func twoBindingsRouteByServerID() async throws {
    let channel = makeChannel()
    var inserts = channel.postgresChanges(event: .insert, table: "todos").makeAsyncIterator()
    var deletes = channel.postgresChanges(event: .delete, table: "todos").makeAsyncIterator()

    let subscribing = Task { try await channel.subscribe() }
    await waitUntil { channel.status.isSubscribed }
    pushPostgresReady()
    try await subscribing.value
    #expect(engine.mirror.postgresChangeIDs(wireTopic) == [1, 2])

    server.pushPostgresChanges(topic: wireTopic, ids: [2], data: postgresData("DELETE", id: 7))
    server.pushPostgresChanges(topic: wireTopic, ids: [1], data: postgresData("INSERT", id: 8))

    let insert = await inserts.next()
    let delete = await deletes.next()
    #expect(insert?.kind == .insert)
    #expect(insert?.record?["id"] == 8)
    #expect(delete?.kind == .delete)
    #expect(delete?.oldRecord?["id"] == 7)
  }

  @Test
  func malformedPostgresChangeIsDropped() async throws {
    let channel = makeChannel()
    var changes = channel.postgresChanges(table: "todos").makeAsyncIterator()
    let subscribing = Task { try await channel.subscribe() }
    await waitUntil { channel.status.isSubscribed }
    pushPostgresReady()
    try await subscribing.value

    server.pushPostgresChanges(topic: wireTopic, ids: [1], data: postgresData("TRUNCATE", id: 1))
    server.pushPostgresChanges(topic: wireTopic, ids: [1], data: postgresData("INSERT", id: 2))

    let change = await changes.next()
    #expect(change?.record?["id"] == 2)
  }

  @Test
  func typedPostgresChangesDecodeTheRowLazily() async throws {
    struct Todo: Decodable {
      var id: Int
    }
    let channel = makeChannel()
    var changes = channel.postgresChanges(of: Todo.self, table: "todos").makeAsyncIterator()
    let subscribing = Task { try await channel.subscribe() }
    await waitUntil { channel.status.isSubscribed }
    pushPostgresReady()
    try await subscribing.value

    server.pushPostgresChanges(topic: wireTopic, ids: [1], data: postgresData("INSERT", id: 3))

    let change = await changes.next()
    #expect(try change?.row().id == 3)
  }

  @Test
  func bindingAddedWhileSubscribedRejoinsOnce() async throws {
    let channel = makeChannel()
    var events = channel.events.makeAsyncIterator()
    try await channel.subscribe()
    #expect(joins.count == 1)

    var changes = channel.postgresChanges(table: "todos").makeAsyncIterator()

    guard case .resubscribed? = await events.next() else {
      Issue.record("expected .resubscribed")
      return
    }
    await settle()
    #expect(joins.count == 2)
    let bindings = joins.last?.payload["config"]?.objectValue?["postgres_changes"]?.arrayValue
    #expect(bindings?.count == 1)
    #expect(channel.status.isSubscribed)

    server.pushPostgresChanges(
      topic: wireTopic, ids: engine.mirror.postgresChangeIDs(wireTopic),
      data: postgresData("INSERT", id: 4))
    let change = await changes.next()
    #expect(change?.record?["id"] == 4)
  }

  @Test
  func waitForSubscriptionGrowsTheJoinTimeout() async throws {
    server.joinReply = .silent
    let channel = makeChannel { $0.postgresChanges.waitForSubscription = true }
    _ = channel.postgresChanges(table: "todos")

    let subscribing = Task { try await channel.subscribe() }
    await waitUntil { !joins.isEmpty }
    await settle()
    await clock.advance(by: .seconds(16))
    await settle()
    guard case .subscribing = channel.status else {
      Issue.record("join timed out at the base timeout: \(channel.status)")
      subscribing.cancel()
      return
    }

    await clock.advance(by: .seconds(15))
    let rejoined = await waitUntil { joins.count == 2 }
    #expect(rejoined, "the join times out at 30 s and the channel joins again")
    await channel.unsubscribe()
    _ = try? await subscribing.value
  }

  // MARK: - REST broadcast

  @Test
  func httpSendPostsToTheBroadcastEndpoint() async throws {
    http.respond { _, _ in (HTTPResponse(status: .init(code: 202)), Data()) }
    let channel = makeChannel { $0.isPrivate = true }

    try await channel.httpSend(event: "test-event", payload: ["data": "explicit"])

    let request = try #require(http.requests.first)
    #expect(
      request.head.url?.absoluteString
        == "https://localhost:54321/realtime/v1/api/broadcast/room/events/test-event?private=true")
    #expect(request.head.method == .post)
    #expect(request.head.headerFields[.authorization] == "Bearer test-token")
    #expect(request.head.headerFields[.apikey] == "test-key")
    #expect(request.head.headerFields[.contentType] == "application/json")
    let body = try JSONDecoder().decode([String: String].self, from: request.body ?? Data())
    #expect(body == ["data": "explicit"])
  }

  @Test
  func httpSendWithDataSendsOctetStream() async throws {
    http.respond { _, _ in (HTTPResponse(status: .init(code: 202)), Data()) }
    let channel = makeChannel()

    try await channel.httpSend(event: "bin", data: Data([1, 2, 3]))

    let request = try #require(http.requests.first)
    #expect(
      request.head.url?.absoluteString
        == "https://localhost:54321/realtime/v1/api/broadcast/room/events/bin")
    #expect(request.head.headerFields[.contentType] == "application/octet-stream")
    #expect(request.body == Data([1, 2, 3]))
  }

  @Test
  func httpSendWithoutAnAccessTokenThrows() async {
    let channel = makeChannel(accessToken: nil)

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.httpSend(event: "a", data: Data())
    }
    #expect(error?.kind == .accessTokenMissing)
    #expect(http.requests.isEmpty)
  }

  @Test
  func httpSendThrowsTheServerMessageOnANon202Status() async {
    http.respond { _, _ in
      (HTTPResponse(status: .init(code: 500)), try JSONEncoder().encode(["error": "Server error"]))
    }
    let channel = makeChannel()

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.httpSend(event: "a", payload: ["n": 1])
    }
    #expect(error?.kind == .server)
    #expect(error?.message == "Server error")
    #expect(error?.response?.statusCode == 500)
  }

  @Test
  func httpSendWrapsATransportFailure() async {
    http.respond { _, _ in throw URLError(.timedOut) }
    let channel = makeChannel()

    let error = await #expect(throws: RealtimeError.self) {
      try await channel.httpSend(event: "a", payload: ["n": 1])
    }
    #expect(error?.kind == .transport)
    #expect((error?.underlyingError as? URLError)?.code == .timedOut)
  }
}
