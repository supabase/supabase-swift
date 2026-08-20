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
private final class PostgrestAuthCapturingProtocol: URLProtocol {
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
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("[]".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func makePostgrestAuthCapturingSession() -> URLSession {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [PostgrestAuthCapturingProtocol.self]
  return URLSession(configuration: config)
}

/// `.serialized`: the tests below share `PostgrestAuthCapturingProtocol`'s static request log, which
/// would otherwise race against itself under Swift Testing's default parallel execution. That
/// storage is private to this file, so — unlike the shared `RequestCapturingProtocol` — no other
/// suite can race against it.
///
/// These pin the design decision in ``SupabaseClient/rest``: it deliberately does *not* pass an
/// `accessToken` closure into `PostgrestClient.Configuration`, and relies on `fetchWithAuth` to
/// resolve and inject the live session token on every request instead. Without a test, dropping that
/// transport-level injection (or adding a stale `Authorization` header to `Configuration.headers`)
/// would silently send requests as the anon/publishable key.
@Suite(.serialized)
struct SupabaseClientPostgrestAuthTests {
  @Test
  func restRequestUsesLiveAccessToken() async throws {
    PostgrestAuthCapturingProtocol.capturedRequest = nil
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        // A custom `accessToken` closure stands in for a real signed-in session, without needing to
        // drive the full sign-in flow.
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClientOptions.GlobalOptions(session: makePostgrestAuthCapturingSession())
      )
    )

    _ = try await client.from("todos").select().execute()

    let request = try #require(PostgrestAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer live-session-token")
  }

  @Test
  func restRequestWithoutSessionFallsBackToSupabaseKey() async throws {
    PostgrestAuthCapturingProtocol.capturedRequest = nil
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(session: makePostgrestAuthCapturingSession())
      )
    )

    _ = try await client.from("todos").select().execute()

    let request = try #require(PostgrestAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer PUBLISHABLE_KEY")
  }
}
