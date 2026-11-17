//
//  FunctionsSupabaseClientIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 16/11/26.
//

import Foundation
import Supabase
import TestHelpers
import Testing

/// Functions invoked through `SupabaseClient`, so the token comes from the client's own wiring
/// (the Auth session, or the key), not a hand-built `FunctionsClient`. Both functions run with
/// `verify_jwt` on, the CLI default.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct FunctionsSupabaseClientIntegrationTests {
  struct WhoAmI: Decodable, Equatable {
    var role: String?
    var sub: String?
  }

  struct Echo: Decodable {
    var headers: [String: String]
  }

  private func makeClient(key: String) throws -> SupabaseClient {
    try SupabaseClient(
      supabaseURL: URL(string: DotEnv.supabaseURL)!,
      supabaseKey: key,
      configuration: SupabaseClient.Configuration(auth: .init(storage: InMemoryTestStorage()))
    )
  }

  /// After a sign-in, the function receives the user's access token, and the gateway accepts it.
  @Test
  func aSignedInClientInvokesWithTheUserJWT() async throws {
    let client = try makeClient(key: DotEnv.supabasePublishableKey)
    let email = "functions-\(UUID().uuidString.lowercased())@supabase.com"
    _ = try await client.auth.signUp(email: email, password: "The.Pa55word!")
    let session = try await client.auth.session()

    let caller: WhoAmI = try await client.functions.invoke("whoami")

    #expect(caller == WhoAmI(role: "authenticated", sub: session.user.id.uuidString.lowercased()))
  }

  /// With a new-format publishable key and no session, the client sends no bearer token, and the
  /// gateway still lets the call through.
  @Test
  func aClientWithANewFormatKeyAndNoSessionInvokes() async throws {
    let client = try makeClient(key: DotEnv.supabaseNewFormatPublishableKey)

    let echo: Echo = try await client.functions.invoke("echo")

    #expect(echo.headers["authorization"] == nil)
  }
}
