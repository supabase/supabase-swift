//
//  SupabaseIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 05/11/26.
//

import Foundation
import PostgrestMacros
@_spi(Experimental) import Supabase

/// A `@Table` type with a primary key, so `LiveQuery` and `SupabaseClient.stream(_:where:)` can
/// match changes to rows. Declared under `.defaultIsolation(MainActor.self)`.
@Table("rooms")
struct IsolationRoom {
  @PrimaryKey var id: Int
  var name: String
}

/// Calls every public async Supabase API from the main actor, since this target compiles with
/// `.defaultIsolation(MainActor.self)`. Nothing here runs: if a call stops compiling, the build
/// fails. `scripts/check-isolation-coverage.sh` checks that each API has a call.
enum SupabaseIsolationTests {
  static func client(_ client: SupabaseClient) async throws {
    let url = URL(string: "myapp://callback")!

    let channel = await client.channel("room")
    _ = await client.channel("room") { $0.broadcast.receiveOwnMessages = true }
    _ = await client.channels
    _ = try await client.handleRedirect(url)
    await client.removeChannel(channel)
    await client.removeAllChannels()
  }

  static func typedStream(_ client: SupabaseClient) async throws {
    for try await rooms in client.stream(IsolationRoom.self) { _ = rooms }
    for try await rooms in client.stream(IsolationRoom.self, where: { $0.id.gt(0) }) {
      _ = rooms
    }
  }

  static func typedPostgresChanges(_ channel: RealtimeChannel) async throws {
    for await change in await channel.postgresChanges(for: IsolationRoom.self) {
      _ = try change.row()
    }
    for await change in await channel.postgresChanges(
      for: IsolationRoom.self, event: .insert, where: { $0.id.eq(1) })
    {
      _ = try change.row()
    }
  }

  #if canImport(Observation)
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    static func liveQuery(_ client: SupabaseClient) async {
      let query = LiveQuery(client, IsolationRoom.self)
      await query.run()
      let filtered = LiveQuery(client, IsolationRoom.self, where: { $0.id.gt(0) })
      await filtered.run()
      for row in query.rows { _ = row.name }
    }
  #endif
}
