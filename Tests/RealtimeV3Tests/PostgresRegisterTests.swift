//
//  PostgresRegisterTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import Helpers
import Testing

@testable import RealtimeV3

@Suite struct PostgresRegisterTests {

  // MARK: - registrationBakedIntoJoin

  /// Registers an insert token before subscribe and asserts the phx_join
  /// postgres_changes array carries the expected entry.
  @Test func registrationBakedIntoJoin() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:1")

    // Register before subscribe.
    let _ = try await channel.inserts(
      schema: "public", table: "messages",
      filter: .eq("room_id", 1)
    )

    // Capture client-sent frames so we can inspect the phx_join before replying.
    let sentFrames = server.subscribeToClientFrames()

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Pull the first text frame that contains phx_join.
    var joinText: String?
    for await frame in sentFrames {
      guard case .text(let text) = frame, text.contains("phx_join") else { continue }
      joinText = text
      break
    }

    guard let joinText else {
      Issue.record("No phx_join frame observed")
      return
    }

    // Decode as JSON array: [joinRef, ref, topic, event, payload]
    guard let data = joinText.data(using: .utf8),
      let array = try? JSONDecoder().decode([AnyJSON].self, from: data),
      array.count >= 5
    else {
      Issue.record("Could not decode phx_join frame as JSON array")
      return
    }

    // payload is array[4]; navigate config.postgres_changes
    guard let payload = array[4].objectValue,
      let config = payload["config"]?.objectValue,
      let changes = config["postgres_changes"]?.arrayValue
    else {
      Issue.record("Could not navigate to config.postgres_changes in payload: \(array[4])")
      return
    }

    #expect(changes.count == 1, "Expected 1 postgres_changes entry, got \(changes.count)")

    guard let entry = changes.first?.objectValue else {
      Issue.record("postgres_changes[0] is not an object")
      return
    }

    #expect(entry["event"]?.stringValue == "INSERT")
    #expect(entry["schema"]?.stringValue == "public")
    #expect(entry["table"]?.stringValue == "messages")
    #expect(entry["filter"]?.stringValue == "room_id=eq.1")
  }

  // MARK: - registerAfterJoinThrows

  /// Registering after subscribe() reaches .joined throws .cannotRegisterAfterJoin.
  @Test func registerAfterJoinThrows() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:2")

    server.autoReplyToJoins()
    try await channel.subscribe()

    // Channel is now .joined — registration must throw.
    do {
      _ = try await channel.inserts(schema: "public", table: "messages")
      Issue.record("Expected cannotRegisterAfterJoin, but inserts() returned normally")
    } catch {
      if case .cannotRegisterAfterJoin = error {
        // Expected — test passes.
      } else {
        Issue.record("Expected cannotRegisterAfterJoin, got: \(error)")
      }
    }
  }

  // MARK: - registrationsReplayAfterLeave

  /// Registrations persist across leave/resubscribe cycles: the second phx_join
  /// still carries the postgres_changes entry registered before the first subscribe.
  @Test func registrationsReplayAfterLeave() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    let channel = await rt.channel("room:3")

    // Register once, before first subscribe.
    let _ = try await channel.inserts(
      schema: "public", table: "events"
    )

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    try await channel.subscribe()
    try await channel.leave()

    // Resubscribe — registrations must replay.
    let sentFrames = server.subscribeToClientFrames()
    try await channel.subscribe()

    // Capture the next phx_join (from the resubscribe).
    var joinText: String?
    for await frame in sentFrames {
      guard case .text(let text) = frame, text.contains("phx_join") else { continue }
      joinText = text
      break
    }

    guard let joinText else {
      Issue.record("No phx_join frame observed on resubscribe")
      return
    }

    guard let data = joinText.data(using: .utf8),
      let array = try? JSONDecoder().decode([AnyJSON].self, from: data),
      array.count >= 5,
      let payload = array[4].objectValue,
      let config = payload["config"]?.objectValue,
      let changes = config["postgres_changes"]?.arrayValue
    else {
      Issue.record("Could not decode postgres_changes from resubscribe phx_join")
      return
    }

    #expect(changes.count == 1, "Expected 1 postgres_changes entry on resubscribe")

    guard let entry = changes.first?.objectValue else {
      Issue.record("postgres_changes[0] is not an object on resubscribe")
      return
    }

    #expect(entry["event"]?.stringValue == "INSERT")
    #expect(entry["schema"]?.stringValue == "public")
    #expect(entry["table"]?.stringValue == "events")
  }
}
