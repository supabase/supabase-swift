//
//  RealtimeChannelOnMessageTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 16/09/26.
//
import ConcurrencyExtras
import Foundation
import Logging
import TestHelpers
import Testing
@testable import Realtime
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
/// Characterization tests for ``RealtimeChannel/onMessage(_:)``.
/// what reaches the streams.
@Suite
struct RealtimeChannelOnMessageTests {
  let client: RealtimeClient
  let sut: RealtimeChannel
  let topic = "realtime:public:messages"
  let commitTimestamp: Date
  let commitTimestampJSON: JSONValue
  init() async throws {
    let client = RealtimeClient(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions()
    )
    self.client = client
    self.sut = await client.channel("public:messages")
    let timestamp = Date(timeIntervalSince1970: 1_703_592_000)
    self.commitTimestamp = timestamp
    self.commitTimestampJSON = try JSONValue(timestamp)
  }
  @Test
  func unknownEventDispatchesNothing() async {
    let events = await sut.events()
    let broadcasts = await sut.broadcasts(event: "*")
    await sut.onMessage(message(event: "not_a_channel_event"))

    let receivedEvents = await collect(events)
    #expect(receivedEvents.isEmpty)
    let receivedBroadcasts = await collect(broadcasts)
    #expect(receivedBroadcasts.isEmpty)
  }

  @Test
  func systemOKForPostgresChangesEmitsReady() async {
    let events = await sut.events()

    await sut.onMessage(
      message(
        event: ChannelEvent.system,
        payload: [
          "status": "ok", "extension": "postgres_changes",
          "message": "Subscribed to PostgreSQL",
        ]
      )
    )

    #expect(await collect(events) == [.postgresChangesReady])
    #expect(await sut.status == .unsubscribed)
  }

