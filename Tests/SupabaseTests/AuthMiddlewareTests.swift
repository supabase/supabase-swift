import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth
@testable import Supabase

@Suite(.timeLimit(.minutes(1)))
struct AuthMiddlewareTests {
  let http = RecordingTransport()
  let client: SupabaseClient

  init() async throws {
    try await self.init(autoRefresh: .manual)
  }

  init(autoRefresh: AuthClient.AutoRefreshPolicy) async throws {
    client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: InMemoryLocalStorage(),
          storageKey: "sb-test-\(UUID().uuidString)-auth-token",
          autoRefresh: autoRefresh
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

  var refreshCount: Int {
    http.requests.filter { $0.head.path == "/auth/v1/token?grant_type=refresh_token" }.count
  }

  func dataAuthorizations(_ prefix: String) -> [String?] {
    http.requests.filter { $0.head.path?.hasPrefix(prefix) == true }
      .map { $0.head.headerFields[.authorization] }
  }

  var redeemedRefreshTokens: [String] {
    http.requests.filter { $0.head.path == "/auth/v1/token?grant_type=refresh_token" }
      .compactMap { request in
        request.body.flatMap {
          (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["refresh_token"]
            as? String
        }
      }
  }

  @Test
  func unauthorizedWithAnOlderTokenRetriesWithTheCurrentOneWithoutRefreshing() async throws {
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { [client] request, _ in
      guard request.headerFields[.authorization] == "Bearer token-1" else {
        return (HTTPResponse(status: .ok), Data("[]".utf8))
      }
      try await client.auth.refreshSession()
      return (invalidTokenUnauthorized, Data())
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
        : (invalidTokenUnauthorized, Data())
    }

    try await client.from("todos").select().execute()

    #expect(dataAuthorizations("/rest/v1/todos") == ["Bearer token-1", "Bearer token-2"])
    #expect(refreshCount == 1)
  }

  @Test
  func secondUnauthorizedAfterTheRefreshReachesTheCaller() async throws {
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { request, _ in
      let token = request.headerFields[.authorization] ?? ""
      return (invalidTokenUnauthorized, Data(#"{"message":"\#(token)"}"#.utf8))
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
    let bothSent = Gate()
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { request, _ in
      guard request.headerFields[.authorization] == "Bearer token-1" else {
        return (HTTPResponse(status: .ok), Data("[]".utf8))
      }
      await bothSent.pass()
      return (invalidTokenUnauthorized, Data())
    }

    async let first: Void = client.from("todos").select().execute().value
    async let second: Void = client.from("todos").select().execute().value
    await bothSent.arrivals(2)
    bothSent.open()
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
      (invalidTokenUnauthorized, Data(#"{"message":"JWT expired"}"#.utf8))
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
      (
        HTTPResponse(status: .badRequest),
        storageExpiredJWTBody(#""exp" claim timestamp check failed"#)
      )
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
      (invalidTokenUnauthorized, Data())
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
      return (invalidTokenUnauthorized, Data())
    }

    await #expect(throws: PostgrestError.self) {
      try await client.from("todos").insert(["title": "a"]).execute()
    }

    #expect(dataAuthorizations("/rest/v1/todos") == ["Bearer token-1"])
    #expect(refreshCount == 0)
  }

  @Test
  func cancellationDuringTheRefreshThrowsWithoutRetrying() async throws {
    let refresh = Gate()
    defer { refresh.open() }
    refreshHandler.setValue { _, _ in
      await refresh.pass()
      return (
        HTTPResponse(status: .ok), sessionJSON(accessToken: "token-2", refreshToken: "refresh-2")
      )
    }
    http.respond(when: { $0.path?.hasPrefix("/functions/v1/hello") == true }) { _, _ in
      (functionsGatewayUnauthorized("UNAUTHORIZED_LEGACY_JWT"), Data())
    }

    let request = Task { [client] in try await client.functions.invoke("hello") }
    await refresh.arrivals(1)
    request.cancel()

    await #expect(throws: CancellationError.self) { try await request.value }
    #expect(dataAuthorizations("/functions/v1/hello") == ["Bearer token-1"])
  }

  @Test(arguments: ["UNAUTHORIZED_LEGACY_JWT", "UNAUTHORIZED_ASYMMETRIC_JWT", "UNAUTHORIZED_JWT"])
  func functionsGatewayJWTRejectionRefreshesOnceAndRetries(code: String) async throws {
    http.respond(when: { $0.path?.hasPrefix("/functions/v1/hello") == true }) { request, _ in
      request.headerFields[.authorization] == "Bearer token-2"
        ? (HTTPResponse(status: .ok), Data("{}".utf8))
        : (functionsGatewayUnauthorized(code), Data(#"{"code":"\#(code)"}"#.utf8))
    }

    try await client.functions.invoke("hello")

    #expect(dataAuthorizations("/functions/v1/hello") == ["Bearer token-1", "Bearer token-2"])
    #expect(refreshCount == 1)
  }

  @Test(arguments: [nil, "UNAUTHORIZED_INVALID_JWT_FORMAT", "UNAUTHORIZED_NO_AUTH_HEADER"])
  func functionsUnauthorizedWithNoJWTRejectionCodeIsNotRetried(code: String?) async throws {
    http.respond(when: { $0.path?.hasPrefix("/functions/v1/hello") == true }) { _, _ in
      (
        code.map(functionsGatewayUnauthorized) ?? HTTPResponse(status: .unauthorized),
        Data(#"{"error":"not an admin"}"#.utf8)
      )
    }

    await #expect(throws: FunctionsError.self) {
      try await client.functions.invoke("hello")
    }

    #expect(dataAuthorizations("/functions/v1/hello") == ["Bearer token-1"])
    #expect(refreshCount == 0)
  }

  @Test
  func postgrestUnauthorizedWithoutAnInvalidTokenChallengeIsNotRetried() async throws {
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/rpc/promote") == true }) { _, _ in
      (
        HTTPResponse(status: .unauthorized, headerFields: [.wwwAuthenticate: "Bearer"]),
        Data(#"{"code":"PT401","message":"not an admin"}"#.utf8)
      )
    }

    let error = try await #require(throws: PostgrestError.self) {
      try await client.rpc("promote").execute()
    }

    #expect(error.serverError?.message == "not an admin")
    #expect(dataAuthorizations("/rest/v1/rpc/promote") == ["Bearer token-1"])
    #expect(refreshCount == 0)
  }

  @Test
  func unauthorizedWithoutASessionIsSentWithTheKeyAndNotRetried() async throws {
    let http = RecordingTransport { _, _ in (invalidTokenUnauthorized, Data()) }
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

  @Test(arguments: [#""exp" claim timestamp check failed"#, "jwt expired"])
  func storageBadRequestForAnExpiredTokenRefreshesAndRetries(message: String) async throws {
    http.respond(when: { $0.path?.hasPrefix("/storage/v1/bucket") == true }) { request, _ in
      request.headerFields[.authorization] == "Bearer token-1"
        ? (HTTPResponse(status: .badRequest), storageExpiredJWTBody(message))
        : (HTTPResponse(status: .ok), Data("[]".utf8))
    }

    _ = try await client.storage.listBuckets()

    #expect(dataAuthorizations("/storage/v1/bucket") == ["Bearer token-1", "Bearer token-2"])
    #expect(refreshCount == 1)
  }

  @Test
  func storageBadRequestWithAnEmptyBodyIsNotRetried() async throws {
    http.respond(when: { $0.path?.hasPrefix("/storage/v1/object") == true }) { _, _ in
      (HTTPResponse(status: .badRequest), Data())
    }

    await #expect(throws: StorageError.self) {
      try await client.storage.from("avatars").download(path: "a.txt")
    }

    #expect(dataAuthorizations("/storage/v1/object") == ["Bearer token-1"])
    #expect(refreshCount == 0)
  }

  @Test
  func storageRLSDenialIsNotRetriedAndKeepsItsBody() async throws {
    http.respond(when: { $0.path?.hasPrefix("/storage/v1/object") == true }) { _, _ in
      (HTTPResponse(status: .badRequest), storageRLSDenialBody)
    }

    let error = try await #require(throws: StorageError.self) {
      try await client.storage.from("avatars").upload(path: "a.txt", data: Data("hello".utf8))
    }

    #expect(error.message == "new row violates row-level security policy")
    #expect(dataAuthorizations("/storage/v1/object") == ["Bearer token-1"])
    #expect(refreshCount == 0)
  }

  /// Drives the middleware itself, with an `AuthClient` built through the `@testable` seam
  /// initializer, so the retry can stop after it reads the held refresh token.
  @Test
  func refreshThatCommitsBeforeTheRetryRefreshesIsNotRedeemedAgain() async throws {
    refreshHandler.setValue { _, body in
      let redeemed = body.map { String(decoding: $0, as: UTF8.self) } ?? ""
      return redeemed.contains("refresh-1")
        ? (
          HTTPResponse(status: .ok), sessionJSON(accessToken: "token-2", refreshToken: "refresh-2")
        )
        : (
          HTTPResponse(status: .ok), sessionJSON(accessToken: "token-3", refreshToken: "refresh-3")
        )
    }
    http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { request, _ in
      request.headerFields[.authorization] == "Bearer token-1"
        ? (invalidTokenUnauthorized, Data())
        : (HTTPResponse(status: .ok), Data("[]".utf8))
    }
    let retryReadTheToken = Gate()
    let auth = AuthClient(
      configuration: AuthClient.Configuration(
        url: URL(string: "https://project-ref.supabase.co/auth/v1")!,
        storageKey: "sb-test-\(UUID().uuidString)-auth-token",
        localStorage: InMemoryLocalStorage(),
        http: HTTPClientConfiguration(transport: http),
        autoRefresh: .manual,
        observesAppLifecycle: false
      ),
      date: { Date() },
      pkce: .live,
      platform: .live,
      beforeRefreshingHeldSession: { await retryReadTheToken.pass() }
    )
    _ = try await auth.signIn(email: "a@b.c", password: "x")
    let middleware = AuthMiddleware(
      auth: auth, fallbackToken: nil, staleTokenRejection: .postgrest, autoRefresh: .manual)

    async let response = middleware.intercept(
      HTTPRequest(
        method: .get, scheme: "https", authority: "project-ref.supabase.co", path: "/rest/v1/todos"),
      body: nil,
      next: { [http] in try await http.send($0, body: $1) }
    )
    await retryReadTheToken.arrivals(1)
    try await auth.refreshSession(refreshToken: "refresh-1")
    retryReadTheToken.open()
    #expect(try await response.0.status == .ok)

    #expect(redeemedRefreshTokens == ["refresh-1"])
    #expect(dataAuthorizations("/rest/v1/todos") == ["Bearer token-1", "Bearer token-2"])
  }

  @Test
  func unauthorizedWithTheCurrentTokenUnderDisabledAutoRefreshIsNotRefreshed() async throws {
    let suite = try await AuthMiddlewareTests(autoRefresh: .disabled)
    suite.http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) { _, _ in
      (invalidTokenUnauthorized, Data(#"{"message":"JWT expired"}"#.utf8))
    }

    let error = try await #require(throws: PostgrestError.self) {
      try await suite.client.from("todos").select().execute()
    }

    #expect(error.serverError?.message == "JWT expired")
    #expect(suite.dataAuthorizations("/rest/v1/todos") == ["Bearer token-1"])
    #expect(suite.refreshCount == 0)
  }

  @Test
  func unauthorizedWithAnOlderTokenUnderDisabledAutoRefreshRetriesWithTheCurrentOne() async throws {
    let suite = try await AuthMiddlewareTests(autoRefresh: .disabled)
    suite.http.respond(when: { $0.path?.hasPrefix("/rest/v1/todos") == true }) {
      [client = suite.client] request, _ in
      guard request.headerFields[.authorization] == "Bearer token-1" else {
        return (HTTPResponse(status: .ok), Data("[]".utf8))
      }
      try await client.auth.refreshSession()
      return (invalidTokenUnauthorized, Data())
    }

    try await suite.client.from("todos").select().execute()

    #expect(suite.dataAuthorizations("/rest/v1/todos") == ["Bearer token-1", "Bearer token-2"])
    #expect(suite.refreshCount == 1)
  }
}

private let userB = "0b0b0b0b-a2ee-47c4-80e1-5bd919f3d8b8"

/// PostgREST's answer to a JWT it cannot accept.
private let invalidTokenUnauthorized = HTTPResponse(
  status: .unauthorized,
  headerFields: [
    .wwwAuthenticate: #"Bearer error="invalid_token", error_description="JWT expired""#
  ]
)

private func functionsGatewayUnauthorized(_ code: String) -> HTTPResponse {
  HTTPResponse(status: .unauthorized, headerFields: [.sbErrorCode: code])
}

private func storageExpiredJWTBody(_ message: String) -> Data {
  Data(
    #"{"statusCode":"403","error":"Unauthorized","message":\#(String(reflecting: message)),"code":"AccessDenied"}"#
      .utf8)
}

private let storageRLSDenialBody = Data(
  #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy","code":"AccessDenied"}"#
    .utf8)

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
