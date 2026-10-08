//
//  RealtimeIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import HTTPTypes
import Supabase
import Testing

/// Compile-time coverage of the Realtime v3 flows from a module that opts into
/// `.defaultIsolation(MainActor.self)`. Nothing here opens a socket.
@Suite
struct RealtimeIsolationTests {
  struct Row: Decodable {
    var id: Int
  }

  /// `WebSocketTransport` refines `Sendable`, so a conformance cannot be main-actor isolated. A
  /// consumer under default isolation opts the type out with `nonisolated`.
  nonisolated struct RefusingTransport: WebSocketTransport {
    func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
      throw RealtimeError(kind: .transport, message: "refused")
    }
  }

  final class Model {
    let client = RealtimeClient(
      url: URL(string: "https://project-ref.supabase.co/realtime/v1")!,
      options: {
        var options = RealtimeClientOptions()
        options.webSocketTransport = RefusingTransport()
        options.handleAppLifecycle = false
        return options
      }()
    )
    var rows: [Row] = []
    var changes: [PostgresChange] = []
    var presenceCount = 0

    func run() async throws {
      let channel = client.channel("room") { $0.isPrivate = false }
      let typed = channel.postgresChanges(of: Row.self, table: "rooms")
      let raw = channel.postgresChanges(event: .insert, table: "rooms")
      try await channel.subscribe()

      for await change in typed { rows.append(try change.row()) }
      for await change in raw {
        changes.append(change)
        if let record = change.record { rows.append(try record.decode(as: Row.self)) }
      }
      for await state in channel.presence.states { presenceCount = state.entries.count }
      for await message in channel.broadcasts(event: "ping") { _ = message.event }

      _ = client.status.isConnected
      _ = channel.status.error
    }
  }

  @Test
  func realtimeIsUsableFromAMainActorIsolatedModule() {
    let model = Model()
    #expect(model.rows.isEmpty)
    #expect(!model.client.status.isConnected)
    let channel = model.client.channel("room")
    #expect(channel.status.error == nil)
  }
}
