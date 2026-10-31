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
@_spi(Experimental) @testable import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class RequestCapturingProtocol: URLProtocol {
  private static let storage = LockIsolated<[URLRequest]>([])

  static var capturedRequests: [URLRequest] {
    get { storage.value }
    set { storage.setValue(newValue) }
  }

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

    #expect(client.auth.configuration.clock as AnyObject === clock)
    #expect(client.realtime.options.clock as AnyObject === clock)
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
          autoRefresh: .manual
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
    var dataHeaders = client.headers
    dataHeaders["Authorization"] = nil
    expectNoDifference(dataHeaders, client.functions.configuration.headers.dictionary)
    expectNoDifference(dataHeaders, client.storage.configuration.headers.dictionary)
    expectNoDifference(dataHeaders, client.rest.configuration.headers)

    #expect(client.functions.configuration.region == .apNortheast1)

    let realtimeURL = client.realtime.url
    #expect(realtimeURL.absoluteString == "https://project-ref.supabase.co/realtime/v1")

    let realtimeOptions = client.realtime.options
    let expectedRealtimeHeader = client._headers.merging(with: [
      .init("custom_realtime_header_key")!: "custom_realtime_header_value"
    ]
    )
    expectNoDifference(client.realtime.headers, expectedRealtimeHeader)
    #expect(client.realtime.logger.label == logger.label)

    #expect(client.auth.configuration.autoRefresh == .manual)
    #expect(client.auth.configuration.storageKey == "sb-project-ref-auth-token")

    #expect(
      client.mutableState.listenForAuthEventsTask != nil,
      "should listen for internal auth events"
    )
  }

  @Test
  func realtimeHeadersMergeCaseInsensitively() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(storage: AuthLocalStorageMock()),
        realtime: RealtimeClientOptions(headers: ["apikey": "other", "X-Custom": "1"])
      )
    )

    let headers = client.realtime.headers
    #expect(headers[values: .apiKey] == ["PUBLISHABLE_KEY"])
    #expect(headers[HTTPField.Name("x-custom")!] == "1")
    #expect(client.realtime.options.headers["X-Custom"] == "1")
  }

  @Test
  func realtimeFallsBackToTheGlobalLoggerTaggedWithSystemMetadata() {
    // Uses a plain Logger (not SwiftLogNoOpLogHandler) because a no-op handler's metadata
    // subscript always reads back nil, which would make this assertion untestable.
    let logger = Logging.Logger(label: "test")

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          autoRefresh: .manual
        ),
        global: SupabaseClientOptions.GlobalOptions(logger: logger)
      )
    )

    #expect(client.realtime.logger.label == "test")
    #expect(client.realtime.logger[metadataKey: "system"] == "realtime")
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

  @Test
  func storageResumableOptionForwardsToStorageClient() {
    var storageOptions = SupabaseClientOptions.StorageOptions()
    storageOptions.resumable = ResumableUploadConfiguration(
      chunkSize: 1024, retryTimeout: .seconds(5))
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(storage: AuthLocalStorageMock()),
        storage: storageOptions
      )
    )

    #expect(client.storage.configuration.resumable.chunkSize == 1024)
    #expect(client.storage.configuration.resumable.retryTimeout == .seconds(5))
  }

  @Test
  func clientInitWithDefaultOptions() {
    // A test bundle on a simulator has no Keychain entitlement, so creating the client reports
    // it. macOS reads the file-based Keychain and reports nothing.
    withKnownIssue(isIntermittent: true) {
      _ = SupabaseClient(
        supabaseURL: URL(string: "https://default-options.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY"
      )
    } matching: { issue in
      issue.comments.contains { $0.rawValue.contains("errSecMissingEntitlement") }
    }
  }

  @Test
  func defaultTransportPropagatedToRealtimeClient() {
    let localStorage = AuthLocalStorageMock()
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefresh: .manual
        )
      )
    )

    #expect(
      client.realtime.options.http.transport is URLSessionTransport,
      "the default URLSessionTransport should be propagated to Realtime client"
    )
    #expect(
      client.realtime.options.http.middlewares.contains { $0 is TraceContextMiddleware },
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
          autoRefresh: .manual
        ),
        realtime: RealtimeClientOptions(
          http: .init(transport: ClosureTransport { _, _ in throw URLError(.cancelled) }))
      )
    )

    #expect(
      client.realtime.options.http.transport is ClosureTransport,
      "user-provided realtime transport should be preserved"
    )
    #expect(
      client.realtime.options.http.middlewares.isEmpty,
      "middlewares should stay as the caller passed them when they set a transport"
    )
  }

  @Test
  func realtimeWebSocketTransportComesOnlyFromRealtimeOptions() {
    let localStorage = AuthLocalStorageMock()
    let httpSession = URLSession(configuration: .ephemeral)
    let realtimeTransport = MarkerWebSocketTransport()
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefresh: .manual
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: httpSession))
        ),
        realtime: RealtimeClientOptions(webSocketTransport: realtimeTransport)
      )
    )

    #expect(
      client.realtime.transport as AnyObject === realtimeTransport,
      "user-provided realtime transport should be used"
    )

    let clientWithoutRealtimeTransport = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefresh: .manual
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: URLSessionTransport(session: httpSession))
        )
      )
    )

    #expect(
      clientWithoutRealtimeTransport.realtime.transport is URLSessionWebSocketTransport,
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
  }

  @Test
  func customAccessTokenErrorPropagatesInsteadOfFallingBackToAnonKey() async {
    struct TokenProviderError: Error, Equatable {}

    final class UnreachableProtocol: URLProtocol {
      override static func canInit(with request: URLRequest) -> Bool { true }
      override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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
  func customAccessTokenClientDoesNotRefreshTheStoredSession() async throws {
    final class StoredSessionStorage: AuthLocalStorage {
      let data: Data
      init(data: Data) { self.data = data }
      func store(key _: String, value _: Data) throws {}
      func retrieve(key _: String) throws -> Data? { data }
      func remove(key _: String) throws {}
    }

    let now = Date()
    let stored = Auth.Session(
      accessToken: "stored-access-token",
      tokenType: "bearer",
      expiresIn: 30,
      expiresAt: now.addingTimeInterval(30).timeIntervalSince1970,
      refreshToken: "stored-refresh-token",
      user: Auth.User(
        id: UUID(),
        appMetadata: [:],
        userMetadata: [:],
        audience: "authenticated",
        createdAt: now,
        updatedAt: now
      )
    )
    let storage = StoredSessionStorage(
      data: try PersistedSessionCodec.encode(ReceivedSession(session: stored, receivedAt: now))
    )

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
      options: .init(
        auth: .init(storage: storage, accessToken: { "third-party-jwt" }),
        global: .init(http: .init(transport: transport))
      )
    )

    let session = try await client._auth.session

    #expect(session.accessToken == "stored-access-token")
    #expect(
      !seen.value.contains { $0.path?.hasPrefix("/auth/v1/token") == true },
      "a client with a third-party access token must not redeem the stored refresh token"
    )
  }

  @Test
  func missingSessionFallsBackToAnonKeyWithoutCustomAccessToken() async throws {
    final class CapturingProtocol: URLProtocol {
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

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CapturingProtocol.self]

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: .init(
        auth: .init(storage: AuthLocalStorageMock(), autoRefresh: .manual),
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

    func scope() {
      let client = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY",
        options: SupabaseClientOptions(
          auth: SupabaseClientOptions.AuthOptions(
            storage: AuthLocalStorageMock(),
            autoRefresh: .manual
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

    func scope() {
      let client = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY",
        options: SupabaseClientOptions(
          auth: SupabaseClientOptions.AuthOptions(
            storage: AuthLocalStorageMock(),
            autoRefresh: .manual
          )
        )
      )
      box.client = client

      _ = client.rest
      _ = client.functions
      _ = client.realtime

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

    #expect(client.functions.configuration.headers[.authorization] == nil)
    #expect(client.functions.configuration.headers[.init("Apikey")!] == "sb_publishable_abc123")
  }

  @Test
  func storageOmitsAuthorizationBearerForNewFormatKey() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "sb_publishable_abc123",
      options: SupabaseClientOptions(auth: .init(storage: AuthLocalStorageMock()))
    )

    let headers = client.storage.configuration.headers
    #expect(headers[.authorization] == nil)
    #expect(headers[.init("Apikey")!] == "sb_publishable_abc123")
  }

  @Test
  func functionsCarriesNoStaticAuthorizationHeaderForLegacyKey() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "legacy-jwt-key",
      options: SupabaseClientOptions(auth: .init(storage: AuthLocalStorageMock()))
    )

    #expect(client.functions.configuration.headers[.authorization] == nil)
    #expect(client.functions.configuration.headers[.init("Apikey")!] == "legacy-jwt-key")
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
          autoRefresh: .manual,
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: transport, middlewares: [TagMiddleware(seen: seenByMiddleware)]))
      )
    )

    _ = try await client.from("todos").select().execute()
    _ = try? await client.storage.listBuckets()
    _ = try? await client.functions.invoke("hello")

    for prefix in ["/rest/v1/todos", "/storage/v1/bucket", "/functions/v1/hello"] {
      #expect(seenByTransport.value.contains { $0.path?.hasPrefix(prefix) == true })
    }
    #expect(seenByTransport.value.allSatisfy { $0.headerFields[.tag] == "yes" })

    for prefix in ["/rest/v1/todos", "/storage/v1/bucket", "/functions/v1/hello"] {
      #expect(authorization(in: seenByMiddleware.value, forPathPrefix: prefix) == nil, "\(prefix)")
      #expect(
        authorization(in: seenByTransport.value, forPathPrefix: prefix)
          == "Bearer live-session-token", "\(prefix)"
      )
    }
  }

  @Test
  func functionsIsBuiltOnceAndCached() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(auth: .init(storage: AuthLocalStorageMock()))
    )

    #expect(client.mutableState.functions == nil)
    _ = client.functions
    #expect(client.mutableState.functions != nil)
  }

  @Test
  func functionsRegionReachesTheWire() async throws {
    let seen = LockIsolated<[HTTPTypes.HTTPRequest]>([])
    let transport = ClosureTransport { request, _ in
      seen.withValue { $0.append(request) }
      return (HTTPTypes.HTTPResponse(status: .ok), nil)
    }
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: .init(storage: AuthLocalStorageMock(), autoRefresh: .manual),
        global: .init(http: .init(transport: transport)),
        functions: .init(region: .usEast1)
      )
    )

    try await client.functions.invoke("hello")

    let request = try #require(seen.value.first)
    #expect(request.headerFields[.init("x-region")!] == "us-east-1")
    #expect(request.url?.query?.contains("forceFunctionRegion=us-east-1") == true)
  }

  @Test
  func functionsHTTPOverridesTheGlobalTransport() async throws {
    let globalSeen = LockIsolated<[HTTPTypes.HTTPRequest]>([])
    let functionsSeen = LockIsolated<[HTTPTypes.HTTPRequest]>([])
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: .init(storage: AuthLocalStorageMock(), autoRefresh: .manual),
        global: .init(
          http: .init(
            transport: ClosureTransport { request, _ in
              globalSeen.withValue { $0.append(request) }
              return (HTTPTypes.HTTPResponse(status: .ok), nil)
            },
            middlewares: [TagMiddleware()])),
        functions: .init(
          http: .init(
            transport: ClosureTransport { request, _ in
              functionsSeen.withValue { $0.append(request) }
              return (HTTPTypes.HTTPResponse(status: .ok), nil)
            }))
      )
    )

    try await client.functions.invoke("hello")

    #expect(globalSeen.value.isEmpty)
    let request = try #require(functionsSeen.value.first)
    #expect(request.headerFields[.tag] == "yes")
  }

  @Test
  func functionsLoggerIsNotOverwrittenByTheGlobalLogger() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: .init(storage: AuthLocalStorageMock()),
        global: .init(logger: Logging.Logger(label: "global")),
        functions: .init(logger: Logging.Logger(label: "functions"))
      )
    )

    #expect(client.functions.configuration.logger.label == "functions")
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
          autoRefresh: .manual
        ),
        global: SupabaseClientOptions.GlobalOptions(
          http: .init(transport: transport, timeout: .seconds(7)))
      )
    )

    _ = try await client.from("todos").select().execute()
    _ = try? await client.storage.listBuckets()
    _ = try? await client.functions.invoke("hello")
    _ = try? await client.auth.resetPassword(email: "a@b.c")

    for prefix in [
      "/rest/v1/todos", "/storage/v1/bucket", "/functions/v1/hello", "/auth/v1/recover",
    ] {
      let entry = try #require(seen.value.first { $0.path.hasPrefix(prefix) }, "\(prefix)")
      #expect(entry.timeout == .seconds(7), "\(prefix)")
    }
    #expect(client.realtime.options.http.timeout == .seconds(7))
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
          autoRefresh: .manual
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
          autoRefresh: .manual
        ),
        realtime: RealtimeClientOptions(http: .init(middlewares: [TagMiddleware()]))
      )
    )

    let middlewares = client.realtime.options.http.middlewares
    #expect(middlewares.contains { $0 is TagMiddleware })
    #expect(middlewares.contains { $0 is TraceContextMiddleware })
  }

  @Test
  func authEventsDoNotBuildRealtime() async {
    let client = makeRealtimeAuthClient()

    await client.handleTokenChanged(event: .initialSession, session: nil)
    await client.handleTokenChanged(event: .signedIn, session: .stub(accessToken: "user-token"))
    await client.handleTokenChanged(event: .signedOut, session: nil)

    #expect(client.mutableState.realtime == nil)
  }

  @Test
  func authEventsReachAnExistingRealtimeClient() async {
    let client = makeRealtimeAuthClient()
    let realtime = client.realtime

    await client.handleTokenChanged(
      event: .tokenRefreshed, session: .stub(accessToken: "refreshed-token"))
    #expect(await realtime.accessToken == "refreshed-token")

    await client.handleTokenChanged(event: .signedOut, session: nil)
    #expect(await realtime.accessToken == "PUBLISHABLE_KEY")
  }

  @Test(arguments: [AuthEvent.passwordRecovery, .userUpdated, .mfaChallengeVerified])
  func anyEventThatChangesTheAccessTokenReachesRealtime(event: AuthEvent) async {
    let client = makeRealtimeAuthClient()
    let realtime = client.realtime

    await client.handleTokenChanged(event: event, session: .stub(accessToken: "new-token"))

    #expect(await realtime.accessToken == "new-token")
  }

  @Test
  func realtimeLoggerIsNotOverwrittenByTheGlobalLogger() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: .init(storage: AuthLocalStorageMock(), autoRefresh: .manual),
        global: .init(logger: Logging.Logger(label: "global")),
        realtime: RealtimeClientOptions(logger: Logging.Logger(label: "realtime"))
      )
    )

    #expect(client.realtime.logger.label == "realtime")
    #expect(client.realtime.logger[metadataKey: "system"] == "realtime")
  }

  /// A third-party `accessToken` keeps the client from listening for auth events, so only the
  /// events a test delivers reach `handleTokenChanged`.
  private func makeRealtimeAuthClient() -> SupabaseClient {
    SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: .init(storage: AuthLocalStorageMock(), accessToken: { nil }),
        realtime: RealtimeClientOptions(handleAppLifecycle: false)
      )
    )
  }
}

extension Session {
  fileprivate static func stub(accessToken: String) -> Session {
    Session(
      accessToken: accessToken,
      tokenType: "bearer",
      expiresIn: 3600,
      expiresAt: 4_102_444_800,
      refreshToken: "refresh-token",
      user: User(
        id: UUID(),
        appMetadata: [:],
        userMetadata: [:],
        audience: "authenticated",
        createdAt: Date(),
        updatedAt: Date()
      )
    )
  }
}

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

private func authorization(
  in requests: [HTTPTypes.HTTPRequest],
  forPathPrefix prefix: String
) -> String? {
  requests.first { $0.path?.hasPrefix(prefix) == true }?.headerFields[.authorization]
}

extension HTTPField.Name {
  fileprivate static let tag = HTTPField.Name("X-Tag")!
}

private final class MarkerWebSocketTransport: WebSocketTransport {
  func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
    throw URLError(.cancelled)
  }
}