  @Test
  func systemErrorForPostgresChangesEmitsFailedWithTheServerMessage() async {
    let events = await sut.events()

    await sut.onMessage(
      message(
        event: ChannelEvent.system,
        payload: [
          "status": "error", "extension": "postgres_changes",
          "message": "Unable to subscribe to changes with given parameters.",
        ]
      )
    )

    #expect(
      await collect(events)
        == [.postgresChangesFailed("Unable to subscribe to changes with given parameters.")]
    )
  }

  @Test
  func systemMessagesForReplicationEmitReadyOrFailed() async {
    let events = await sut.events()

    await sut.onMessage(
      message(
        event: ChannelEvent.system,
        payload: [
          "status": "ok", "extension": "system",
          "message": "Replication connection established",
        ]
      )
    )
    await sut.onMessage(
      message(
        event: ChannelEvent.system,
        payload: ["status": "error", "extension": "system", "message": "Replication not ready"]
      )
    )

    #expect(
      await collect(events) == [.replicationReady, .replicationFailed("Replication not ready")])
  }

  @Test
  func systemMessageWithoutAKnownExtensionEmitsNothing() async {
    let events = await sut.events()

    await sut.onMessage(message(event: ChannelEvent.system, payload: ["status": "ok"]))
    await sut.onMessage(message(event: ChannelEvent.system, payload: ["status": "error"]))
    await sut.onMessage(message(event: ChannelEvent.system))

    #expect(await collect(events).isEmpty)
  }

  @Test
  func replyWithoutRefIsSwallowed() async {
    await sut.onMessage(message(event: ChannelEvent.reply, payload: ["status": "ok"]))

    #expect(await sut.serverChanges.isEmpty)
  }

  @Test
  func replyWithoutStatusIsSwallowed() async {
    await sut.onMessage(message(event: ChannelEvent.reply, ref: "1"))

    #expect(await sut.serverChanges.isEmpty)
  }

  @Test
  func replyWithoutPostgresChangesLeavesServerChangesUntouched() async {
    await sut.onMessage(
      message(
        event: ChannelEvent.reply,
        payload: ["status": "ok", "response": [:]],
        ref: "1"
      )
    )

    #expect(await sut.serverChanges.isEmpty)
  }

  @Test
  func replyToAnotherRefLeavesServerChangesUntouched() async {
    await sut.setJoinRef("2")
    await sut.onMessage(
      message(
        event: ChannelEvent.reply,
        payload: [
          "status": "ok",
          "response": [
            "postgres_changes": [
              ["id": 7, "event": "INSERT", "schema": "public", "table": "messages"]
            ]
          ],
        ],
        ref: "1"
      )
    )

    #expect(await sut.serverChanges.isEmpty)
  }

  @Test
  func replyWithPostgresChangesStoresServerChanges() async throws {
    await sut.setJoinRef("1")
    await sut.onMessage(
      message(
        event: ChannelEvent.reply,
        payload: [
          "status": "ok",
          "response": [
            "postgres_changes": [
              ["id": 7, "event": "INSERT", "schema": "public", "table": "messages"]
            ]
          ],
        ],
        ref: "1"
      )
    )

    let change = try #require(await sut.serverChanges.first)
    #expect(await sut.serverChanges.count == 1)
    #expect(change.id == 7)
    #expect(change.event == .insert)
    #expect(change.schema == "public")
    #expect(change.table == "messages")
  }

  @Test
  func replyWithMalformedPostgresChangesLeavesServerChangesUntouched() async {
    await sut.onMessage(
      message(
        event: ChannelEvent.reply,
        payload: [
          "status": "ok",
          "response": ["postgres_changes": "not-an-array"],
        ],
        ref: "1"
      )
    )

    #expect(await sut.serverChanges.isEmpty)
  }

  @Test
  func postgresChangesWithoutDataIsIgnored() async {
    let changes = await recordPostgresChanges()

    await sut.onMessage(message(event: ChannelEvent.postgresChanges, payload: ["ids": [1]]))

    let received = await collect(changes)
    #expect(received.isEmpty)
  }

  @Test
  func postgresChangesInsertDispatchesAnInsert() async throws {
    let changes = await recordPostgresChanges()

    await sut.onMessage(
      postgresChange([
        "type": "INSERT",
        "record": ["id": 1, "body": "hello"],
        "columns": [["name": "id", "type": "int4"], ["name": "body", "type": "text"]],
      ])
    )

    let received = await collect(changes)
    let change = try #require(received.first)
    #expect(received.count == 1)
    #expect(change.kind == .insert)
    #expect(change.schema == "public")
    #expect(change.table == "messages")
    #expect(change.record == PostgresRow(values: ["id": 1, "body": "hello"]))
    #expect(change.oldRecord == nil)
    #expect(change.commitTimestamp == commitTimestamp)
    #expect(
      change.columns == [
        PostgresColumn(name: "id", type: "int4"), PostgresColumn(name: "body", type: "text"),
      ])
  }

  @Test
  func postgresChangesUpdateDispatchesAnUpdateWithBothRecords() async throws {
    let changes = await recordPostgresChanges()

    await sut.onMessage(
      postgresChange([
        "type": "UPDATE",
        "record": ["id": 1, "body": "new"],
        "old_record": ["id": 1, "body": "old"],
        "columns": [["name": "body", "type": "text"]],
      ])
    )

    let change = try #require(await collect(changes).first)
    #expect(change.kind == .update)
    #expect(change.record == PostgresRow(values: ["id": 1, "body": "new"]))
    #expect(change.oldRecord == PostgresRow(values: ["id": 1, "body": "old"]))
  }

  @Test
  func postgresChangesUpdateWithoutRecordsHasNilRecords() async throws {
    let changes = await recordPostgresChanges()

    await sut.onMessage(
      postgresChange(["type": "UPDATE", "columns": [["name": "body", "type": "text"]]])
    )

    let change = try #require(await collect(changes).first)
    #expect(change.kind == .update)
    #expect(change.record == nil)
    #expect(change.oldRecord == nil)
  }

  @Test
  func postgresChangesDeleteDispatchesADelete() async throws {
    let changes = await recordPostgresChanges()

    await sut.onMessage(
      postgresChange([
        "type": "DELETE",
        "old_record": ["id": 1],
        "columns": [["name": "id", "type": "int4"]],
      ])
    )

    let change = try #require(await collect(changes).first)
    #expect(change.kind == .delete)
    #expect(change.record == nil)
    #expect(change.oldRecord == PostgresRow(values: ["id": 1]))
  }

  @Test
  func postgresChangesWithUnknownTypeIsDelivered() async throws {
    let changes = await recordPostgresChanges()

    await sut.onMessage(postgresChange(["type": "TRUNCATE", "columns": []]))

    let change = try #require(await collect(changes).first)
    #expect(change.kind == PostgresChange.Kind(rawValue: "TRUNCATE"))
  }

  @Test
  func postgresChangesDataThatIsNotAnObjectThrowsADecodingError() {
    let error = #expect(throws: RealtimeError.self) {
      try RealtimeChannel.postgresChangeData(in: ["ids": [1], "data": "not-an-object"])
    }
    #expect(error?.kind == .decoding)
  }

  @Test
  func postgresChangesWithoutDataHasNoChangeData() throws {
    #expect(try RealtimeChannel.postgresChangeData(in: ["ids": [1]]) == nil)
  }

  @Test
  func postgresChangesWithMalformedDataIsSwallowed() async {
    let changes = await recordPostgresChanges()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: ["ids": [1], "data": ["type": "INSERT"]]
      )
    )

    let received = await collect(changes)
    #expect(received.isEmpty)
  }

  @Test
  func postgresChangesWithoutIdsMatchesNoCallback() async {
    let changes = await recordPostgresChanges()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: [
          "data": [
            "type": "INSERT",
            "schema": "public",
            "table": "messages",
            "record": ["id": 1],
            "columns": [["name": "id", "type": "int4"]],
            "commit_timestamp": commitTimestampJSON,
          ]
        ]
      )
    )

    let received = await collect(changes)
    #expect(received.isEmpty)
  }

  @Test
  func typedPostgresChangesDeliverEveryChangeWhenARowDoesNotDecode() async throws {
    struct Message: Decodable, Equatable {
      let id: Int
      let body: String
    }
    let changes = await sut.postgresChanges(of: Message.self, table: "messages")
    await sut.setServerChanges([
      PostgresJoinConfig(event: .all, schema: "public", table: "messages", id: 1)
    ])

    await sut.onMessage(postgresChange(["type": "INSERT", "record": ["id": "not-a-number"]]))
    await sut.onMessage(postgresChange(["type": "INSERT", "record": ["id": 2, "body": "hi"]]))
    await sut.onMessage(postgresChange(["type": "DELETE", "old_record": ["id": 2]]))

    let received = await collect(changes)
    #expect(received.map(\.kind) == [.insert, .insert, .delete])
    #expect(throws: RealtimeError.self) { try received[0].row() }
    #expect(try received[1].row() == Message(id: 2, body: "hi"))
    #expect(received[2].oldRecord == PostgresRow(values: ["id": 2]))
  }

  @Test
  func typedPostgresChangesShapeTheJoinLikeTheUntypedStream() async {
    struct Message: Decodable {}
    let stream = await sut.postgresChanges(
      of: Message.self, event: .insert, schema: "chat", table: "messages",
      filter: .eq("room", value: 1), select: ["id"])

    let changes = await sut.clientChanges
    withExtendedLifetime(stream) {}
    #expect(
      changes == [
        PostgresJoinConfig(
          event: .insert, schema: "chat", table: "messages",
          filter: RealtimePostgresFilter.eq("room", value: 1).value)
      ])
    #expect(changes.first?.select == ["id"])
  }

  @Test
  func postgresChangesSignalsDeliverChangesEventsAndStatusesInOrder() async {
    let filtered = PostgresJoinConfig(
      event: .all, schema: "public", table: "messages", filter: "room=eq.1")
    let deletes = PostgresJoinConfig(event: .delete, schema: "public", table: "messages")
    let signals = await sut.postgresChangesSignals(bindings: [filtered, deletes])
    #expect(await sut.clientChanges == [filtered, deletes])

    var serverFiltered = filtered
    serverFiltered.id = 1
    var serverDeletes = deletes
    serverDeletes.id = 2
    await sut.setServerChanges([serverFiltered, serverDeletes])

    await sut.onMessage(postgresChange(["type": "INSERT", "record": ["id": 1]]))
    await sut.yieldEvent(.resubscribed)
    await sut.setFailed(.decoding("boom"))
    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: [
          "ids": [1, 2],
          "data": [
            "type": "DELETE", "schema": "public", "table": "messages",
            "commit_timestamp": commitTimestampJSON, "old_record": ["id": 1],
          ],
        ]
      )
    )

    let received = await collect(signals)
    #expect(received.count == 4)
    guard received.count == 4 else { return }
    if case .change(let change) = received[0] {
      #expect(change.kind == .insert)
    } else {
      Issue.record("Expected a change, got \(received[0])")
    }
    if case .event(let event) = received[1] {
      #expect(event == .resubscribed)
    } else {
      Issue.record("Expected an event, got \(received[1])")
    }
    if case .status(.failed) = received[2] {
    } else {
      Issue.record("Expected a failed status, got \(received[2])")
    }
    if case .change(let change) = received[3] {
      #expect(change.kind == .delete)
    } else {
      Issue.record("Expected a change, got \(received[3])")
    }
  }

  @Test
  func broadcastTriggersMatchingBroadcastCallback() async throws {
    let broadcasts = await sut.broadcasts(event: "message")

    await sut.onMessage(
      message(
        event: ChannelEvent.broadcast,
        payload: ["type": "broadcast", "event": "message", "payload": ["body": "hi"]]
      )
    )

    let received = await collect(broadcasts)
    let broadcast = try #require(received.first)
    #expect(received.count == 1)
    #expect(broadcast.event == "message")
    #expect(broadcast.payload == .json(["body": "hi"]))
    #expect(broadcast.id == nil)
    #expect(broadcast.isReplayed == false)
  }

  @Test
  func broadcastMatchingIsCaseSensitive() async {
    let broadcasts = await sut.broadcasts(event: "Typing")

    for event in ["typing", "Typing", "TYPING"] {
      await sut.onMessage(
        message(
          event: ChannelEvent.broadcast,
          payload: ["type": "broadcast", "event": .string(event), "payload": [:]]
        )
      )
    }

    #expect(await collect(broadcasts).map(\.event) == ["Typing"])
  }

  @Test
  func wildcardReceivesEveryEvent() async {
    let broadcasts = await sut.broadcasts(event: "*")

    for event in ["a", "B"] {
      await sut.onMessage(
        message(
          event: ChannelEvent.broadcast,
          payload: ["type": "broadcast", "event": .string(event), "payload": [:]]
        )
      )
    }

    #expect(await collect(broadcasts).map(\.event) == ["a", "B"])
  }

  @Test
  func broadcastWithoutEventIsSwallowed() async {
    let broadcasts = await sut.broadcasts(event: "*")

    await sut.onMessage(
      message(event: ChannelEvent.broadcast, payload: ["payload": ["body": "hi"]])
    )

    let receivedBroadcasts = await collect(broadcasts)
    #expect(receivedBroadcasts.isEmpty)
  }

  @Test
  func closeWithoutJoinRefRemovesChannelFromSocket() async {
    await sut.onMessage(message(event: ChannelEvent.close))

    #expect(await client.channelsByTopic[sut.topic] == nil)
  }

  @Test
  func closeForStaleJoinRefDoesNotRemoveChannel() async {
    await sut.onMessage(message(event: ChannelEvent.close, joinRef: "stale-ref"))

    #expect(await client.channelsByTopic[sut.topic] != nil)
  }

  @Test
  func errorClosesChannelWithoutRemovingItFromSocket() async {
    await sut.onMessage(message(event: ChannelEvent.error))

    #expect(await client.channelsByTopic[sut.topic] != nil)
    #expect(await sut.status == .unsubscribed)
  }

  @Test
  func presenceStateYieldsItsEntriesAsJoins() async throws {
    let changes = await sut.presenceChanges()

    await sut.onMessage(
      message(
        event: ChannelEvent.presenceState,
        payload: ["user-1": ["metas": [["phx_ref": "ref-1", "name": "ana"]]]]
      )
    )

    let change = try #require(await collect(changes).first)
    #expect(change.joins["user-1"]?.map(\.ref) == ["ref-1"])
    #expect(change.joins["user-1"]?.first?.payload == ["name": "ana"])
    #expect(change.leaves.isEmpty)
  }

  @Test
  func presenceDiffAfterAStateYieldsJoinsAndLeaves() async throws {
    let changes = await sut.presenceChanges()
    await sut.onMessage(
      message(
        event: ChannelEvent.presenceState,
        payload: ["user-2": ["metas": [["phx_ref": "ref-2"]]]]
      )
    )

    await sut.onMessage(
      message(
        event: ChannelEvent.presenceDiff,
        payload: [
          "joins": ["user-1": ["metas": [["phx_ref": "ref-1", "name": "ana"]]]],
          "leaves": ["user-2": ["metas": [["phx_ref": "ref-2"]]]],
        ]
      )
    )

    let change = try #require(await collect(changes).last)
    #expect(change.joins.keys.sorted() == ["user-1"])
    #expect(change.leaves["user-2"]?.map(\.ref) == ["ref-2"])
  }

  @Test
  func presenceMessagesWithoutChangesYieldNothing() async {
    let changes = await sut.presenceChanges()

    await sut.onMessage(message(event: ChannelEvent.presenceState))
    await sut.onMessage(message(event: ChannelEvent.presenceDiff))

    #expect(await collect(changes).isEmpty)
  }

  @Test
  func malformedPresenceMetasAreSkipped() async {
    let changes = await sut.presenceChanges()

    await sut.onMessage(
      message(
        event: ChannelEvent.presenceState,
        payload: ["user-1": "not-a-presence", "user-2": ["metas": [["name": "no ref"]]]]
      )
    )

    #expect(await collect(changes).isEmpty)
  }

  private func message(
    event: String,
    payload: JSONObject = [:],
    ref: String? = nil,
    joinRef: String? = nil
  ) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef,
      ref: ref,
      topic: topic,
      event: event,
      payload: payload
    )
  }

  /// Ends the channel's streams, then returns everything they had buffered. Every delivery in
  /// these tests happens synchronously inside `onMessage`, so nothing can arrive later.
  private func collect<Element>(_ stream: AsyncStream<Element>) async -> [Element] {
    await sut.finishStreams()
    var elements: [Element] = []
    for await element in stream {
      elements.append(element)
    }
    return elements
  }

  /// Opens a postgres stream and records server-change id `1` for it, matching the
  private func recordPostgresChanges() async -> AsyncStream<PostgresChange> {
    let changes = await sut.postgresChanges(schema: "public", table: "messages")
    await sut.setServerChanges([
      PostgresJoinConfig(event: .all, schema: "public", table: "messages", id: 1)
    ])
    return changes
  }

  /// A `postgres_changes` message for server-change id `1` on `public.messages`. `data` adds to
  /// or overrides the defaults.
  private func postgresChange(_ data: JSONObject) -> RealtimeMessage {
    let defaults: JSONObject = [
      "schema": "public", "table": "messages", "commit_timestamp": commitTimestampJSON,
    ]
    return message(
      event: ChannelEvent.postgresChanges,
      payload: ["ids": [1], "data": .object(defaults.merging(data) { $1 })]
    )
  }
}

extension RealtimeChannel {
  fileprivate func setServerChanges(_ changes: [PostgresJoinConfig]) {
    serverChanges = changes
  }
}

extension RealtimeChannel {
  fileprivate func setJoinRef(_ ref: String?) {
    joinRef = ref
  }

  fileprivate func yieldEvent(_ event: RealtimeChannelEvent) {
    yield(event)
  }

  fileprivate func setFailed(_ error: RealtimeError) {
    setState(.failed(error))
  }
}
