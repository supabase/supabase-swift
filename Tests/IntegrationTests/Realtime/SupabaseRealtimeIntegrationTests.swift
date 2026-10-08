//
//  SupabaseRealtimeIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import Helpers
import Supabase
import TestHelpers
import Testing

@Suite(
  .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil),
  .disabled(if: WebSocketAvailability.isMissing, "libcurl has no WebSocket support")
)
struct SupabaseRealtimeIntegrationTests {
  struct StreamEnded: Error {}

  struct Item: Codable, Sendable {
    var listID: Int
    var title: String

    enum CodingKeys: String, CodingKey {
      case listID = "list_id"
      case title
    }
  }

  private func uniqueTopic() -> String { "it-\(UUID())" }

  /// Runs `body` with a fresh client and closes its socket afterwards, also when `body` throws.
  private func withSupabase(_ body: (SupabaseClient) async throws -> Void) async throws {
    let supabase = SupabaseClient(
      supabaseURL: URL(string: DotEnv.supabaseURL)!,
      supabaseKey: DotEnv.supabasePublishableKey,
      options: SupabaseClientOptions(auth: .init(storage: InMemoryLocalStorage()))
    )
    do {
      try await body(supabase)
    } catch {
      await supabase.realtime.disconnect()
      throw error
    }
    await supabase.realtime.disconnect()
  }

  private func signUp(_ supabase: SupabaseClient) async throws {
    let response = try await supabase.auth.signUp(
      email: "realtime-\(UUID().uuidString.lowercased())@supabase.com", password: "The.pass@00!")
    #expect(response.session != nil)
  }

  /// The first element that passes `predicate`, within `timeout`.
  private func first<Element>(
    _ stream: RealtimeStream<Element>,
    timeout: Duration = .seconds(10),
    where predicate: @escaping @Sendable (Element) -> Bool = { _ in true }
  ) async throws -> Element {
    try await withTimeout(timeout) {
      for await element in stream where predicate(element) { return element }
      throw StreamEnded()
    }
  }

  /// Sends `ping` on a fresh channel for `topic` and returns once the same channel receives it.
  private func broadcastRoundTrip(_ supabase: SupabaseClient, isPrivate: Bool = false)
    async throws
  {
    let channel = supabase.channel(isPrivate ? "private-\(UUID())" : uniqueTopic()) {
      $0.isPrivate = isPrivate
      $0.broadcast.receiveOwnMessages = true
    }
    let messages = channel.broadcasts(event: "ping")
    try await channel.subscribe()

    try await channel.broadcast(event: "ping", payload: ["n": 1])

    let message = try await first(messages)
    #expect(try message.decode(as: [String: Int].self) == ["n": 1])
    await supabase.removeChannel(channel)
  }

  @Test
  func broadcastThroughTheFacade() async throws {
    try await withSupabase { supabase in
      try await broadcastRoundTrip(supabase)
    }
  }

  @Test
  func postgresInsertThroughTheFacade() async throws {
    try await withSupabase { supabase in
      let listID = Int.random(in: 1_000_000...2_000_000_000)
      let channel = supabase.channel(uniqueTopic())
      let changes = channel.postgresChanges(
        of: Item.self, event: .insert, table: "realtime_items",
        filter: .eq("list_id", value: listID))
      try await channel.subscribe()

      try await supabase.from("realtime_items")
        .insert(Item(listID: listID, title: "facade"))
        .execute()

      let change = try await first(changes)
      #expect(try change.row().title == "facade")
    }
  }

  @Test
  func aSignedInUserJoinsAPrivateChannel() async throws {
    try await withSupabase { supabase in
      try await signUp(supabase)

      try await broadcastRoundTrip(supabase, isPrivate: true)
    }
  }

  @Test
  func signOutRevokesPrivateChannelsAndKeepsPublicOnes() async throws {
    try await withSupabase { supabase in
      try await signUp(supabase)
      let privateChannel = supabase.channel("private-\(UUID())") { $0.isPrivate = true }
      let statuses = privateChannel.statusChanges
      try await privateChannel.subscribe()

      try await supabase.auth.signOut()

      // The server closes the channel when the anon key arrives, and the rejoins with that key
      // are refused until the channel fails. That takes a few rejoin backoff steps.
      let status = try await first(statuses, timeout: .seconds(20)) {
        if case .failed = $0 { return true }
        return false
      }
      #expect(status.error?.kind == .unauthorized)
      try await broadcastRoundTrip(supabase)
    }
  }
}
