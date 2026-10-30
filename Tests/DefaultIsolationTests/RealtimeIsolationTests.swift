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
/// `.defaultIsolation(MainActor.self)`. `RealtimeClient` and `RealtimeChannel` are actors, so each
/// member read below needs one `await` from the main actor and nothing more. Nothing here opens a
/// socket.
@Suite
struct RealtimeIsolationTests {
  /// A plain `Decodable` row with a main-actor-isolated conformance. `PostgresRow.decode(as:)` and
  /// `TypedPostgresChange.row()` run on the caller's actor, so it needs no `nonisolated`.
  struct Row: Decodable {
    var id: Int
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
      let typed = channel.postgresChanges(of: Row.self, table: "rooms")
      let raw = channel.postgresChanges(event: .insert, table: "rooms")
      try await channel.subscribe()

      for await change in typed { rows.append(try change.row()) }
      for await change in raw {
        changes.append(change)
        if let record = change.record { rows.append(try record.decode(as: Row.self)) }
      }
      for await state in channel.presenceStates() { presenceCount = state.entries.count }
      for await message in channel.broadcasts(event: "ping") { _ = message.event }

      isConnected = await client.status.isConnected
      channelError = channel.status.error
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
