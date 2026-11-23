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
    auth: SupabaseClient.Configuration.Auth,
    transport: RecordingTransport? = nil
  ) throws -> SupabaseClient {
    try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: supabaseKey,
      configuration: SupabaseClient.Configuration(
        auth: auth,
        global: SupabaseClient.Configuration.Global(
          http: .init(transport: transport ?? self.transport)
        )
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

  @Test(arguments: ["sb_publishable_abc123", "sb_secret_abc123"])
  func functionsInvokeWithNewFormatKeyAndNoSessionSendsNoBearer(supabaseKey: String) async throws {
    let client = try makeClient(
      supabaseKey: supabaseKey,
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        autoRefresh: .manual
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == nil)
    #expect(request.head.headerFields[HTTPField.Name("apikey")!] == supabaseKey)
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
  func functionsInvokeSendsAProviderTokenAsGivenEvenWhenItEqualsTheNewFormatKey() async throws {
    let client = try makeClient(
      supabaseKey: "sb_publishable_abc123",
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        accessToken: { "sb_publishable_abc123" }
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer sb_publishable_abc123")
  }

  @Test(arguments: ["sb_publishable_abc123", "legacy.jwt.key"])
  func functionsInvokeWithASessionSendsTheSessionTokenForEveryKeyFormat(
    supabaseKey: String
  ) async throws {
    let http = RecordingTransport()
    http.respond(when: { $0.path?.hasPrefix("/auth/v1/token") == true }) { _, _ in
      (HTTPResponse(status: .ok), sessionJSON(accessToken: "session-jwt", refreshToken: "r"))
    }
    http.respond { _, _ in (HTTPResponse(status: .ok), Data("{}".utf8)) }
    let client = try makeClient(
      supabaseKey: supabaseKey,
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        autoRefresh: .manual
      ),
      transport: http
    )
    _ = try await client.auth.signIn(email: "a@b.c", password: "x")

    try await client.functions.invoke("hello-world")

    let request = try #require(http.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer session-jwt")
    #expect(request.head.headerFields[HTTPField.Name("apikey")!] == supabaseKey)
  }

  @Test(
    arguments: [
      ("sb_publishable_abc123", nil),
      ("sb_secret_abc123", nil),
      ("legacy.jwt.key", "Bearer legacy.jwt.key"),
    ] as [(String, String?)])
  func functionsInvokeWhenTheProviderReturnsNoTokenFallsBackOnlyToALegacyKey(
    supabaseKey: String,
    expectedAuthorization: String?
  ) async throws {
    let client = try makeClient(
      supabaseKey: supabaseKey,
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        accessToken: { nil }
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == expectedAuthorization)
  }

  @Test
  func functionsInvokeWithNewFormatKeyKeepsAPerCallAuthorizationOverride() async throws {
    let client = try makeClient(
      supabaseKey: "sb_publishable_abc123",
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        autoRefresh: .manual
      )
    )

    try await client.functions.invoke(
      "hello-world",
      options: FunctionInvokeOptions(headers: [.authorization: "Bearer per-call-override"])
    )

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer per-call-override")
  }
}
