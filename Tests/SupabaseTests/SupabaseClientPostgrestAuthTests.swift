import ConcurrencyExtras
import Foundation
import Testing

@testable import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private final class PostgrestAuthCapturingProtocol: URLProtocol {
  private static let storage = LockIsolated<URLRequest?>(nil)
  static var capturedRequest: URLRequest? {
    get { storage.value }
    set { storage.setValue(newValue) }
  }

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

@Suite(.serialized)
struct SupabaseClientPostgrestAuthTests {
  @Test
  func restRequestUsesLiveAccessToken() async throws {
    PostgrestAuthCapturingProtocol.capturedRequest = nil
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: makePostgrestAuthCapturingSession()))
        )
      )
    )

    _ = try await client.from("todos").select().execute()

    let request = try #require(PostgrestAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer live-session-token")
  }

  @Test
  func restRequestPerCallAuthorizationWinsOverLiveAccessToken() async throws {
    PostgrestAuthCapturingProtocol.capturedRequest = nil
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: makePostgrestAuthCapturingSession()))
        )
      )
    )

    _ = try await client.from("todos").select()
      .setHeader(name: "Authorization", value: "Bearer per-call-override").execute()

    let request = try #require(PostgrestAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer per-call-override")
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
          autoRefresh: .manual
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: makePostgrestAuthCapturingSession()))
        )
      )
    )

    _ = try await client.from("todos").select().execute()

    let request = try #require(PostgrestAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer PUBLISHABLE_KEY")
  }
}
