import Clocks
import ConcurrencyExtras
import CustomDump
import Foundation
import HTTPTypes
import Helpers
import InlineSnapshotTesting
import Logging
import SnapshotTestingCustomDump
import TestHelpers
import Testing

@testable import Auth
@testable import Functions
@testable import Realtime
@testable import RealtimeV2
@testable import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Captures every request handed to it and responds with an empty JSON array.
/// `startLoading` runs on the `URLSession` delegate queue, so mutable state is lock-guarded.
///
/// Shared with `TracingTests`, which needs it to assert on `traceparent` header injection.
final class RequestCapturingProtocol: URLProtocol {
  private static let storage = LockIsolated<[URLRequest]>([])

  static var capturedRequests: [URLRequest] {
    get { storage.value }
    set { storage.setValue(newValue) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.capturedRequests.append(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("[]".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

func makeMockSession() -> URLSession {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [RequestCapturingProtocol.self]
  return URLSession(configuration: config)
}

final class AuthLocalStorageMock: AuthLocalStorage {
  func store(key _: String, value _: Data) throws {}

  func retrieve(key _: String) throws -> Data? {
    nil
  }

  func remove(key _: String) throws {}
}

@Suite
struct SupabaseClientTests {
  @Test
  func globalClockReachesAuthAndRealtime() {
    let clock = TestClock()
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(storage: AuthLocalStorageMock()),
        global: SupabaseClientOptions.GlobalOptions(clock: clock)
      )
    )

    // Identity, not equality: `any Clock<Duration>` is not `Equatable`, and what matters is that
    // the very instance the caller passed is the one the sub-clients sleep on.
    #expect(client.auth.configuration.clock as AnyObject === clock)
    #expect(client.realtimeV2.options.clock as AnyObject === clock)
  }

  @Test
  func clientInitialization() async {
    let logger = Logging.Logger(label: "test") { _ in SwiftLogNoOpLogHandler() }
    let customSchema = "custom_schema"
    let localStorage = AuthLocalStorageMock()
    let customHeaders = ["header_field": "header_value"]

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        db: SupabaseClientOptions.DatabaseOptions(schema: customSchema),
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          automaticallyRefreshesToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          headers: customHeaders,
          logger: logger
        ),
        functions: SupabaseClientOptions.FunctionsOptions(
          region: .apNortheast1
        ),
        realtime: RealtimeClientOptions(
          headers: ["custom_realtime_header_key": "custom_realtime_header_value"]
        )
      )
    )

    #expect(client.supabaseURL.absoluteString == "https://project-ref.supabase.co")
    #expect(client.supabaseKey == "PUBLISHABLE_KEY")
    #expect(client.storageURL.absoluteString == "https://project-ref.supabase.co/storage/v1")
    #expect(client.databaseURL.absoluteString == "https://project-ref.supabase.co/rest/v1")
    #expect(
      client.functionsURL.absoluteString
        == "https://project-ref.supabase.co/functions/v1"
    )

    assertInlineSnapshot(of: client.headers, as: .customDump) {
      """
      [
        "Apikey": "PUBLISHABLE_KEY",
        "Authorization": "Bearer PUBLISHABLE_KEY",
        "X-Client-Info": "supabase-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0",
        "header_field": "header_value"
      ]
      """
    }
    expectNoDifference(client.headers, client.auth.configuration.headers)
    expectNoDifference(client.headers, client.functions.headers.dictionary)
    expectNoDifference(client.headers, client.storage.configuration.headers)
    expectNoDifference(client.headers, client.rest.configuration.headers)

    #expect(client.functions.region == "ap-northeast-1")

    let realtimeURL = client.realtimeV2.url
    #expect(realtimeURL.absoluteString == "https://project-ref.supabase.co/realtime/v1")

    let realtimeOptions = client.realtimeV2.options
    let expectedRealtimeHeader = client._headers.merging(with: [
      .init("custom_realtime_header_key")!: "custom_realtime_header_value"
    ]
    )
    expectNoDifference(realtimeOptions.headers, expectedRealtimeHeader)
    #expect(realtimeOptions.logger.label == logger.label)

    #expect(!client.auth.configuration.automaticallyRefreshesToken)
    #expect(client.auth.configuration.storageKey == "sb-project-ref-auth-token")

