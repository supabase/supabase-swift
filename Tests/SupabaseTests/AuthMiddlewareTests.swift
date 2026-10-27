import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Supabase

@Suite
struct AuthMiddlewareTests {
  let http = RecordingTransport()
  let client: SupabaseClient

  init() async throws {
    client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: InMemoryLocalStorage(),
          storageKey: "sb-test-\(UUID().uuidString)-auth-token",
          autoRefresh: .manual
        ),
        global: SupabaseClientOptions.GlobalOptions(http: .init(transport: http))
      )
    )
    http.respond(when: { $0.path == "/auth/v1/token?grant_type=password" }) { _, _ in
      (HTTPResponse(status: .ok), sessionJSON(accessToken: "token-1", refreshToken: "refresh-1"))
    }
    http.respond(when: { $0.path == "/auth/v1/token?grant_type=refresh_token" }) {
      [refreshResponse] _, _ in refreshResponse.value
    }
    _ = try await client.auth.signIn(email: "a@b.c", password: "x")
  }

  let refreshResponse = LockIsolated(
    (HTTPResponse(status: .ok), sessionJSON(accessToken: "token-2", refreshToken: "refresh-2")))

  var refreshCount: Int {
    http.requests.filter { $0.head.path == "/auth/v1/token?grant_type=refresh_token" }.count
  }

  func dataAuthorizations(_ prefix: String) -> [String?] {
    http.requests.filter { $0.head.path?.hasPrefix(prefix) == true }
      .map { $0.head.headerFields[.authorization] }
  }

  @Test
  func unauthorizedWithAnOlderTokenRetriesWithTheCurrentOneWithoutRefreshing() async throws {
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { [client] request, _ in
      guard request.headerFields[.authorization] == "Bearer token-1" else {
        return (HTTPResponse(status: .ok), Data("[]".utf8))
      }
      try await client.auth.refreshSession()
      return (HTTPResponse(status: .unauthorized), Data())
    }

    try await client.from("todos").select().execute()

    #expect(dataAuthorizations("/rest/v1/todos") == ["Bearer token-1", "Bearer token-2"])
    #expect(refreshCount == 1)
  }

  @Test
  func unauthorizedWithTheCurrentTokenRefreshesOnceAndRetries() async throws {
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { request, _ in
      request.headerFields[.authorization] == "Bearer token-2"
        ? (HTTPResponse(status: .ok), Data("[]".utf8))
        : (HTTPResponse(status: .unauthorized), Data())
    }

    try await client.from("todos").select().execute()

    #expect(dataAuthorizations("/rest/v1/todos") == ["Bearer token-1", "Bearer token-2"])
    #expect(refreshCount == 1)
  }

  @Test
  func secondUnauthorizedAfterTheRefreshReachesTheCaller() async throws {
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { request, _ in
      let token = request.headerFields[.authorization] ?? ""
      return (HTTPResponse(status: .unauthorized), Data(#"{"message":"\#(token)"}"#.utf8))
    }

    let error = try await #require(throws: PostgrestError.self) {
      try await client.from("todos").select().execute()
    }

    #expect(error.serverError?.message == "Bearer token-2")
    #expect(dataAuthorizations("/rest/v1/todos") == ["Bearer token-1", "Bearer token-2"])
    #expect(refreshCount == 1)
  }

  @Test
  func concurrentUnauthorizedResponsesShareOneRefresh() async throws {
    let bothSent = Barrier(count: 2)
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { request, _ in
      guard request.headerFields[.authorization] == "Bearer token-1" else {
        return (HTTPResponse(status: .ok), Data("[]".utf8))
      }
      await bothSent.arrive()
      return (HTTPResponse(status: .unauthorized), Data())
    }

    async let first: Void = client.from("todos").select().execute().value
    async let second: Void = client.from("todos").select().execute().value
    _ = try await (first, second)

    #expect(refreshCount == 1)
    #expect(dataAuthorizations("/rest/v1/todos").filter { $0 == "Bearer token-2" }.count == 2)
  }

  @Test
  func failedRefreshReturnsTheOriginalUnauthorized() async throws {
    refreshResponse.setValue(
      (
        HTTPResponse(status: .badRequest),
        Data(#"{"code":"refresh_token_not_found","message":"Refresh Token Not Found"}"#.utf8)
      ))
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { _, _ in
      (HTTPResponse(status: .unauthorized), Data(#"{"message":"JWT expired"}"#.utf8))
    }

    let error = try await #require(throws: PostgrestError.self) {
      try await client.from("todos").select().execute()
    }

    #expect(error.serverError?.message == "JWT expired")
    #expect(dataAuthorizations("/rest/v1/todos") == ["Bearer token-1"])
    #expect(refreshCount == 1)
  }

  @Test
  func singlePassBodyIsNotRetried() async throws {
    http.respond(when: { $0.path?.hasPrefix("/storage/v1/object") == true }) { _, _ in
      (HTTPResponse(status: .unauthorized), Data())
    }
    let chunks = AsyncStream<ArraySlice<UInt8>> {
      $0.yield(ArraySlice("hello".utf8))
      $0.finish()
    }

    await #expect(throws: (any Error).self) {
      try await client.storage.from("avatars").upload(
        path: "a.txt", body: HTTPBody(chunks, length: .known(5), iterationBehavior: .single))
    }

    #expect(dataAuthorizations("/storage/v1/object") == ["Bearer token-1"])
    #expect(refreshCount == 0)
  }

  @Test
  func perCallAuthorizationIsNeitherReplacedNorRetried() async throws {
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { _, _ in
      (HTTPResponse(status: .unauthorized), Data())
    }

    await #expect(throws: PostgrestError.self) {
      try await client.from("todos").select()
        .setHeader(name: "Authorization", value: "Bearer per-call").execute()
    }

    #expect(dataAuthorizations("/rest/v1/todos") == ["Bearer per-call"])
    #expect(refreshCount == 0)
  }
}

private actor Barrier {
  let count: Int
  var waiters: [CheckedContinuation<Void, Never>] = []

  init(count: Int) {
    self.count = count
  }

  func arrive() async {
    guard waiters.count + 1 < count else {
      waiters.forEach { $0.resume() }
      waiters = []
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }
}

private func sessionJSON(accessToken: String, refreshToken: String) -> Data {
  Data(
    """
    {
      "access_token": "\(accessToken)",
      "token_type": "bearer",
      "expires_in": 3600,
      "expires_at": \(Int(Date().timeIntervalSince1970) + 3600),
      "refresh_token": "\(refreshToken)",
      "user": {
        "id": "f33d3ec9-a2ee-47c4-80e1-5bd919f3d8b8",
        "aud": "authenticated",
        "app_metadata": {},
        "user_metadata": {},
        "created_at": "2022-03-30T10:33:41.005433Z",
        "updated_at": "2022-03-30T10:33:41.022688Z"
      }
    }
    """.utf8)
}
