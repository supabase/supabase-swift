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
    http.respond(when: { $0.path == "/auth/v1/token?grant_type=password" }) { _, body in
      let isUserB = body.map { String(decoding: $0, as: UTF8.self).contains("b@b.c") } ?? false
      return (
        HTTPResponse(status: .ok),
        isUserB
          ? sessionJSON(accessToken: "token-b", refreshToken: "refresh-b", userID: userB)
          : sessionJSON(accessToken: "token-1", refreshToken: "refresh-1")
      )
    }
    http.respond(when: { $0.path == "/auth/v1/token?grant_type=refresh_token" }) {
      [refreshHandler] request, body in try await refreshHandler.value(request, body)
    }
    _ = try await client.auth.signIn(email: "a@b.c", password: "x")
  }

  let refreshHandler = LockIsolated<RecordingTransport.Handler> { _, _ in
    (HTTPResponse(status: .ok), sessionJSON(accessToken: "token-2", refreshToken: "refresh-2"))
  }

  func refreshReturns(accessToken: String) {
    refreshHandler.setValue { _, _ in
      (HTTPResponse(status: .ok), sessionJSON(accessToken: accessToken, refreshToken: "refresh-2"))
    }
  }

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
    refreshHandler.setValue { _, _ in
      (
        HTTPResponse(status: .badRequest),
        Data(#"{"code":"refresh_token_not_found","message":"Refresh Token Not Found"}"#.utf8)
      )
    }
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

  @Test
  func unauthorizedAfterAnotherUserSignedInIsNotRetriedAsThatUser() async throws {
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { [client] request, _ in
      guard request.headerFields[.authorization] == "Bearer token-1" else {
        return (HTTPResponse(status: .created), Data())
      }
      try await client.auth.signIn(email: "b@b.c", password: "x")
      return (HTTPResponse(status: .unauthorized), Data())
    }

    await #expect(throws: PostgrestError.self) {
      try await client.from("todos").insert(["title": "a"]).execute()
    }

    #expect(dataAuthorizations("/rest/v1/todos") == ["Bearer token-1"])
    #expect(refreshCount == 0)
  }

  @Test
  func cancellationDuringTheRefreshThrowsWithoutRetrying() async throws {
    let refreshStarted = AsyncStream.makeStream(of: Void.self)
    let releaseRefresh = AsyncStream.makeStream(of: Void.self)
    defer { releaseRefresh.continuation.finish() }
    refreshHandler.setValue { _, _ in
      refreshStarted.continuation.yield()
      for await _ in releaseRefresh.stream {}
      return (
        HTTPResponse(status: .ok), sessionJSON(accessToken: "token-2", refreshToken: "refresh-2")
      )
    }
    http.respond(when: { $0.path?.hasPrefix("/functions/v1/hello") == true }) { _, _ in
      (HTTPResponse(status: .unauthorized), Data())
    }

    let request = Task { [client] in try await client.functions.invoke("hello") }
    for await _ in refreshStarted.stream { break }
    request.cancel()

    await #expect(throws: CancellationError.self) { try await request.value }
    #expect(dataAuthorizations("/functions/v1/hello") == ["Bearer token-1"])
  }

  @Test
  func functionsUnauthorizedRefreshesOnceAndRetries() async throws {
    http.respond(when: { $0.path?.hasPrefix("/functions/v1/hello") == true }) { request, _ in
      request.headerFields[.authorization] == "Bearer token-2"
        ? (HTTPResponse(status: .ok), Data("{}".utf8))
        : (HTTPResponse(status: .unauthorized), Data(#"{"code":"UNAUTHORIZED"}"#.utf8))
    }

    try await client.functions.invoke("hello")

    #expect(dataAuthorizations("/functions/v1/hello") == ["Bearer token-1", "Bearer token-2"])
    #expect(refreshCount == 1)
  }

  @Test
  func unauthorizedWithoutASessionIsSentWithTheKeyAndNotRetried() async throws {
    let http = RecordingTransport { _, _ in (HTTPResponse(status: .unauthorized), Data()) }
    let client = SupabaseClient(
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

    await #expect(throws: PostgrestError.self) {
      try await client.from("todos").select().execute()
    }

    #expect(
      http.requests.map { $0.head.headerFields[.authorization] } == ["Bearer PUBLISHABLE_KEY"])
  }

  @Test
  func storageBadRequestForAnExpiredTokenRefreshesAndRetries() async throws {
    let expired = jwt(expiresIn: -60)
    try await signIn(withAccessToken: expired)
    http.respond(when: { $0.path?.hasPrefix("/storage/v1/bucket") == true }) { request, _ in
      request.headerFields[.authorization] == "Bearer \(expired)"
        ? (HTTPResponse(status: .badRequest), storageExpiredJWTBody)
        : (HTTPResponse(status: .ok), Data("[]".utf8))
    }

    _ = try await client.storage.listBuckets()

    #expect(dataAuthorizations("/storage/v1/bucket") == ["Bearer \(expired)", "Bearer token-2"])
    #expect(refreshCount == 2)
  }

  @Test
  func storageBadRequestWithAnEmptyBodyForAnExpiredTokenIsRetried() async throws {
    let expired = jwt(expiresIn: -60)
    try await signIn(withAccessToken: expired)
    http.respond(when: { $0.path?.hasPrefix("/storage/v1/object") == true }) { request, _ in
      request.headerFields[.authorization] == "Bearer \(expired)"
        ? (HTTPResponse(status: .badRequest), Data())
        : (HTTPResponse(status: .ok), Data("hello".utf8))
    }

    _ = try await client.storage.from("avatars").download(path: "a.txt")

    #expect(dataAuthorizations("/storage/v1/object") == ["Bearer \(expired)", "Bearer token-2"])
  }

  @Test
  func storageBadRequestForALiveTokenIsNotRetried() async throws {
    let live = jwt(expiresIn: 3600)
    try await signIn(withAccessToken: live)
    http.respond(when: { $0.path?.hasPrefix("/storage/v1/object") == true }) { _, _ in
      (HTTPResponse(status: .badRequest), storageRLSDenialBody)
    }

    await #expect(throws: StorageError.self) {
      try await client.storage.from("avatars").upload(path: "a.txt", data: Data("hello".utf8))
    }

    #expect(dataAuthorizations("/storage/v1/object") == ["Bearer \(live)"])
    #expect(refreshCount == 1)
  }

  /// Replaces the session with one whose `expires_at` is an hour away, so the client sends
  /// `accessToken` whatever its own `exp` says.
  func signIn(withAccessToken accessToken: String) async throws {
    refreshReturns(accessToken: accessToken)
    try await client.auth.refreshSession()
    refreshReturns(accessToken: "token-2")
  }
}

