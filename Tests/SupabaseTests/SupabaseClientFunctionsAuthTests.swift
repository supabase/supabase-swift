import ConcurrencyExtras
import Foundation
import Testing

@testable import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Single-purpose capturing protocol, deliberately not the shared `RequestCapturingProtocol`:
/// that's also used by `TracingTests` (a `.serialized` suite that still runs concurrently with
/// this one), so touching its static storage here would race.
private final class FunctionsAuthCapturingProtocol: URLProtocol {
  private static let storage = LockIsolated<URLRequest?>(nil)
  static var capturedRequest: URLRequest? {
    get { storage.value }
    set { storage.setValue(newValue) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.capturedRequest = request
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("[]".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func makeFunctionsAuthCapturingSession() -> URLSession {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [FunctionsAuthCapturingProtocol.self]
  return URLSession(configuration: config)
}

/// `.serialized`: the three tests below share `FunctionsAuthCapturingProtocol`'s static request
/// log, which would otherwise race against itself under Swift Testing's default parallel
/// execution. That storage is private to this file, so — unlike the shared `RequestCapturingProtocol`
/// — no other suite can race against it.
@Suite(.serialized)
struct SupabaseClientFunctionsAuthTests {
  @Test
  func functionsInvokePerCallHeaderOverrideIsNotClobberedByLiveAccessToken() async throws {
    FunctionsAuthCapturingProtocol.capturedRequest = nil
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
        global: SupabaseClientOptions.GlobalOptions(session: makeFunctionsAuthCapturingSession())
      )
    )

    _ = try? await client.functions.invoke(
      "hello-world",
      options: FunctionInvokeOptions(headers: ["Authorization": "Bearer per-call-override"])
    )

    let request = try #require(FunctionsAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer per-call-override")
  }

  @Test
  func functionsInvokeWithoutSessionDoesNotThrow() async throws {
    FunctionsAuthCapturingProtocol.capturedRequest = nil
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(session: makeFunctionsAuthCapturingSession())
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(FunctionsAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer PUBLISHABLE_KEY")
  }

  @Test
  func functionsInvokeUsesLiveAccessTokenWhenNoOverrideIsGiven() async throws {
    FunctionsAuthCapturingProtocol.capturedRequest = nil
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClientOptions.GlobalOptions(session: makeFunctionsAuthCapturingSession())
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(FunctionsAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer live-session-token")
  }
}
