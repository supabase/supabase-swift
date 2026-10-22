import ConcurrencyExtras
import Foundation
import HTTPTypes
import Testing

@testable import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private final class FunctionsAuthCapturingProtocol: URLProtocol {
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

@Suite(.serialized)
struct SupabaseClientFunctionsAuthTests {
  @Test
  func functionsInvokePerCallHeaderOverrideIsNotClobberedByLiveAccessToken() async throws {
    FunctionsAuthCapturingProtocol.capturedRequest = nil
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: makeFunctionsAuthCapturingSession()))
        )
      )
    )

    _ = try? await client.functions.invoke(
      "hello-world",
      options: FunctionInvokeOptions(headers: [.authorization: "Bearer per-call-override"])
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
          automaticallyRefreshesToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: makeFunctionsAuthCapturingSession()))
        )
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(FunctionsAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer PUBLISHABLE_KEY")
  }

  @Test
  func functionsInvokeWithNewFormatKeyAndNoSessionSendsNoBearer() async throws {
    FunctionsAuthCapturingProtocol.capturedRequest = nil
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "sb_publishable_abc123",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          automaticallyRefreshesToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: makeFunctionsAuthCapturingSession()))
        )
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(FunctionsAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_abc123")
  }

  @Test
  func functionsInvokeThrowsTheProviderErrorUnwrapped() async throws {
    struct TokenError: Error {}
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          accessToken: { throw TokenError() }
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: makeFunctionsAuthCapturingSession()))
        )
      )
    )

    await #expect(throws: TokenError.self) {
      try await client.functions.invoke("hello-world")
    }
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
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: makeFunctionsAuthCapturingSession()))
        )
      )
    )

    try await client.functions.invoke("hello-world")

    let request = try #require(FunctionsAuthCapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer live-session-token")
  }
}
