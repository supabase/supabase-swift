//
//  RealtimeChannelIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import Helpers
import PostgREST
import Realtime
import Testing

@Suite(
  .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil),
  .disabled(if: WebSocketAvailability.isMissing, "libcurl has no WebSocket support")
)
struct RealtimeChannelIntegrationTests {
  struct Item: Decodable, Sendable {
    var id: Int
    var listID: Int
    var title: String

    enum CodingKeys: String, CodingKey {
      case id
      case listID = "list_id"
      case title
    }
  }

  struct NewItem: Encodable {
    var listID: Int
    var title: String

    enum CodingKeys: String, CodingKey {
      case listID = "list_id"
      case title
    }
  }

  struct StreamEnded: Error {}

  let db = PostgrestClient(
    url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
    headers: ["Apikey": DotEnv.supabasePublishableKey])

  private func uniqueTopic() -> String { "it-\(UUID())" }
  private func uniqueList() -> Int { Int.random(in: 1_000_000...2_000_000_000) }

  /// Runs `body` with a fresh socket and closes it afterwards, also when `body` throws.
  private func withEngine(
    _ body: (RealtimeEngine) async throws -> Void
  ) async throws {
    let engine = LiveRealtime.engine()
    do {
      try await body(engine)
    } catch {
      await engine.disconnect()
      throw error
    }
    await engine.disconnect()
  }

  /// The first element that passes `predicate`, within 10 seconds.
  private func first<Element>(
    _ stream: RealtimeStream<Element>,
    where predicate: @escaping @Sendable (Element) -> Bool = { _ in true }
  ) async throws -> Element {
    try await withTimeout(.seconds(10)) {
      for await element in stream where predicate(element) { return element }
      throw StreamEnded()
    }
  }

  /// The first `count` elements that pass `predicate`, within 10 seconds.
  private func collect<Element>(
    _ stream: RealtimeStream<Element>, count: Int,
    where predicate: @escaping @Sendable (Element) -> Bool = { _ in true }
  ) async throws -> [Element] {
    try await withTimeout(.seconds(10)) {
      var elements: [Element] = []
      for await element in stream where predicate(element) {
        elements.append(element)
        if elements.count == count { return elements }
      }
      throw StreamEnded()
    }
  }

  private func listID(of change: PostgresChange) -> Int? {
    (change.record ?? change.oldRecord)?["list_id"]?.intValue
  }

  // MARK: - Lifecycle

