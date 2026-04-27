//
//  PostgresChangesTests.swift
//  _RealtimeTests
//
//  Created by Guilherme Souza on 24/04/25.
//

import ConcurrencyExtras
import Foundation
import Testing
@testable import _Realtime

// File-scope types for RealtimeTable conformances — required for Swift Testing macro compatibility.
private struct PGUser: RealtimeTable {
  static let schema = "public"
  static let tableName = "users"
  static func columnName<V>(for kp: KeyPath<PGUser, V>) -> String {
    switch kp {
    case \Self.id: return "id"
    case \Self.name: return "name"
    default: return "unknown"
    }
  }
  var id: UUID
  var name: String
}

private struct PGItem: RealtimeTable {
  static let schema = "public"
  static let tableName = "items"
  static func columnName<V>(for kp: KeyPath<PGItem, V>) -> String { "status" }
  var status: String
}

private struct PGMessage: Codable, Sendable {
  let id: Int
  let text: String
}

@Suite struct PostgresChangesTests {

  @Test func filterEqEncodesCorrectly() {
    let filter = Filter.eq(\PGUser.id, UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    #expect(filter.wireValue == "id=eq.00000000-0000-0000-0000-000000000001")
  }

  @Test func filterInEncodesCorrectly() {
    let filter = Filter.in(\PGItem.status, ["active", "pending"])
    #expect(filter.wireValue == "status=in.(active,pending)")
  }

  @Test func untypedFilterEncodesCorrectly() {
    let filter = UntypedFilter.eq("room_id", "abc-123")
    #expect(filter.wireValue == "room_id=eq.abc-123")
  }

  @Test func postgresChangeDecodesInsert() throws {
    let payload: [String: JSONValue] = [
      "data": .object([
        "type": "INSERT",
        "record": .object(["id": .int(1), "text": .string("hello")]),
        "old_record": .null,
        "columns": .array([]),
        "commit_timestamp": .string("2026-01-01T00:00:00Z"),
      ]),
      "ids": .array([.int(1)]),
    ]

    let change = try PostgresChange<PGMessage>.decode(from: payload)
    if case .insert(let row) = change {
      #expect(row.id == 1)
      #expect(row.text == "hello")
    } else {
      Issue.record("Expected .insert, got \(change)")
    }
  }

  @Test func postgresChangeDecodesUpdate() throws {
    let payload: [String: JSONValue] = [
      "data": .object([
        "type": "UPDATE",
        "record": .object(["id": .int(1), "text": .string("updated")]),
        "old_record": .object(["id": .int(1), "text": .string("original")]),
        "columns": .array([]),
        "commit_timestamp": .string("2026-01-01T00:00:00Z"),
      ])
    ]
    let change = try PostgresChange<PGMessage>.decode(from: payload)
    if case .update(let old, let new) = change {
      #expect(old.text == "original")
      #expect(new.text == "updated")
    } else {
      Issue.record("Expected .update")
    }
  }

  @Test func postgresChangeDecodesDelete() throws {
    let payload: [String: JSONValue] = [
      "data": .object([
        "type": "DELETE",
        "record": .null,
        "old_record": .object(["id": .int(1), "text": .string("deleted")]),
        "columns": .array([]),
        "commit_timestamp": .string("2026-01-01T00:00:00Z"),
      ])
    ]
    let change = try PostgresChange<PGMessage>.decode(from: payload)
    if case .delete(let old) = change {
      #expect(old.text == "deleted")
    } else {
      Issue.record("Expected .delete")
    }
  }

  // MARK: - Test 1: Additional filter operator encoding

  @Test func filterNeqAndGtEncode() {
    struct Post: RealtimeTable {
      static let schema = "public"
      static let tableName = "posts"
      static func columnName<V>(for kp: KeyPath<Post, V>) -> String {
        switch kp {
        case \Self.status: return "status"
        case \Self.viewCount: return "view_count"
        default: return "unknown"
        }
      }
      var status: String
      var viewCount: Int
    }
    let neqFilter = Filter.neq(\Post.status, "draft")
    #expect(neqFilter.wireValue == "status=neq.draft")

    let gtFilter = Filter.gt(\Post.viewCount, 100)
    #expect(gtFilter.wireValue == "view_count=gt.100")
  }

  // MARK: - Test 2: Per-event convenience streams

  @Test func perEventConvenienceStreams() async throws {
    struct ConvMessage: Codable, Sendable, RealtimeTable {
      static let schema = "public"
      static let tableName = "messages"
      static func columnName<V>(for kp: KeyPath<ConvMessage, V>) -> String { "id" }
      let id: Int
      let text: String
    }

    let testURL = URL(string: "ws://localhost:4000/realtime/v1")!
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    let autoReplyTask = Task { [server] in
      do {
        for try await frame in server.receivedFrames {
          guard case .text(let text) = frame,
            let msg = try? PhoenixSerializer.decodeText(text),
            msg.event == "phx_join"
          else { continue }
          let reply = PhoenixMessage(
            joinRef: msg.joinRef, ref: msg.ref, topic: msg.topic,
            event: "phx_reply", payload: ["status": "ok", "response": .object([:])]
          )
          await server.send(.text(try! PhoenixSerializer.encodeText(reply)))
        }
      } catch {
        // stream ended
      }
    }
    defer { autoReplyTask.cancel() }

    let channel = await realtime.channel("room:convenience")
    let inserts = LockIsolated<[ConvMessage]>([])
    let updates = LockIsolated<[(old: ConvMessage, new: ConvMessage)]>([])
    let deletes = LockIsolated<[ConvMessage]>([])

    let insertsStream = await channel.inserts(into: ConvMessage.self)
    let updatesStream = await channel.updates(of: ConvMessage.self)
    let deletesStream = await channel.deletes(from: ConvMessage.self)

    let t1 = Task {
      for try await m in insertsStream {
        inserts.withValue { $0.append(m) }
      }
    }
    let t2 = Task {
      for try await p in updatesStream {
        updates.withValue { $0.append(p) }
      }
    }
    let t3 = Task {
      for try await m in deletesStream {
        deletes.withValue { $0.append(m) }
      }
    }
    defer { t1.cancel(); t2.cancel(); t3.cancel() }

    try await Task.sleep(for: .milliseconds(50))

    let record: JSONValue = .object(["id": .int(1), "text": .string("hello")])
    let oldRecord: JSONValue = .object(["id": .int(1), "text": .string("old")])

    func makePayload(type: String, rec: JSONValue, old: JSONValue) -> [String: JSONValue] {
      [
        "data": .object([
          "type": .string(type),
          "record": rec,
          "old_record": old,
          "columns": .array([]),
          "commit_timestamp": .string("2026-01-01T00:00:00Z"),
        ])
      ]
    }

    let events: [(String, JSONValue, JSONValue)] = [
      ("INSERT", record, .null),
      ("UPDATE", record, oldRecord),
      ("DELETE", .null, oldRecord),
    ]
    for (eventType, rec, old) in events {
      let push = PhoenixMessage(
        joinRef: nil, ref: nil, topic: "room:convenience",
        event: "postgres_changes",
        payload: makePayload(type: eventType, rec: rec, old: old)
      )
      await server.send(.text(try! PhoenixSerializer.encodeText(push)))
    }

    try await Task.sleep(for: .milliseconds(100))

    #expect(inserts.value.count == 1)
    #expect(inserts.value.first?.text == "hello")
    #expect(updates.value.count == 1)
    #expect(updates.value.first?.new.text == "hello")
    #expect(deletes.value.count == 1)
    #expect(deletes.value.first?.text == "old")
  }

  // MARK: - Test 3: Typed changes(to:) live stream

  @Test func typedChangesStreamDecodesLivePayload() async throws {
    struct TypedMessage: Codable, Sendable, RealtimeTable {
      static let schema = "public"
      static let tableName = "messages"
      static func columnName<V>(for kp: KeyPath<TypedMessage, V>) -> String { "id" }
      let id: Int
      let body: String
    }

    let testURL = URL(string: "ws://localhost:4000/realtime/v1")!
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    let autoReplyTask = Task { [server] in
      do {
        for try await frame in server.receivedFrames {
          guard case .text(let text) = frame,
            let msg = try? PhoenixSerializer.decodeText(text),
            msg.event == "phx_join"
          else { continue }
          let reply = PhoenixMessage(
            joinRef: msg.joinRef, ref: msg.ref, topic: msg.topic,
            event: "phx_reply", payload: ["status": "ok", "response": .object([:])]
          )
          await server.send(.text(try! PhoenixSerializer.encodeText(reply)))
        }
      } catch {
        // stream ended
      }
    }
    defer { autoReplyTask.cancel() }

    let channel = await realtime.channel("room:typed")
    let stream = await channel.changes(to: TypedMessage.self)
    let received = LockIsolated<[PostgresChange<TypedMessage>]>([])
    let task = Task {
      for try await c in stream { received.withValue { $0.append(c) } }
    }
    defer { task.cancel() }

    try await Task.sleep(for: .milliseconds(50))

    let insertPayload: [String: JSONValue] = [
      "data": .object([
        "type": "INSERT",
        "record": .object(["id": .int(7), "body": .string("typed!")]),
        "old_record": .null,
        "columns": .array([]),
        "commit_timestamp": .string("2026-01-01T00:00:00Z"),
      ])
    ]
    let push = PhoenixMessage(
      joinRef: nil, ref: nil, topic: "room:typed",
      event: "postgres_changes", payload: insertPayload
    )
    await server.send(.text(try! PhoenixSerializer.encodeText(push)))

    try await Task.sleep(for: .milliseconds(50))

    #expect(received.value.count == 1)
    if case .insert(let row) = received.value.first {
      #expect(row.id == 7)
      #expect(row.body == "typed!")
    } else {
      Issue.record("Expected .insert, got \(String(describing: received.value.first))")
    }
  }

  @Test func untypedChangesStreamReceivesPayload() async throws {
    let testURL = URL(string: "ws://localhost:4000/realtime/v1")!
    let (transport, server) = InMemoryTransport.pair()
    let realtime = Realtime(url: testURL, apiKey: .literal("key"), transport: transport)
    try await realtime.connect()

    let autoReplyTask = Task { [server] in
      do {
        for try await frame in server.receivedFrames {
          guard case .text(let text) = frame,
            let msg = try? PhoenixSerializer.decodeText(text),
            msg.event == "phx_join"
          else { continue }
          let reply = PhoenixMessage(
            joinRef: msg.joinRef, ref: msg.ref, topic: msg.topic,
            event: "phx_reply", payload: ["status": "ok", "response": .object([:])]
          )
          await server.send(.text(try! PhoenixSerializer.encodeText(reply)))
        }
      } catch {
        // stream ended
      }
    }
    defer { autoReplyTask.cancel() }

    let channel = await realtime.channel("room:pg")
    let stream = await channel.changes(schema: "public", table: "messages")
    let received = LockIsolated<[PostgresChange<[String: JSONValue]>]>([])
    let task = Task {
      for try await change in stream { received.withValue { $0.append(change) } }
    }
    defer { task.cancel() }

    try await Task.sleep(for: .milliseconds(50))

    // Server pushes a postgres_changes event
    let insertPayload: [String: JSONValue] = [
      "data": .object([
        "type": "INSERT",
        "record": .object(["id": .int(42), "body": .string("test")]),
        "old_record": .null,
        "columns": .array([]),
        "commit_timestamp": .string("2026-01-01T00:00:00Z"),
      ])
    ]
    let push = PhoenixMessage(
      joinRef: nil, ref: nil, topic: "room:pg",
      event: "postgres_changes", payload: insertPayload
    )
    await server.send(.text(try! PhoenixSerializer.encodeText(push)))

    try await Task.sleep(for: .milliseconds(50))
    #expect(received.value.count == 1)
    if case .insert(let row) = received.value.first {
      #expect(row["id"] == .int(42))
    } else {
      Issue.record("Expected insert")
    }
  }
}
