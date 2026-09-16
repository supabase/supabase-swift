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
@testable import RealtimeV2

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Characterization tests for ``RealtimeChannelV2/onMessage(_:)``.
///
/// These pin the dispatcher's current behavior for every event type it handles,
/// including the paths that swallow a decoding error and the ones that
/// deliberately do nothing, so the switch can be restructured without changing
/// what reaches the callbacks.
@Suite
struct RealtimeChannelOnMessageTests {
  let socket: SpyRealtimeClient
  let sut: RealtimeChannelV2

  /// A commit timestamp and its wire form, round-tripped through the SDK's own
  /// encoder so the fixture can't drift from ``JSONValue/decoder``'s format.
  let commitTimestamp: Date
  let commitTimestampJSON: JSONValue

  init() throws {
    let socket = SpyRealtimeClient()
    self.socket = socket
    self.sut = RealtimeChannelV2(
      topic: "realtime:public:messages",
      config: RealtimeChannelConfig(
        broadcast: BroadcastJoinConfig(),
        presence: PresenceJoinConfig(),
        isPrivate: false
      ),
      socket: socket,
      logger: supabaseDefaultLogger(label: "io.supabase.realtime")
    )

    let timestamp = Date(timeIntervalSince1970: 1_703_592_000)
    self.commitTimestamp = timestamp
    self.commitTimestampJSON = try JSONValue(timestamp)
  }

  // MARK: - Unknown event

  @Test
  func unknownEventDispatchesNothing() async {
    let systemMessages = recordSystemMessages()
    let broadcasts = recordBroadcasts(event: "*")

    await sut.onMessage(message(event: "not_a_channel_event"))

    #expect(systemMessages.value.isEmpty)
    #expect(broadcasts.value.isEmpty)
  }

  // MARK: - system

  @Test
  func systemOKTriggersSystemCallback() async {
    let systemMessages = recordSystemMessages()
    let sent = message(event: ChannelEvent.system, payload: ["status": "ok"])

    await sut.onMessage(sent)

    #expect(systemMessages.value == [sent])
    // `didReceiveSubscribedOK` only promotes a channel that is already
    // `.subscribing`, so a system.ok on its own cannot subscribe a channel.
    #expect(sut.status == .unsubscribed)
  }

  @Test
  func systemErrorStillTriggersSystemCallback() async {
    let systemMessages = recordSystemMessages()
    let sent = message(event: ChannelEvent.system, payload: ["status": "error"])

    await sut.onMessage(sent)

    #expect(systemMessages.value == [sent])
  }

  @Test
  func systemWithoutStatusStillTriggersSystemCallback() async {
    let systemMessages = recordSystemMessages()
    let sent = message(event: ChannelEvent.system)

    await sut.onMessage(sent)

    #expect(systemMessages.value == [sent])
  }

  // MARK: - phx_reply

  @Test
  func replyWithoutRefIsSwallowed() async {
    await sut.onMessage(message(event: ChannelEvent.reply, payload: ["status": "ok"]))

    #expect(sut.callbackManager.serverChanges.isEmpty)
  }

  @Test
  func replyWithoutStatusIsSwallowed() async {
    await sut.onMessage(message(event: ChannelEvent.reply, ref: "1"))

    #expect(sut.callbackManager.serverChanges.isEmpty)
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

    #expect(sut.callbackManager.serverChanges.isEmpty)
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

    let change = try #require(sut.callbackManager.serverChanges.first)
    #expect(sut.callbackManager.serverChanges.count == 1)
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

    #expect(sut.callbackManager.serverChanges.isEmpty)
  }

  // MARK: - postgres_changes

  @Test
  func postgresChangesWithoutDataIsIgnored() async {
    let actions = recordPostgresActions()

    await sut.onMessage(message(event: ChannelEvent.postgresChanges, payload: ["ids": [1]]))

    #expect(actions.value.isEmpty)
  }

  @Test
  func postgresChangesInsertDispatchesInsertAction() async throws {
    let actions = recordPostgresActions()

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

    let action = try #require(actions.value.first)
    #expect(actions.value.count == 1)
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
    let actions = recordPostgresActions()

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

    let action = try #require(actions.value.first)
    guard case .update(let update) = action else {
      Issue.record("Expected .update, got \(action)")
      return
    }
    #expect(update.record == ["id": 1, "body": "new"])
    #expect(update.oldRecord == ["id": 1, "body": "old"])
  }

