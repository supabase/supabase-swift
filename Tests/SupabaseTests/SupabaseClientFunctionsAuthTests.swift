import Foundation
import Testing

@testable import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// `.serialized`: shares `RequestCapturingProtocol`'s static request log with
/// `SupabaseClientTests`/`TracingTests`, which would otherwise race against these tests under
/// Swift Testing's default parallel execution.
@Suite(.serialized)
struct SupabaseClientFunctionsAuthTests {
  @Test
  func functionsInvokePerCallHeaderOverrideIsNotClobberedByLiveAccessToken() async throws {
    RequestCapturingProtocol.capturedRequests = []
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        // A custom `accessToken` closure stands in for a real signed-in session, without needing
        // to drive the full sign-in flow: it's what actually exercises the bug, since the
        // transport-level auth injection this test guards against only fires when a live token
        // is available to inject.
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClientOptions.GlobalOptions(session: makeMockSession())
      )
    )

    _ = try? await client.functions.invoke(
      "hello-world",
      options: FunctionInvokeOptions(headers: ["Authorization": "Bearer per-call-override"])
    )

    let request = try #require(RequestCapturingProtocol.capturedRequests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer per-call-override")
  }

  @Test
  func functionsInvokeWithoutSessionDoesNotThrow() async throws {
    RequestCapturingProtocol.capturedRequests = []
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(session: makeMockSession())
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(RequestCapturingProtocol.capturedRequests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer PUBLISHABLE_KEY")
  }

  @Test
  func functionsInvokeUsesLiveAccessTokenWhenNoOverrideIsGiven() async throws {
    RequestCapturingProtocol.capturedRequests = []
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClientOptions.GlobalOptions(session: makeMockSession())
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(RequestCapturingProtocol.capturedRequests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer live-session-token")
  }
}