private let userB = "0b0b0b0b-a2ee-47c4-80e1-5bd919f3d8b8"

private let storageExpiredJWTBody = Data(
  #"{"statusCode":"403","error":"Unauthorized","message":"\"exp\" claim timestamp check failed","code":"AccessDenied"}"#
    .utf8)

private let storageRLSDenialBody = Data(
  #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy","code":"AccessDenied"}"#
    .utf8)

private func jwt(expiresIn seconds: TimeInterval) -> String {
  func segment(_ json: String) -> String {
    Data(json.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
  let exp = Int(Date().timeIntervalSince1970 + seconds)
  return [
    segment(#"{"alg":"ES256","typ":"JWT"}"#),
    segment(#"{"sub":"f33d3ec9-a2ee-47c4-80e1-5bd919f3d8b8","exp":\#(exp)}"#),
    "signature",
  ].joined(separator: ".")
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

private func sessionJSON(
  accessToken: String,
  refreshToken: String,
  userID: String = "f33d3ec9-a2ee-47c4-80e1-5bd919f3d8b8"
) -> Data {
  Data(
    """
    {
      "access_token": "\(accessToken)",
      "token_type": "bearer",
      "expires_in": 3600,
      "expires_at": \(Int(Date().timeIntervalSince1970) + 3600),
      "refresh_token": "\(refreshToken)",
      "user": {
        "id": "\(userID)",
        "aud": "authenticated",
        "app_metadata": {},
        "user_metadata": {},
        "created_at": "2022-03-30T10:33:41.005433Z",
        "updated_at": "2022-03-30T10:33:41.022688Z"
      }
    }
    """.utf8)
}