  @Test
  func postgresChangesUpdateWithoutRecordsFallsBackToEmptyObjects() async throws {
    let actions = recordPostgresActions()

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

    let action = try #require(actions.value.first)
    guard case .update(let update) = action else {
      Issue.record("Expected .update, got \(action)")
      return
    }
    #expect(update.record.isEmpty)
    #expect(update.oldRecord.isEmpty)
  }

  @Test
  func postgresChangesDeleteDispatchesDeleteAction() async throws {
    let actions = recordPostgresActions()

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

    let action = try #require(actions.value.first)
    guard case .delete(let delete) = action else {
      Issue.record("Expected .delete, got \(action)")
      return
    }
    #expect(delete.oldRecord == ["id": 1])
  }

  @Test
  func postgresChangesWithUnknownTypeIsSwallowed() async {
    let actions = recordPostgresActions()

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

    #expect(actions.value.isEmpty)
  }

  @Test
  func postgresChangesWithMalformedDataIsSwallowed() async {
    let actions = recordPostgresActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.postgresChanges,
        payload: ["ids": [1], "data": ["type": "INSERT"]]
      )
    )

    #expect(actions.value.isEmpty)
  }

  @Test
  func postgresChangesWithoutIdsMatchesNoCallback() async {
    let actions = recordPostgresActions()

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

    #expect(actions.value.isEmpty)
  }

  // MARK: - broadcast

  @Test
  func broadcastTriggersMatchingBroadcastCallback() async throws {
    let broadcasts = recordBroadcasts(event: "message")

    await sut.onMessage(
      message(
        event: ChannelEvent.broadcast,
        payload: ["event": "message", "payload": ["body": "hi"]]
      )
    )

    let received = try #require(broadcasts.value.first)
    #expect(broadcasts.value.count == 1)
    // The whole message payload is forwarded, not just the inner `payload`.
    #expect(received["event"]?.stringValue == "message")
    #expect(received["payload"]?.objectValue?["body"]?.stringValue == "hi")
  }

  @Test
  func broadcastWithoutEventIsSwallowed() async {
    let broadcasts = recordBroadcasts(event: "*")

    await sut.onMessage(
      message(event: ChannelEvent.broadcast, payload: ["payload": ["body": "hi"]])
    )

    #expect(broadcasts.value.isEmpty)
  }

  // MARK: - phx_close

  @Test
  func closeWithoutJoinRefRemovesChannelFromSocket() async {
    await sut.onMessage(message(event: ChannelEvent.close))

    #expect(socket.removedTopics == [sut.topic])
  }

  @Test
  func closeForStaleJoinRefDoesNotRemoveChannel() async {
    // The channel never joined, so its `joinRef` is nil and any tagged close
    // belongs to a previous incarnation of the topic (issue #1145).
    await sut.onMessage(message(event: ChannelEvent.close, joinRef: "stale-ref"))

    #expect(socket.removedTopics.isEmpty)
  }

  // MARK: - phx_error

  @Test
  func errorClosesChannelWithoutRemovingItFromSocket() async {
    await sut.onMessage(message(event: ChannelEvent.error))

    #expect(socket.removedTopics.isEmpty)
    #expect(sut.status == .unsubscribed)
  }

  // MARK: - presence_diff

  @Test
  func presenceDiffTriggersPresenceCallbackWithJoinsAndLeaves() async throws {
    let actions = recordPresenceActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.presenceDiff,
        payload: [
          "joins": ["user-1": ["metas": [["phx_ref": "ref-1", "name": "ana"]]]],
          "leaves": ["user-2": ["metas": [["phx_ref": "ref-2"]]]],
        ]
      )
    )

    let action = try #require(actions.value.first)
    #expect(action.joins.keys.sorted() == ["user-1"])
    #expect(action.joins["user-1"]?.ref == "ref-1")
    #expect(action.joins["user-1"]?.state["name"]?.stringValue == "ana")
    #expect(action.leaves.keys.sorted() == ["user-2"])
    #expect(action.leaves["user-2"]?.ref == "ref-2")
  }

  @Test
  func presenceDiffWithoutJoinsOrLeavesTriggersEmptyPresenceAction() async throws {
    let actions = recordPresenceActions()

    await sut.onMessage(message(event: ChannelEvent.presenceDiff))

    let action = try #require(actions.value.first)
    #expect(action.joins.isEmpty)
    #expect(action.leaves.isEmpty)
  }

  @Test
  func presenceDiffWithMalformedPresenceIsSwallowed() async {
    let actions = recordPresenceActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.presenceDiff,
        payload: ["joins": ["user-1": ["metas": []]]]
      )
    )

    #expect(actions.value.isEmpty)
  }

  // MARK: - presence_state

  @Test
  func presenceStateTriggersPresenceCallbackWithJoinsOnly() async throws {
    let actions = recordPresenceActions()

    await sut.onMessage(
      message(
        event: ChannelEvent.presenceState,
        payload: ["user-1": ["metas": [["phx_ref": "ref-1", "name": "ana"]]]]
      )
    )

    let action = try #require(actions.value.first)
    #expect(action.joins["user-1"]?.ref == "ref-1")
    #expect(action.leaves.isEmpty)
  }

  @Test
  func presenceStateWithMalformedPresenceIsSwallowed() async {
    let actions = recordPresenceActions()

    await sut.onMessage(
      message(event: ChannelEvent.presenceState, payload: ["user-1": "not-a-presence"])
    )

    #expect(actions.value.isEmpty)
  }

  // MARK: - Helpers

  private func message(
    event: String,
    payload: JSONObject = [:],
    ref: String? = nil,
    joinRef: String? = nil
  ) -> RealtimeMessageV2 {
    RealtimeMessageV2(
      joinRef: joinRef,
      ref: ref,
      topic: sut.topic,
      event: event,
      payload: payload
    )
  }

  private func recordSystemMessages() -> LockIsolated<[RealtimeMessageV2]> {
    let messages = LockIsolated([RealtimeMessageV2]())
    sut.callbackManager.addSystemCallback { message in
      messages.withValue { $0.append(message) }
    }
    return messages
  }

  private func recordBroadcasts(event: String) -> LockIsolated<[JSONObject]> {
    let payloads = LockIsolated([JSONObject]())
    sut.callbackManager.addBroadcastCallback(event: event) { payload in
      payloads.withValue { $0.append(payload) }
    }
    return payloads
  }

  private func recordPresenceActions() -> LockIsolated<[any PresenceAction]> {
    let actions = LockIsolated([any PresenceAction]())
    sut.callbackManager.addPresenceCallback { action in
      actions.withValue { $0.append(action) }
    }
    return actions
  }

  /// Registers a postgres callback under server-change id `1`, matching the
  /// `"ids": [1]` used by the postgres_changes fixtures.
  private func recordPostgresActions() -> LockIsolated<[AnyAction]> {
    let filter = PostgresJoinConfig(
      event: .all,
      schema: "public",
      table: "messages",
      id: 1
    )
    sut.callbackManager.setServerChanges(changes: [filter])

    let actions = LockIsolated([AnyAction]())
    sut.callbackManager.addPostgresCallback(filter: filter) { action in
      actions.withValue { $0.append(action) }
    }
    return actions
  }
}

