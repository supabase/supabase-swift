//
//  RealtimeIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 29/10/26.
//

import Foundation
import Supabase
import Testing

/// Compile-time coverage of the Realtime v3 flows from a module that opts into
/// `.defaultIsolation(MainActor.self)`. Reads and stream subscriptions on `RealtimeClient` and
/// `RealtimeChannel` are `async`: the client actor owns the state. The generic entry points encode
/// and decode on the caller's actor, so app types with main-actor conformances need no annotation.
/// Nothing here opens a socket.
@Suite
struct RealtimeIsolationTests {
  /// A plain `Decodable` row with a main-actor-isolated conformance. `PostgresRow.decode(as:)` and
  /// `TypedPostgresChange.row()` run on the caller's actor, so it needs no `nonisolated`.
  struct Row: Decodable {
    var id: Int
  }

  /// A plain `Encodable` payload with a main-actor-isolated conformance. `broadcast`, `track`, and
  /// `httpSend` encode it on the caller's actor, so it needs no `nonisolated`.
  struct ChatMessage: Encodable {
    var text: String
  }

  /// `WebSocketTransport` refines `Sendable`, so its conformance cannot be main-actor isolated. A
  /// consumer under default isolation opts the type out with `nonisolated`, as intended.
  nonisolated struct RefusingTransport: WebSocketTransport {
    func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
      throw RealtimeError(kind: .transport, message: "refused", isRetryable: false)
    }
  }

  final class Model {
    let client = RealtimeClient(
      url: URL(string: "https://project-ref.supabase.co/realtime/v1")!,
      options: RealtimeClientOptions(
        webSocketTransport: RefusingTransport(), handleAppLifecycle: false)
    )
    var rows: [Row] = []
    var changes: [PostgresChange] = []
    var presenceCount = 0
    var isConnected = false
    var channelError: RealtimeError?

    func run() async throws {
      let channel = await client.channel("room") { $0.isPrivate = false }
      let typed = await channel.postgresChanges(of: Row.self, table: "rooms")
      let raw = await channel.postgresChanges(event: .insert, table: "rooms")
      let states = await channel.presenceStates()
      let messages = await channel.broadcasts(event: "ping")
      try await channel.subscribe()
      try await channel.broadcast(event: "message", payload: ChatMessage(text: "hi"))
      try await channel.track(ChatMessage(text: "here"))
      try await channel.httpSend(event: "message", payload: ChatMessage(text: "hi"))

      for await change in typed { rows.append(try change.row()) }
      for await change in raw {
        changes.append(change)
        if let record = change.record { rows.append(try record.decode(as: Row.self)) }
      }
      for await state in states { presenceCount = state.entries.count }
      for await message in messages { _ = message.event }

      isConnected = await client.status.isConnected
      channelError = await channel.status.error
    }
  }

  @Test
  func realtimeIsUsableFromAMainActorIsolatedModule() async {
    let model = Model()
    #expect(model.rows.isEmpty)
    #expect(await !model.client.status.isConnected)
    let channel = await model.client.channel("room")
    #expect(await channel.status.error == nil)
  }
}
