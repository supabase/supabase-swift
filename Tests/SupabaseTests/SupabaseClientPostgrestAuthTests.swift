import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Supabase

@Suite
struct SupabaseClientPostgrestAuthTests {
  private let transport = RecordingTransport { _, _ in
    (
      HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
      Data("[]".utf8)
    )
  }

  private func makeClient(auth: SupabaseClient.Configuration.Auth) throws -> SupabaseClient {
    try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: auth,
        global: SupabaseClient.Configuration.Global(http: .init(transport: transport))
      )
    )
  }

  @Test
  func restRequestUsesLiveAccessToken() async throws {
    let client = try makeClient(
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        accessToken: { "live-session-token" }
      )
    )

    _ = try await client.from("todos").select().execute()

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer live-session-token")
  }

  @Test
  func restRequestPerCallAuthorizationWinsOverLiveAccessToken() async throws {
    let client = try makeClient(
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        accessToken: { "live-session-token" }
      )
    )

    _ = try await client.from("todos").select()
      .settingHeader(name: .authorization, value: "Bearer per-call-override").execute()

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer per-call-override")
  }

  @Test
  func restRequestWithoutSessionFallsBackToSupabaseKey() async throws {
    let client = try makeClient(
      auth: SupabaseClient.Configuration.Auth(
        storage: InMemoryAuthStorage(),
        autoRefresh: .manual
      )
    )

    _ = try await client.from("todos").select().execute()

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer PUBLISHABLE_KEY")
  }
}