    #expect(
      client.mutableState.listenForAuthEventsTask != nil,
      "should listen for internal auth events"
    )
  }

  @Test
  func realtimeLoggerIsTaggedWithSystemMetadataEvenThoughGlobalLoggerOverridesIt() {
    // Uses a plain Logger (not SwiftLogNoOpLogHandler) because a no-op handler's metadata
    // subscript always reads back nil, which would make this assertion untestable.
    let logger = Logging.Logger(label: "test")

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          automaticallyRefreshesToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(logger: logger)
      )
    )

    let realtimeOptions = client.realtimeV2.options
    #expect(realtimeOptions.logger[metadataKey: "system"] == "realtime")
  }

  @Test
  func dbRetryOptionForwardsToPostgrestClient() {
    let defaultClient = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(storage: AuthLocalStorageMock())
      )
    )
    #expect(defaultClient.rest.configuration.retryEnabled == true)

    let noRetryClient = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        db: SupabaseClientOptions.DatabaseOptions(retry: false),
        auth: SupabaseClientOptions.AuthOptions(storage: AuthLocalStorageMock())
      )
    )
    #expect(noRetryClient.rest.configuration.retryEnabled == false)
  }

  #if !os(Linux) && !os(Android)
    @Test
    func clientInitWithDefaultOptionsShouldBeAvailableInNonLinux() {
      _ = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY"
      )
    }
  #endif

  @Test
  func defaultTransportPropagatedToRealtimeClient() {
    let localStorage = AuthLocalStorageMock()
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          automaticallyRefreshesToken: false
        )
      )
    )

    #expect(
      client.realtimeV2.options.http.transport is URLSessionTransport,
      "the default URLSessionTransport should be propagated to Realtime client"
    )
    #expect(
      client.realtimeV2.options.http.middlewares.contains { $0 is TraceContextMiddleware },
      "SDK middlewares should be installed when the caller sets no transport"
    )
  }

  @Test
  func userProvidedRealtimeTransportIsNotOverridden() {
    let localStorage = AuthLocalStorageMock()
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          automaticallyRefreshesToken: false
        ),
        realtime: RealtimeClientOptions(
          http: .init(transport: ClosureTransport { _, _ in throw URLError(.cancelled) }))
      )
    )

    #expect(
      client.realtimeV2.options.http.transport is ClosureTransport,
      "user-provided realtime transport should be preserved"
    )
    #expect(
      client.realtimeV2.options.http.middlewares.isEmpty,
      "middlewares should stay as the caller passed them when they set a transport"
    )
  }

  @Test
  func realtimeWebSocketSessionComesOnlyFromRealtimeOptions() {
    let localStorage = AuthLocalStorageMock()
    let httpSession = URLSession(configuration: .ephemeral)
    let realtimeSpecificSession = URLSession(configuration: .default)
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          automaticallyRefreshesToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: httpSession))
        ),
        realtime: RealtimeClientOptions(session: realtimeSpecificSession)
      )
    )

    #expect(
      client.realtimeV2.options.session === realtimeSpecificSession,
      "user-provided realtime session should be preserved"
    )

    let clientWithoutRealtimeSession = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          automaticallyRefreshesToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: httpSession))
        )
      )
    )

    #expect(
      clientWithoutRealtimeSession.realtimeV2.options.session == nil,
      "the HTTP transport's URLSession must not leak into Realtime's WebSocket"
    )
  }

  @Test
  func clientInitWithCustomAccessToken() async {
    let localStorage = AuthLocalStorageMock()

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: .init(
        auth: .init(
          storage: localStorage,
          accessToken: { "jwt" }
        )
      )
    )

    #expect(
      client.mutableState.listenForAuthEventsTask == nil,
      "should not listen for internal auth events when using 3p authentication"
    )

    // Not asserting that `client.auth` reports an issue here (as the XCTest version of this
    // test did via `withExpectedIssue`/`withKnownIssue`): under Xcode 26's Swift Testing +
    // XCTest bundle hosting, `reportIssue` (xctest-dynamic-overlay) segfaults the test process
    // when called from a `@Test` function, regardless of which "expected/known issue" wrapper
    // is used. Reproduced locally via `xcodebuild test`; does not reproduce under `swift test`.
    // Tracked as a migration-wide risk in SDK-435 for any later phase whose tests exercise
    // `reportIssue`-instrumented production code.
  }

  @Test
  func customAccessTokenErrorPropagatesInsteadOfFallingBackToAnonKey() async {
    struct TokenProviderError: Error, Equatable {}

    // A URLProtocol that fails any request it receives — proves the request never reaches the
    // network instead of merely trusting that it didn't. Deliberately not the shared
    // `RequestCapturingProtocol`: that's also used by `TracingTests` (a `.serialized` suite that
    // still runs concurrently with this one), so touching its static storage here would race.
    final class UnreachableProtocol: URLProtocol {
      override class func canInit(with request: URLRequest) -> Bool { true }
      override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

      override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      }

      override func stopLoading() {}
    }

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [UnreachableProtocol.self]

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: .init(
        auth: .init(
          storage: AuthLocalStorageMock(),
          accessToken: { throw TokenProviderError() }
        ),
        global: .init(
          http: .init(transport: URLSessionTransport(session: URLSession(configuration: config)))
        )
      )
    )

    await #expect(throws: TokenProviderError.self) {
      try await client.rpc("some_fn").execute()
    }
  }

  @Test
  func missingSessionFallsBackToAnonKeyWithoutCustomAccessToken() async throws {
    // Single-purpose capturing protocol (not the shared `RequestCapturingProtocol`) so this test
    // doesn't race with other suites reading/resetting shared static storage.
    final class CapturingProtocol: URLProtocol {
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

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingProtocol.self]

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: .init(
        auth: .init(storage: AuthLocalStorageMock(), automaticallyRefreshesToken: false),
        global: .init(
          http: .init(transport: URLSessionTransport(session: URLSession(configuration: config)))
        )
      )
    )

    try await client.rpc("some_fn").execute()

    let request = try #require(CapturingProtocol.capturedRequest)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer PUBLISHABLE_KEY")
  }

  @Test
  func listenForAuthEventsTaskDoesNotRetainClient() async {
    final class WeakBox: @unchecked Sendable {
      weak var client: SupabaseClient?
    }
    let box = WeakBox()

    // Narrow scope so ARC drops the last strong reference when it returns.
    func scope() {
      let client = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY",
        options: SupabaseClientOptions(
          auth: SupabaseClientOptions.AuthOptions(
            storage: AuthLocalStorageMock(),
            automaticallyRefreshesToken: false
          )
        )
      )
      box.client = client

      #expect(
        client.mutableState.listenForAuthEventsTask != nil,
        "test precondition: client should be listening for internal auth events"
      )
    }
    scope()

    // Let the auth-state-change plumbing drain before asserting.
    await Task.megaYield()

    #expect(
      box.client == nil,
      "SupabaseClient leaked: the listenForAuthEvents task retained self, preventing deinit."
    )
  }

  @Test
  func subClientsDoNotRetainClient() async {
    final class WeakBox: @unchecked Sendable {
      weak var client: SupabaseClient?
    }
    let box = WeakBox()

    // Narrow scope so ARC drops the last strong reference when it returns.
    func scope() {
      let client = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY",
        options: SupabaseClientOptions(
          auth: SupabaseClientOptions.AuthOptions(
            storage: AuthLocalStorageMock(),
            automaticallyRefreshesToken: false
          )
        )
      )
      box.client = client

      // Materialize every sub-client cached in `mutableState`: each one captures the
      // `fetch`/`upload` closures there, so a `self` capture in one of those closures would
      // form a retain cycle (client -> mutableState -> cached sub-client -> closure -> client).
      _ = client.rest
      _ = client.functions
      _ = client.realtimeV2

      // `storage` builds a fresh, uncached `SupabaseStorageClient` on every access (see
      // `SupabaseClient.storage`), so discarding the result here can't exercise the same
      // detection: nothing keeps the closures it captures alive past this statement, so this
      // arm can't prove `storage` is cycle-free the way the cached sub-clients above can.
      _ = client.storage
    }
    scope()

    await Task.megaYield()

    #expect(
      box.client == nil,
      "SupabaseClient leaked: a cached sub-client retained self, preventing deinit."
    )
  }

  @Test
  func functionsOmitsAuthorizationBearerForNewFormatKey() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "sb_publishable_abc123",
      options: SupabaseClientOptions(auth: .init(storage: AuthLocalStorageMock()))
    )

    #expect(client.functions.headers.dictionary["Authorization"] == nil)
    #expect(client.functions.headers.dictionary["Apikey"] == "sb_publishable_abc123")
  }

  @Test
  func functionsKeepsAuthorizationBearerForLegacyKey() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "legacy-jwt-key",
      options: SupabaseClientOptions(auth: .init(storage: AuthLocalStorageMock()))
    )

    #expect(client.functions.headers.dictionary["Authorization"] == "Bearer legacy-jwt-key")
    #expect(client.functions.headers.dictionary["Apikey"] == "legacy-jwt-key")
  }

  @Test
  func globalTransportAndMiddlewaresReachEverySubClient() async throws {
    let seenByMiddleware = LockIsolated<[HTTPTypes.HTTPRequest]>([])
    let seenByTransport = LockIsolated<[HTTPTypes.HTTPRequest]>([])
    let transport = ClosureTransport { request, _ in
      seenByTransport.withValue { $0.append(request) }
      return (
        HTTPTypes.HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
        HTTPBody(Data("[]".utf8))
      )
    }
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          automaticallyRefreshesToken: false,
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: transport, middlewares: [TagMiddleware(seen: seenByMiddleware)]))
      )
    )

    _ = try await client.from("todos").select().execute()
    _ = try? await client.storage.listBuckets()
    _ = try? await client.functions.invoke("hello")

    // Every sub-client reached the caller's transport, through the caller's middleware.
    for prefix in ["/rest/v1/todos", "/storage/v1/bucket", "/functions/v1/hello"] {
      #expect(seenByTransport.value.contains { $0.path?.hasPrefix(prefix) == true })
    }
    #expect(seenByTransport.value.allSatisfy { $0.headerFields[.tag] == "yes" })

    // Caller middlewares run *before* `AccessTokenMiddleware`: REST and Storage still carry the
    // anon key when the caller's middleware sees them, and the live token by the time they reach
    // the transport.
    for prefix in ["/rest/v1/todos", "/storage/v1/bucket"] {
      #expect(
        authorization(in: seenByMiddleware.value, forPathPrefix: prefix) == "Bearer PUBLISHABLE_KEY"
      )
      #expect(
        authorization(in: seenByTransport.value, forPathPrefix: prefix)
          == "Bearer live-session-token"
      )
    }

    // Functions deliberately gets no `AccessTokenMiddleware`: it resolves the token itself while
    // building the request, so the live token is already on the header before any middleware runs.
    #expect(
      authorization(in: seenByMiddleware.value, forPathPrefix: "/functions/v1/hello")
        == "Bearer live-session-token"
    )
    #expect(
      authorization(in: seenByTransport.value, forPathPrefix: "/functions/v1/hello")
        == "Bearer live-session-token"
    )
  }

  @Test
  func globalTimeoutIntervalReachesEverySubClient() async throws {
    let seen = LockIsolated<[(path: String, timeout: Duration?)]>([])
    let transport = ClosureTransport { request, _ in
      seen.withValue { $0.append((request.path ?? "", RequestTimeout.current)) }
      return (
        HTTPTypes.HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
        HTTPBody(Data("[]".utf8))
      )
    }
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          automaticallyRefreshesToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: transport, timeout: .seconds(7)))
      )
    )

    _ = try await client.from("todos").select().execute()
    _ = try? await client.storage.listBuckets()
    _ = try? await client.functions.invoke("hello")
    _ = try? await client.auth.resetPasswordForEmail("a@b.c")

    for prefix in [
      "/rest/v1/todos", "/storage/v1/bucket", "/functions/v1/hello", "/auth/v1/recover",
    ] {
      let entry = try #require(seen.value.first { $0.path.hasPrefix(prefix) }, "\(prefix)")
      #expect(entry.timeout == .seconds(7), "\(prefix)")
    }
    #expect(client.realtimeV2.options.http.timeout == .seconds(7))
  }

  @Test
  func globalTransportAndMiddlewaresReachAuth() async throws {
    let seen = LockIsolated<[HTTPTypes.HTTPRequest]>([])
    let transport = ClosureTransport { request, _ in
      seen.withValue { $0.append(request) }
      return (
        HTTPTypes.HTTPResponse(
          status: .badRequest, headerFields: [.contentType: "application/json"]
        ),
        HTTPBody(Data("{}".utf8))
      )
    }
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          automaticallyRefreshesToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: transport, middlewares: [TagMiddleware()]))
      )
    )

    _ = try? await client.auth.signIn(email: "a@b.c", password: "x")

    let request = try #require(seen.value.first { $0.path?.hasPrefix("/auth/v1/token") == true })
    #expect(request.headerFields[.tag] == "yes")
  }

  @Test
  func realtimeKeepsCallerMiddlewaresWhenSDKInstallsItsOwn() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          automaticallyRefreshesToken: false
        ),
        realtime: RealtimeClientOptions(http: .init(middlewares: [TagMiddleware()]))
      )
    )

    let middlewares = client.realtimeV2.options.http.middlewares
    #expect(middlewares.contains { $0 is TagMiddleware })
    #expect(middlewares.contains { $0 is TraceContextMiddleware })
  }
}

/// Stamps `X-Tag` on every request and records what it saw, so tests can assert both that a
/// caller-supplied middleware runs and what the headers looked like at that point in the chain.
private struct TagMiddleware: ClientMiddleware {
  let seen: LockIsolated<[HTTPTypes.HTTPRequest]>

  init(seen: LockIsolated<[HTTPTypes.HTTPRequest]> = LockIsolated([])) {
    self.seen = seen
  }

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var tagged = request
    tagged.headerFields[.tag] = "yes"
    seen.withValue { [tagged] in $0.append(tagged) }
    return try await next(tagged, body)
  }
}

/// The `Authorization` header of the first recorded request whose path starts with `prefix`.
private func authorization(
  in requests: [HTTPTypes.HTTPRequest],
  forPathPrefix prefix: String
) -> String? {
  requests.first { $0.path?.hasPrefix(prefix) == true }?.headerFields[.authorization]
}

extension HTTPField.Name {
  fileprivate static let tag = HTTPField.Name("X-Tag")!
}
