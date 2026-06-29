//
//  PostgresConsumeTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@testable import RealtimeV3

// MARK: - PostgresConsumeTests

@Suite struct PostgresConsumeTests {

  // MARK: - insertYieldsRecord

  /// After subscribe (join reply assigns id 0 to the insert token), an injected
  /// postgres_changes INSERT frame with ids:[0] yields a decoded JSONValue record.
  @Test func insertYieldsRecord() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    // Register insert token BEFORE subscribe.
    let token = try await channel.inserts(schema: "public", table: "messages")

    // Auto-reply to join with a postgres_changes response that assigns id 0 to our registration.
    server.autoReplyToJoinsWithPostgres(
      postgresChanges: [
        [
          "id": .integer(0), "event": .string("INSERT"), "schema": .string("public"),
          "table": .string("messages"),
        ]
      ]
    )
    try await channel.subscribe()

    // Register the stream AFTER subscribe (but the implementation must tolerate it).
    let stream = await channel.postgresChanges(for: token)
    var iter = stream.makeAsyncIterator()

    // Inject a postgres_changes frame with ids:[0].
    server.send(
      .text(
        #"["1",null,"room:1","postgres_changes",{"ids":[0],"data":{"type":"INSERT","record":{"id":1,"text":"hi"},"columns":[],"commit_timestamp":"2024-01-01T00:00:00Z"}}]"#
      ))

