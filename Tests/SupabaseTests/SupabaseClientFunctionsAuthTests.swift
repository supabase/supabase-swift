import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Supabase

@Suite
struct SupabaseClientFunctionsAuthTests {
  private let transport = RecordingTransport { _, _ in
    (HTTPResponse(status: .ok), Data("[]".utf8))
  }

  private func makeClient(
    supabaseKey: String = "PUBLISHABLE_KEY",
    auth: SupabaseClient.Configuration.Auth
  ) throws -> SupabaseClient {
    try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: supabaseKey,
      configuration: SupabaseClient.Configuration(
        auth: auth,
        global: SupabaseClient.Configuration.Global(http: .init(transport: transport))
      )
    )
  }

  @Test
  func functionsInvokePerCallHeaderOverrideIsNotClobberedByLiveAccessToken() async throws {
    let client = try makeClient(
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        accessToken: { "live-session-token" }
      )
    )

    _ = try? await client.functions.invoke(
      "hello-world",
      options: FunctionInvokeOptions(headers: [.authorization: "Bearer per-call-override"])
    )

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer per-call-override")
  }

  @Test
  func functionsInvokeWithoutSessionDoesNotThrow() async throws {
    let client = try makeClient(
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        autoRefresh: .manual
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer PUBLISHABLE_KEY")
  }

  @Test
  func functionsInvokeWithNewFormatKeyAndNoSessionSendsNoBearer() async throws {
    let client = try makeClient(
      supabaseKey: "sb_publishable_abc123",
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        autoRefresh: .manual
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == nil)
    #expect(request.head.headerFields[HTTPField.Name("apikey")!] == "sb_publishable_abc123")
  }

  @Test
  func functionsInvokeThrowsTheProviderErrorUnwrapped() async throws {
    struct TokenError: Error {}
    let client = try makeClient(
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        accessToken: { throw TokenError() }
      )
    )

    await #expect(throws: TokenError.self) {
      try await client.functions.invoke("hello-world")
    }
  }

  @Test
  func functionsInvokeUsesLiveAccessTokenWhenNoOverrideIsGiven() async throws {
    let client = try makeClient(
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        accessToken: { "live-session-token" }
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer live-session-token")
  }

  @Test
  func functionsInvokeSendsNoBearerWhenTheProviderReturnsTheNewFormatKey() async throws {
    let client = try makeClient(
      supabaseKey: "sb_publishable_abc123",
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        accessToken: { "sb_publishable_abc123" }
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == nil)
  }
}
