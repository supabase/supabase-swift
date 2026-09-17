//
//  DefaultIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 16/09/26.
//

import Foundation
import Supabase
import Testing

/// This target compiles with `.defaultIsolation(MainActor.self)`, the SE-0466 setting an app can
/// opt into on Swift 6.2. Every declaration below is implicitly `@MainActor`, so `Model.load` only
/// compiles if each public async entry point can be called from the main actor with values that
/// live there. Nothing here talks to a server: the test proves the code builds and a client can be
/// constructed. The SDK modules themselves stay nonisolated.
@Suite
struct DefaultIsolationTests {
  /// `AuthLocalStorage` refines `Sendable`, so its conformance cannot be main-actor isolated. A
  /// consumer under default isolation opts the type out with `nonisolated`, as an app would. An
  /// explicit storage also keeps this target building on Linux, which has no default storage.
  nonisolated struct NoopAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
  }

  final class Model {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "anon-key",
      options: SupabaseClientOptions(auth: .init(storage: NoopAuthStorage()))
    )
    var rows: [String] = []

    func load() async throws {
      let session = try await client.auth.signIn(email: "user@example.com", password: "password")
      _ = session.accessToken
      rows = try await client.from("table").select().execute().value
      let channel = client.channel("room")
      for await status in channel.statusChange { _ = status }
      try await client.storage.from("bucket").upload(path: "key", data: Data())
      _ = try await client.functions.invoke("function")
      for await (event, session) in client.auth.authStateChanges { _ = (event, session) }
    }
  }

  @Test
  func clientIsUsableFromAMainActorIsolatedModule() {
    let model = Model()
    #expect(model.rows.isEmpty)
  }
}