    // Read first value — decoded record must be the JSONValue object.
    let value = try await iter.next()
    let obj = value?.objectValue
    #expect(obj?["text"]?.stringValue == "hi")
    #expect(obj?["id"]?.intValue == 1)
  }

  // MARK: - overlappingIdsFanOutToBothTokens

  /// Two insert tokens both mapped to server id 0; one frame with ids:[0] must
  /// fan out to both streams.
  @Test func overlappingIdsFanOutToBothTokens() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:2")

    // Two registrations — both will map to id 0 (server assigns by index, so both get the same id
    // when the reply lists two entries both with id 0, OR we use two registrations sharing id 0).
    // Here we use two registrations and the server assigns id 0 to both (overlapping).
    let tokenA = try await channel.inserts(schema: "public", table: "messages")
    let tokenB = try await channel.inserts(schema: "public", table: "messages")

    // The server can assign the same id to both — or different ids.
    // We assign both to id 0 so a single frame fans out to both.
    server.autoReplyToJoinsWithPostgres(
      postgresChanges: [
        [
          "id": .integer(0), "event": .string("INSERT"), "schema": .string("public"),
          "table": .string("messages"),
        ],
        [
          "id": .integer(0), "event": .string("INSERT"), "schema": .string("public"),
          "table": .string("messages"),
        ],
      ]
    )
    try await channel.subscribe()

    let streamA = await channel.postgresChanges(for: tokenA)
    let streamB = await channel.postgresChanges(for: tokenB)
    var iterA = streamA.makeAsyncIterator()
    var iterB = streamB.makeAsyncIterator()

    // Inject one frame — both streams should receive it.
    server.send(
      .text(
        #"["1",null,"room:2","postgres_changes",{"ids":[0],"data":{"type":"INSERT","record":{"id":42},"columns":[],"commit_timestamp":"2024-01-01T00:00:00Z"}}]"#
      ))

    let valueA = try await iterA.next()
    let valueB = try await iterB.next()

    #expect(valueA?.objectValue?["id"]?.intValue == 42)
    #expect(valueB?.objectValue?["id"]?.intValue == 42)
  }

  // MARK: - unknownTokenThrows

  /// A token created on a DIFFERENT channel passed to channelB.postgresChanges(for:)
  /// produces a stream that throws .unknownToken immediately.
  @Test func unknownTokenThrows() async throws {
    let (transport, _) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)

    let channelA = await rt.channel("room:A")
    let channelB = await rt.channel("room:B")

    // Token is for channelA's identity.
    let tokenA = try await channelA.inserts(schema: "public", table: "messages")

    // Pass the token from channelA to channelB — must throw .unknownToken.
    let stream = await channelB.postgresChanges(for: tokenA)

    do {
      for try await _ in stream {
        Issue.record("Expected .unknownToken, but stream yielded a value")
        return
      }
      Issue.record("Expected .unknownToken, but stream finished without throwing")
    } catch {
      if case .unknownToken = error as? RealtimeError {
        // Expected — test passes.
      } else {
        Issue.record("Expected .unknownToken, got: \(error)")
      }
    }
  }

  // MARK: - systemPostgresErrorFails

  /// A system event with extension "postgres_changes" and status "error" causes
  /// all postgres streams on the channel to throw .postgresSubscriptionFailed.
  @Test func systemPostgresErrorFails() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:3")

    let token = try await channel.inserts(schema: "public", table: "messages")

    server.autoReplyToJoinsWithPostgres(
      postgresChanges: [
        [
          "id": .integer(0), "event": .string("INSERT"), "schema": .string("public"),
          "table": .string("messages"),
        ]
      ]
    )
    try await channel.subscribe()

    let stream = await channel.postgresChanges(for: token)

    let receivedError = LockIsolated<Error?>(nil)
    let done = LockIsolated(false)
    let collectionTask = Task {
      do {
        for try await _ in stream {
          // No messages expected before the error.
        }
        done.withValue { $0 = true }
      } catch {
        receivedError.withValue { $0 = error }
        done.withValue { $0 = true }
      }
    }

    // Inject a system event indicating a postgres subscription failure.
    server.send(
      .text(
        #"[null,null,"room:3","system",{"extension":"postgres_changes","status":"error","message":"subscription failed"}]"#
      ))

    // Wait for the error (bounded).
    var waitIterations = 0
    while !done.value {
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      waitIterations += 1
      if waitIterations > 1000 {
        collectionTask.cancel()
        Issue.record("Postgres stream was not failed after system error event within 1s")
        return
      }
    }
    collectionTask.cancel()

    let error = receivedError.value
    if let realtimeError = error as? RealtimeError,
      case .postgresSubscriptionFailed = realtimeError
    {
      // Expected — test passes.
    } else {
      Issue.record("Expected .postgresSubscriptionFailed, got: \(String(describing: error))")
    }
  }

  // MARK: - updateYieldsPostgresUpdate

  /// Verifies that an UPDATE frame with record+old_record yields a PostgresUpdate.
  @Test func updateYieldsPostgresUpdate() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:4")

    let token = try await channel.updates(schema: "public", table: "messages")

    server.autoReplyToJoinsWithPostgres(
      postgresChanges: [
        [
          "id": .integer(0), "event": .string("UPDATE"), "schema": .string("public"),
          "table": .string("messages"),
        ]
      ]
    )
    try await channel.subscribe()

    let stream = await channel.postgresChanges(for: token)
    var iter = stream.makeAsyncIterator()

    server.send(
      .text(
        #"["1",null,"room:4","postgres_changes",{"ids":[0],"data":{"type":"UPDATE","record":{"id":1,"text":"new"},"old_record":{"id":1,"text":"old"},"columns":[],"commit_timestamp":"2024-01-01T00:00:00Z"}}]"#
      ))

    let value = try await iter.next()
    #expect(value?.record.objectValue?["text"]?.stringValue == "new")
    #expect(value?.oldRecord?.objectValue?["text"]?.stringValue == "old")
  }

  // MARK: - deleteYieldsPostgresDelete

  /// Verifies that a DELETE frame with old_record yields a PostgresDelete.
  @Test func deleteYieldsPostgresDelete() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:5")

    let token = try await channel.deletes(schema: "public", table: "messages")

    server.autoReplyToJoinsWithPostgres(
      postgresChanges: [
        [
          "id": .integer(0), "event": .string("DELETE"), "schema": .string("public"),
          "table": .string("messages"),
        ]
      ]
    )
    try await channel.subscribe()

    let stream = await channel.postgresChanges(for: token)
    var iter = stream.makeAsyncIterator()

    server.send(
      .text(
        #"["1",null,"room:5","postgres_changes",{"ids":[0],"data":{"type":"DELETE","old_record":{"id":1,"text":"deleted"},"columns":[],"commit_timestamp":"2024-01-01T00:00:00Z"}}]"#
      ))

    let value = try await iter.next()
    #expect(value?.oldRecord.objectValue?["text"]?.stringValue == "deleted")
  }

  // MARK: - anyEventYieldsPostgresChange

  /// Verifies that an AnyEvent token yields a PostgresChange<JSONValue> with the right tag.
  @Test func anyEventYieldsPostgresChange() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:6")

    let token = try await channel.changes(schema: "public", table: "messages")

    server.autoReplyToJoinsWithPostgres(
      postgresChanges: [
        [
          "id": .integer(0), "event": .string("*"), "schema": .string("public"),
          "table": .string("messages"),
        ]
      ]
    )
    try await channel.subscribe()

    let stream = await channel.postgresChanges(for: token)
    var iter = stream.makeAsyncIterator()

    server.send(
      .text(
        #"["1",null,"room:6","postgres_changes",{"ids":[0],"data":{"type":"INSERT","record":{"id":99},"columns":[],"commit_timestamp":"2024-01-01T00:00:00Z"}}]"#
      ))

    let value = try await iter.next()
    if case .insert(let record) = value {
      #expect(record.objectValue?["id"]?.intValue == 99)
    } else {
      Issue.record("Expected .insert case, got: \(String(describing: value))")
    }
  }
}

// MARK: - TransportServer helpers for postgres

extension TransportServer {
  /// Auto-replies to joins with a postgres_changes response that includes server-assigned IDs.
  func autoReplyToJoinsWithPostgres(postgresChanges: [[String: AnyJSON]]) {
    let response: [String: AnyJSON] = [
      "postgres_changes": .array(postgresChanges.map { .object($0) })
    ]
    autoReplyToJoins(status: "ok", response: response)
  }
}
