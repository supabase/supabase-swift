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
/// `MessageRoutingTests` covers the routing itself.
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
  func systemOKTriggersSystemCallback() async {
    let systemMessages = await sut.systemMessages()
    let sent = message(event: ChannelEvent.system, payload: ["status": "ok"])

    await sut.onMessage(sent)

    let receivedSystemMessages = await collect(systemMessages)
    #expect(receivedSystemMessages == [sent])
    #expect(await sut.status == .unsubscribed)
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

extension RealtimeChannel {
  fileprivate func setJoinRef(_ ref: String?) {
    joinRef = ref
  }
}