  @Test
  func channelStatusChanges() async throws {
    try await withEngine { engine in
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine)
      let statuses = channel.statusChanges

      try await channel.subscribe()

      #expect(channel.status.isSubscribed)
      _ = try await first(statuses) { $0.isSubscribed }

      await channel.unsubscribe()
      guard case .unsubscribed = channel.status else {
        Issue.record("expected .unsubscribed, got \(channel.status)")
        return
      }
    }
  }

  @Test
  func privateChannelWithTheAnonKeyIsRefused() async throws {
    try await withEngine { engine in
      let channel = LiveRealtime.channel("private-\(UUID())", engine: engine) {
        $0.isPrivate = true
      }

      let error = await #expect(throws: RealtimeError.self) {
        try await withTimeout(.seconds(15)) { try await channel.subscribe() }
      }
      #expect(error?.kind == .unauthorized)
      #expect(error?.isRetryable == false)
      guard case .failed = channel.status else {
        Issue.record("expected .failed, got \(channel.status)")
        return
      }
    }
  }

  // MARK: - Broadcast

  @Test
  func broadcastSendAndReceive() async throws {
    try await withEngine { engine in
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine) {
        $0.broadcast.receiveOwnMessages = true
      }
      let messages = channel.broadcasts(event: "greeting")
      try await channel.subscribe()

      try await channel.broadcast(event: "greeting", payload: ["text": "hello"])

      let message = try await first(messages)
      #expect(try message.decode(as: [String: String].self) == ["text": "hello"])
    }
  }

  @Test
  func broadcastWithoutOwnBroadcasts() async throws {
    try await withEngine { sender in
      try await withEngine { listener in
        let topic = uniqueTopic()
        let sending = LiveRealtime.channel(topic, engine: sender)
        let listening = LiveRealtime.channel(topic, engine: listener)
        let echoes = sending.broadcasts(event: "ping")
        let received = listening.broadcasts(event: "ping")
        try await sending.subscribe()
        try await listening.subscribe()

        try await sending.broadcast(event: "ping", payload: ["n": 1])

        _ = try await first(received)
        await #expect(throws: TimeoutError.self) {
          try await withTimeout(.seconds(2)) {
            for await _ in echoes { return }
          }
        }
      }
    }
  }

  @Test
  func broadcastMultipleEvents() async throws {
    try await withEngine { engine in
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine) {
        $0.broadcast.receiveOwnMessages = true
      }
      let first = channel.broadcasts(event: "first")
      let second = channel.broadcasts(event: "second")
      try await channel.subscribe()

      try await channel.broadcast(event: "second", payload: ["n": 2])
      try await channel.broadcast(event: "first", payload: ["n": 1])

      let firstMessage = try await self.first(first)
      let secondMessage = try await self.first(second)
      #expect(firstMessage.event == "first")
      #expect(firstMessage.payload == .json(["n": 1]))
      #expect(secondMessage.event == "second")
      #expect(secondMessage.payload == .json(["n": 2]))
    }
  }

  @Test
  func acknowledgedBroadcastResolves() async throws {
    try await withEngine { engine in
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine) {
        $0.broadcast.acknowledge = true
      }
      try await channel.subscribe()

      try await channel.broadcast(event: "acknowledged", payload: ["n": 1])
    }
  }

  @Test
  func binaryBroadcastRoundTrip() async throws {
    try await withEngine { engine in
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine) {
        $0.broadcast.receiveOwnMessages = true
      }
      let messages = channel.broadcasts(event: "bytes")
      try await channel.subscribe()

      let data = Data([0x00, 0x01, 0xFE, 0xFF])
      try await channel.broadcast(event: "bytes", data: data)

      let message = try await first(messages)
      #expect(message.payload == .binary(data))
    }
  }

  @Test
  func httpSendReachesASubscribedListener() async throws {
    try await withEngine { engine in
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine)
      let messages = channel.broadcasts(event: "rest")
      try await channel.subscribe()

      try await channel.httpSend(event: "rest", payload: ["via": "http"])

      let message = try await first(messages)
      #expect(message.payload == .json(["via": "http"]))
    }
  }

  // MARK: - Postgres changes

  /// The server checks row level security against the table when it reads the change, so a row
  /// already deleted by then is never sent. Each statement waits for its change before the next.
  @Test
  func postgresAllChanges() async throws {
    try await withEngine { engine in
      let list = uniqueList()
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine)
      let changes = channel.postgresChanges(of: Item.self, table: "realtime_items")
      try await channel.subscribe()

      try await db.from("realtime_items").insert(NewItem(listID: list, title: "a")).execute()
      let insert = try await first(changes) { $0.raw.record?["list_id"]?.intValue == list }
      let inserted = try insert.row()
      #expect(insert.kind == .insert)
      #expect(inserted.listID == list)
      #expect(inserted.title == "a")

      try await db.from("realtime_items").update(["title": "b"]).eq("list_id", value: list)
        .execute()
      let update = try await first(changes) { $0.raw.record?["list_id"]?.intValue == list }
      #expect(update.kind == .update)
      #expect(try update.row().title == "b")

      try await db.from("realtime_items").delete().eq("list_id", value: list).execute()
      let delete = try await first(changes) { $0.oldRecord?["id"]?.intValue == inserted.id }
      #expect(delete.kind == .delete)
      #expect(throws: RealtimeError.self) { try delete.row() }
    }
  }

  @Test
  func postgresChangesWithFilter() async throws {
    try await withEngine { engine in
      let wanted = uniqueList()
      let other = uniqueList()
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine)
      let changes = channel.postgresChanges(
        event: .insert, table: "realtime_items", filter: .eq("list_id", value: wanted))
      try await channel.subscribe()

      try await db.from("realtime_items").insert(NewItem(listID: other, title: "skip")).execute()
      try await db.from("realtime_items").insert(NewItem(listID: wanted, title: "keep")).execute()

      let change = try await first(changes)
      #expect(listID(of: change) == wanted)
      #expect(change.record?["title"] == "keep")
    }
  }

  @Test
  func postgresChangesMultipleSubscriptions() async throws {
    try await withEngine { engine in
      let list = uniqueList()
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine)
      let inserts = channel.postgresChanges(event: .insert, table: "realtime_items")
      let deletes = channel.postgresChanges(event: .delete, table: "realtime_items")
      try await channel.subscribe()

      try await db.from("realtime_items").insert(NewItem(listID: list, title: "a")).execute()
      let insert = try await first(inserts) { $0.record?["list_id"]?.intValue == list }
      let id = insert.record?["id"]?.intValue

      try await db.from("realtime_items").delete().eq("list_id", value: list).execute()
      let delete = try await first(deletes) { $0.oldRecord?["id"]?.intValue == id }
      #expect(insert.kind == .insert)
      #expect(delete.kind == .delete)
    }
  }

  @Test
  func bindingAddedAfterSubscribeRejoinsAndReceives() async throws {
    try await withEngine { engine in
      let list = uniqueList()
      let channel = LiveRealtime.channel(uniqueTopic(), engine: engine)
      let events = channel.events
      try await channel.subscribe()

      let changes = channel.postgresChanges(
        event: .insert, table: "realtime_items", filter: .eq("list_id", value: list))

      let rejoin = try await collect(events, count: 2) {
        switch $0 {
        case .resubscribed, .postgresChangesReady: true
        default: false
        }
      }
      guard case .resubscribed = rejoin[0], case .postgresChangesReady = rejoin[1] else {
        Issue.record("expected .resubscribed then .postgresChangesReady, got \(rejoin)")
        return
      }

      try await db.from("realtime_items").insert(NewItem(listID: list, title: "late")).execute()

      let change = try await first(changes)
      #expect(listID(of: change) == list)
    }
  }
}