/// Records the `_remove` calls `onMessage` makes on a `phx_close`.
final class SpyRealtimeClient: RealtimeClientProtocol, @unchecked Sendable {
  private let _removedTopics = LockIsolated([String]())

  let options = RealtimeClientOptions()
  let http = HTTPClient(
    transport: RecordingTransport { _, _ in (HTTPResponse(status: .ok), Data()) }
  )
  let clock: any Clock<Duration> = ContinuousClock()
  let status: RealtimeClientStatus = .connected

  var removedTopics: [String] { _removedTopics.value }

  func broadcastURL(topic: String, event: String, isPrivate: Bool) -> URL {
    URL(string: "https://test.supabase.co/api/broadcast")!
  }

  func connect() async {}
  func push(_ message: RealtimeMessageV2) {}
  func pushBroadcast(
    joinRef: String?, ref: String?, topic: String, event: String, jsonPayload: JSONObject
  ) {}
  func pushBroadcast(
    joinRef: String?, ref: String?, topic: String, event: String, binaryPayload: Data
  ) {}
  func _getAccessToken() async -> String? { nil }
  func makeRef() -> String { UUID().uuidString }

  func _remove(_ channel: any RealtimeChannelProtocol) {
    _removedTopics.withValue { $0.append(channel.topic) }
  }
}
