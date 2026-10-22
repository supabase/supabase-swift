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
    let systemMessages = await sut.systemMessages()
    let broadcasts = await sut.broadcasts(event: "*")
    await sut.onMessage(message(event: "not_a_channel_event"))

    let receivedSystemMessages = await collect(systemMessages)
    #expect(receivedSystemMessages.isEmpty)
    let receivedBroadcasts = await collect(broadcasts)
    #expect(receivedBroadcasts.isEmpty)
  }

  @Test
  func systemOKTriggersSystemCallback() async {
    let systemMessages = await sut.systemMessages()
    let sent = message(event: ChannelEvent.system, payload: ["status": "ok"])

    await sut.onMessage(sent)

    let receivedSystemMessages = await collect(systemMessages)
    #expect(receivedSystemMessages == [sent])
    #expect(await sut.status == .unsubscribed)
  }

  @Test
  func systemErrorStillTriggersSystemCallback() async {
    let systemMessages = await sut.systemMessages()
    let sent = message(event: ChannelEvent.system, payload: ["status": "error"])

    await sut.onMessage(sent)

    let receivedSystemMessages = await collect(systemMessages)
    #expect(receivedSystemMessages == [sent])
  }

  @Test
  func systemWithoutStatusStillTriggersSystemCallback() async {
    let systemMessages = await sut.systemMessages()
    let sent = message(event: ChannelEvent.system)

    await sut.onMessage(sent)

    let receivedSystemMessages = await collect(systemMessages)
    #expect(receivedSystemMessages == [sent])
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
  func replyWithPostgresChangesStoresServerChanges() async throws {
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
    let actions = await recordPostgresActions()

    await sut.onMessage(message(event: ChannelEvent.postgresChanges, payload: ["ids": [1]]))

    let receivedActions = await collect(actions)
    #expect(receivedActions.isEmpty)
  }

  @Test
  func postgresChangesInsertDispatchesInsertAction() async throws {
    let actions = await recordPostgresActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: [
          "ids": [1],
          "data": [
            "type": "INSERT",
            "record": ["id": 1, "body": "hello"],
            "columns": [["name": "id", "type": "int4"], ["name": "body", "type": "text"]],
            "commit_timestamp": commitTimestampJSON,
          ],
        ]
      )
    )

    let receivedActions = await collect(actions)
    let action = try #require(receivedActions.first)
    #expect(receivedActions.count == 1)
    guard case .insert(let insert) = action else {
      Issue.record("Expected .insert, got \(action)")
      return
    }
    #expect(insert.record == ["id": 1, "body": "hello"])
    #expect(insert.commitTimestamp == commitTimestamp)
    #expect(
      insert.columns == [Column(name: "id", type: "int4"), Column(name: "body", type: "text")])
  }

  @Test
  func postgresChangesUpdateDispatchesUpdateActionWithBothRecords() async throws {
    let actions = await recordPostgresActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: [
          "ids": [1],
          "data": [
            "type": "UPDATE",
            "record": ["id": 1, "body": "new"],
            "old_record": ["id": 1, "body": "old"],
            "columns": [["name": "body", "type": "text"]],
            "commit_timestamp": commitTimestampJSON,
          ],
        ]
      )
    )

    let receivedActions = await collect(actions)
    let action = try #require(receivedActions.first)
    guard case .update(let update) = action else {
      Issue.record("Expected .update, got \(action)")
      return
    }
    #expect(update.record == ["id": 1, "body": "new"])
    #expect(update.oldRecord == ["id": 1, "body": "old"])
  }

  @Test
  func postgresChangesUpdateWithoutRecordsFallsBackToEmptyObjects() async throws {
    let actions = await recordPostgresActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: [
          "ids": [1],
          "data": [
            "type": "UPDATE",
            "columns": [["name": "body", "type": "text"]],
            "commit_timestamp": commitTimestampJSON,
          ],
        ]
      )
    )

    let receivedActions = await collect(actions)
    let action = try #require(receivedActions.first)
    guard case .update(let update) = action else {
      Issue.record("Expected .update, got \(action)")
      return
    }
    #expect(update.record.isEmpty)
    #expect(update.oldRecord.isEmpty)
  }

  @Test
  func postgresChangesDeleteDispatchesDeleteAction() async throws {
    let actions = await recordPostgresActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: [
          "ids": [1],
          "data": [
            "type": "DELETE",
            "old_record": ["id": 1],
            "columns": [["name": "id", "type": "int4"]],
            "commit_timestamp": commitTimestampJSON,
          ],
        ]
      )
    )

    let receivedActions = await collect(actions)
    let action = try #require(receivedActions.first)
    guard case .delete(let delete) = action else {
      Issue.record("Expected .delete, got \(action)")
      return
    }
    #expect(delete.oldRecord == ["id": 1])
  }

  @Test
  func postgresChangesWithUnknownTypeIsSwallowed() async {
    let actions = await recordPostgresActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: [
          "ids": [1],
          "data": [
            "type": "TRUNCATE",
            "columns": [],
            "commit_timestamp": commitTimestampJSON,
          ],
        ]
      )
    )

    let receivedActions = await collect(actions)
    #expect(receivedActions.isEmpty)
  }

  @Test
  func postgresChangesWithMalformedDataIsSwallowed() async {
    let actions = await recordPostgresActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: ["ids": [1], "data": ["type": "INSERT"]]
      )
    )

    let receivedActions = await collect(actions)
    #expect(receivedActions.isEmpty)
  }

  @Test
  func postgresChangesWithoutIdsMatchesNoCallback() async {
    let actions = await recordPostgresActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: [
          "data": [
            "type": "INSERT",
            "record": ["id": 1],
            "columns": [["name": "id", "type": "int4"]],
            "commit_timestamp": commitTimestampJSON,
          ]
        ]
      )
    )

    let receivedActions = await collect(actions)
    #expect(receivedActions.isEmpty)
  }

  @Test
  func broadcastTriggersMatchingBroadcastCallback() async throws {
    let broadcasts = await sut.broadcasts(event: "message")

    await sut.onMessage(
      message(
        event: ChannelEvent.broadcast,
        payload: ["event": "message", "payload": ["body": "hi"]]
      )
    )

    let receivedBroadcasts = await collect(broadcasts)
    let received = try #require(receivedBroadcasts.first)
    #expect(receivedBroadcasts.count == 1)
    #expect(received["event"]?.stringValue == "message")
    #expect(received["payload"]?.objectValue?["body"]?.stringValue == "hi")
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

    #expect(await client.channels[topic] == nil)
  }

  @Test
  func closeForStaleJoinRefDoesNotRemoveChannel() async {
    await sut.onMessage(message(event: ChannelEvent.close, joinRef: "stale-ref"))

    #expect(await client.channels[topic] != nil)
  }

  @Test
  func errorClosesChannelWithoutRemovingItFromSocket() async {
    await sut.onMessage(message(event: ChannelEvent.error))

    #expect(await client.channels[topic] != nil)
    #expect(await sut.status == .unsubscribed)
  }

  @Test
  func presenceDiffTriggersPresenceCallbackWithJoinsAndLeaves() async throws {
    let actions = await sut.presenceChanges()

    await sut.onMessage(
      message(
        event: ChannelEvent.presenceDiff,
        payload: [
          "joins": ["user-1": ["metas": [["phx_ref": "ref-1", "name": "ana"]]]],
          "leaves": ["user-2": ["metas": [["phx_ref": "ref-2"]]]],
        ]
      )
    )

    let receivedActions = await collect(actions)
    let action = try #require(receivedActions.first)
    #expect(action.joins.keys.sorted() == ["user-1"])
    #expect(action.joins["user-1"]?.ref == "ref-1")
    #expect(action.joins["user-1"]?.state["name"]?.stringValue == "ana")
    #expect(action.leaves.keys.sorted() == ["user-2"])
    #expect(action.leaves["user-2"]?.ref == "ref-2")
  }

  @Test
  func presenceDiffWithoutJoinsOrLeavesTriggersEmptyPresenceAction() async throws {
    let actions = await sut.presenceChanges()

    await sut.onMessage(message(event: ChannelEvent.presenceDiff))

    let receivedActions = await collect(actions)
    let action = try #require(receivedActions.first)
    #expect(action.joins.isEmpty)
    #expect(action.leaves.isEmpty)
  }

  @Test
  func presenceDiffWithMalformedPresenceIsSwallowed() async {
    let actions = await sut.presenceChanges()

    await sut.onMessage(
      message(
        event: ChannelEvent.presenceDiff,
        payload: ["joins": ["user-1": ["metas": []]]]
      )
    )

    let receivedActions = await collect(actions)
    #expect(receivedActions.isEmpty)
  }

  @Test
  func presenceStateTriggersPresenceCallbackWithJoinsOnly() async throws {
    let actions = await sut.presenceChanges()

    await sut.onMessage(
      message(
        event: ChannelEvent.presenceState,
        payload: ["user-1": ["metas": [["phx_ref": "ref-1", "name": "ana"]]]]
      )
    )

    let receivedActions = await collect(actions)
    let action = try #require(receivedActions.first)
    #expect(action.joins["user-1"]?.ref == "ref-1")
    #expect(action.leaves.isEmpty)
  }

  @Test
  func presenceStateWithMalformedPresenceIsSwallowed() async {
    let actions = await sut.presenceChanges()

    await sut.onMessage(
      message(event: ChannelEvent.presenceState, payload: ["user-1": "not-a-presence"])
    )

    let receivedActions = await collect(actions)
    #expect(receivedActions.isEmpty)
  }

  private func message(
    event: String,
    payload: JSONObject = [:],
    ref: String? = nil,
    joinRef: String? = nil
  ) -> RealtimeMessageV2 {
    RealtimeMessageV2(
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
  private func recordPostgresActions() async -> AsyncStream<AnyAction> {
    let actions = await sut.postgresChanges(AnyAction.self, schema: "public", table: "messages")
    await sut.setServerChanges([
      PostgresJoinConfig(event: .all, schema: "public", table: "messages", id: 1)
    ])
    return actions
  }
}

extension RealtimeChannel {
  fileprivate func setServerChanges(_ changes: [PostgresJoinConfig]) {
    serverChanges = changes
  }
}
