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

@Suite
struct SupabaseClientTests {
  @Test
  func eachDatabaseConfigurationGetsItsOwnDefaultCoders() {
    let first = SupabaseClient.Configuration.Database()
    let second = SupabaseClient.Configuration.Database()

    #expect(first.encoder !== second.encoder)
    #expect(first.decoder !== second.decoder)
  }

  @Test
  func globalClockReachesEverySubClientThatWaits() throws {
    let clock = TestClock()
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(storage: InMemoryAuthStorage()),
        global: SupabaseClient.Configuration.Global(clock: clock)
      )
    )

    #expect(client.auth.configuration.clock as AnyObject === clock)
    #expect(client.realtime.configuration.clock as AnyObject === clock)
    #expect(client.rest.configuration.clock as AnyObject === clock)
    #expect(client.storage.configuration.clock as AnyObject === clock)
  }

  @Test
  func clientInitialization() async throws {
    let logger = Logging.Logger(label: "test") { _ in SwiftLogNoOpLogHandler() }
    let customSchema = "custom_schema"
    let localStorage = InMemoryAuthStorage()
    let customHeaders: HTTPFields = [HTTPField.Name("header_field")!: "header_value"]

    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        database: SupabaseClient.Configuration.Database(schema: customSchema),
        auth: SupabaseClient.Configuration.Auth(
          storage: localStorage,
          autoRefresh: .manual
        ),
        global: SupabaseClient.Configuration.Global(
          headers: customHeaders,
          logger: logger
        ),
        functions: SupabaseClient.Configuration.Functions(
          region: .apNortheast1
        ),
        realtime: SupabaseClient.Configuration.Realtime(
          headers: [HTTPField.Name("custom_realtime_header_key")!: "custom_realtime_header_value"]
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

    expectNoDifference(
      client.headers,
      [
        .apikey: "PUBLISHABLE_KEY",
        .authorization: "Bearer PUBLISHABLE_KEY",
        .xClientInfo:
          "supabase-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0",
        HTTPField.Name("header_field")!: "header_value",
      ]
    )
    expectNoDifference(client.headers, client.auth.configuration.headers)
    var dataHeaders = client.headers
    dataHeaders[.authorization] = nil
    expectNoDifference(dataHeaders, client.functions.configuration.headers)
    expectNoDifference(dataHeaders, client.storage.configuration.headers)
    expectNoDifference(dataHeaders, client.rest.configuration.headers)

    #expect(client.functions.configuration.region == .apNortheast1)

    let realtimeURL = client.realtime.configuration.url
    #expect(realtimeURL.absoluteString == "https://project-ref.supabase.co/realtime/v1")

    let expectedRealtimeHeader = client.headers.merging(with: [
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
  func exposesTheConfigurationItWasCreatedWith() throws {
    var configuration = SupabaseClient.Configuration(auth: .init(storage: InMemoryAuthStorage()))
    configuration.database.schema = "custom"
    configuration.storage.usesNewHostname = true

    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: configuration
    )

    #expect(client.configuration.database.schema == "custom")
    #expect(client.configuration.storage.usesNewHostname)
  }

  @Test
  func realtimeHeadersMergeCaseInsensitively() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(storage: InMemoryAuthStorage()),
        realtime: SupabaseClient.Configuration.Realtime(headers: [
          .apikey: "other", HTTPField.Name("X-Custom")!: "1",
        ])
      )
    )

    let headers = client.realtime.headers
    #expect(headers[values: .apikey] == ["PUBLISHABLE_KEY"])
    #expect(headers[HTTPField.Name("x-custom")!] == "1")
    #expect(client.realtime.configuration.headers[HTTPField.Name("X-Custom")!] == "1")
  }

  @Test
  func realtimeFallsBackToTheGlobalLoggerTaggedWithSystemMetadata() throws {
    // Uses a plain Logger (not SwiftLogNoOpLogHandler) because a no-op handler's metadata
    // subscript always reads back nil, which would make this assertion untestable.
    let logger = Logging.Logger(label: "test")

    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: InMemoryAuthStorage(),
          autoRefresh: .manual
        ),
        global: SupabaseClient.Configuration.Global(logger: logger)
      )
    )

    #expect(client.realtime.logger.label == "test")
    #expect(client.realtime.logger[metadataKey: "system"] == "realtime")
  }

  @Test
  func dbRetryOptionForwardsToPostgrestClient() throws {
    let defaultClient = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(storage: InMemoryAuthStorage())
      )
    )
    #expect(defaultClient.rest.configuration.retryEnabled == true)

    let noRetryClient = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        database: SupabaseClient.Configuration.Database(retryEnabled: false),
        auth: SupabaseClient.Configuration.Auth(storage: InMemoryAuthStorage())
      )
    )
    #expect(noRetryClient.rest.configuration.retryEnabled == false)
  }

  @Test
  func realtimeObservesAppLifecycleForwardsToRealtimeClient() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(storage: InMemoryAuthStorage()),
        realtime: SupabaseClient.Configuration.Realtime(observesAppLifecycle: false)
      )
    )

    #expect(client.realtime.configuration.observesAppLifecycle == false)
  }

  @Test
  func storageResumableOptionForwardsToStorageClient() throws {
    var storageOptions = SupabaseClient.Configuration.Storage()
    storageOptions.resumable = ResumableUploadConfiguration(
      chunkSize: 1024, retryTimeout: .seconds(5))
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(storage: InMemoryAuthStorage()),
        storage: storageOptions
      )
    )

    #expect(client.storage.configuration.resumable.chunkSize == 1024)
    #expect(client.storage.configuration.resumable.retryTimeout == .seconds(5))
  }

  @Test
  func clientInitWithDefaultOptions() async throws {
    // A test bundle has no Keychain entitlement, so reading the stored session reports it. The
    // client reads it in a task it starts, so the test reads the session inside the known issue.
    // `initialization()` is no option: it never returns while the read fails.
    try await withKnownIssue(isIntermittent: true) {
      let client = try SupabaseClient(
        supabaseURL: URL(string: "https://default-options.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY"
      )
      _ = try? await client.auth.session()
    } matching: { issue in
      issue.comments.contains { $0.rawValue.contains("errSecMissingEntitlement") }
    }
  }

  @Test
  func defaultTransportPropagatedToRealtimeClient() throws {
    let localStorage = InMemoryAuthStorage()
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: localStorage,
          autoRefresh: .manual
        )
      )
    )

    #expect(
      client.realtime.configuration.http.transport is URLSessionTransport,
      "the default URLSessionTransport should be propagated to Realtime client"
    )
    #expect(
      client.realtime.configuration.http.middlewares.contains { $0 is TraceContextMiddleware },
      "SDK middlewares should be installed when the caller sets no transport"
    )
  }

  @Test
  func userProvidedRealtimeTransportIsNotOverridden() throws {
    let localStorage = InMemoryAuthStorage()
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: localStorage,
          autoRefresh: .manual
        ),
        realtime: SupabaseClient.Configuration.Realtime(
          http: .init(transport: ClosureTransport { _, _ in throw URLError(.cancelled) }))
      )
    )

    #expect(
      client.realtime.configuration.http.transport is ClosureTransport,
      "user-provided realtime transport should be preserved"
    )
    #expect(
      client.realtime.configuration.http.middlewares.isEmpty,
      "middlewares should stay as the caller passed them when they set a transport"
    )
  }

  @Test
  func realtimeWebSocketTransportComesOnlyFromRealtimeConfiguration() throws {
    let localStorage = InMemoryAuthStorage()
    let httpSession = URLSession(configuration: .ephemeral)
    let realtimeTransport = MarkerWebSocketTransport()
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: localStorage,
          autoRefresh: .manual
        ),
        global: SupabaseClient.Configuration.Global(
          http: .init(transport: URLSessionTransport(session: httpSession))
        ),
        realtime: SupabaseClient.Configuration.Realtime(webSocketTransport: realtimeTransport)
      )
    )

    #expect(
      client.realtime.transport as AnyObject === realtimeTransport,
      "user-provided realtime transport should be used"
    )

    let clientWithoutRealtimeTransport = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: localStorage,
          autoRefresh: .manual
        ),
        global: SupabaseClient.Configuration.Global(
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
  func clientInitWithCustomAccessToken() async throws {
    let localStorage = InMemoryAuthStorage()

    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: .init(
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
  func customAccessTokenErrorPropagatesInsteadOfFallingBackToAnonKey() async throws {
    struct TokenProviderError: Error, Equatable {}

    let transport = ClosureTransport { _, _ in throw URLError(.unknown) }

    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: .init(
        auth: .init(
          storage: InMemoryAuthStorage(),
          accessToken: { throw TokenProviderError() }
        ),
        global: .init(http: .init(transport: transport))
      )
    )

    await #expect(throws: TokenProviderError.self) {
      try await client.rpc("some_fn").execute()
    }
  }

  @Test
  func customAccessTokenClientDoesNotRefreshTheStoredSession() async throws {
    final class StoredSessionStorage: AuthStorage {
      let data: Data
      init(data: Data) { self.data = data }
      func save(_: Data, key _: String) async throws {}
      func load(key _: String) async throws -> Data? { data }
      func remove(key _: String) async throws {}
    }

    let now = Date()
    let stored = Auth.Session(
      accessToken: "stored-access-token",
      tokenType: "bearer",
      expiresIn: .seconds(30),
      expiresAt: now.addingTimeInterval(30),
      receivedAt: now,
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
      data: try PersistedSessionCodec.encode(stored)
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

    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: .init(
        auth: .init(storage: storage, accessToken: { "third-party-jwt" }),
        global: .init(http: .init(transport: transport))
      )
    )

    let session = try await client._auth.session()

    #expect(session.accessToken == "stored-access-token")
    #expect(
      !seen.value.contains { $0.path?.hasPrefix("/auth/v1/token") == true },
      "a client with a third-party access token must not redeem the stored refresh token"
    )
  }

  @Test
  func missingSessionFallsBackToAnonKeyWithoutCustomAccessToken() async throws {
    let transport = RecordingTransport { _, _ in
      (HTTPTypes.HTTPResponse(status: .ok), Data("[]".utf8))
    }

    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: .init(
        auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
        global: .init(http: .init(transport: transport))
      )
    )

    try await client.rpc("some_fn").execute()

    let request = try #require(transport.requests.last)
    #expect(request.head.headerFields[.authorization] == "Bearer PUBLISHABLE_KEY")
  }

  @Test
  func listenForAuthEventsTaskDoesNotRetainClient() async throws {
    final class WeakBox: @unchecked Sendable {
      weak var client: SupabaseClient?
    }
    let box = WeakBox()

    func scope() throws {
      let client = try SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY",
        configuration: SupabaseClient.Configuration(
          auth: SupabaseClient.Configuration.Auth(
            storage: InMemoryAuthStorage(),
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
    try scope()

    await Task.megaYield()

    #expect(
      box.client == nil,
      "SupabaseClient leaked: the listenForAuthEvents task retained self, preventing deinit."
    )
  }

  @Test
  func subClientsDoNotRetainClient() async throws {
    final class WeakBox: @unchecked Sendable {
      weak var client: SupabaseClient?
    }
    let box = WeakBox()

    func scope() throws {
      let client = try SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY",
        configuration: SupabaseClient.Configuration(
          auth: SupabaseClient.Configuration.Auth(
            storage: InMemoryAuthStorage(),
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
    try scope()

    await Task.megaYield()

    #expect(
      box.client == nil,
      "SupabaseClient leaked: a cached sub-client retained self, preventing deinit."
    )
  }

  @Test
  func functionsOmitsAuthorizationBearerForNewFormatKey() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "sb_publishable_abc123",
      configuration: SupabaseClient.Configuration(auth: .init(storage: InMemoryAuthStorage()))
    )

    #expect(client.functions.configuration.headers[.authorization] == nil)
    #expect(client.functions.configuration.headers[.apikey] == "sb_publishable_abc123")
  }

  @Test
  func storageOmitsAuthorizationBearerForNewFormatKey() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "sb_publishable_abc123",
      configuration: SupabaseClient.Configuration(auth: .init(storage: InMemoryAuthStorage()))
    )

    let headers = client.storage.configuration.headers
    #expect(headers[.authorization] == nil)
    #expect(headers[.apikey] == "sb_publishable_abc123")
  }

  @Test
  func functionsCarriesNoStaticAuthorizationHeaderForLegacyKey() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "legacy-jwt-key",
      configuration: SupabaseClient.Configuration(auth: .init(storage: InMemoryAuthStorage()))
    )

    #expect(client.functions.configuration.headers[.authorization] == nil)
    #expect(client.functions.configuration.headers[.apikey] == "legacy-jwt-key")
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
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: InMemoryAuthStorage(),
          autoRefresh: .manual,
          accessToken: { "live-session-token" }
        ),
        global: SupabaseClient.Configuration.Global(
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
  func functionsIsBuiltOnceAndCached() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(auth: .init(storage: InMemoryAuthStorage()))
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
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
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
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
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
  func functionsLoggerIsNotOverwrittenByTheGlobalLogger() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: .init(storage: InMemoryAuthStorage()),
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
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: InMemoryAuthStorage(),
          autoRefresh: .manual
        ),
        global: SupabaseClient.Configuration.Global(
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
    #expect(client.realtime.configuration.http.timeout == .seconds(7))
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
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: InMemoryAuthStorage(),
          autoRefresh: .manual
        ),
        global: SupabaseClient.Configuration.Global(
          http: .init(transport: transport, middlewares: [TagMiddleware()]))
      )
    )

    _ = try? await client.auth.signIn(email: "a@b.c", password: "x")

    let request = try #require(seen.value.first { $0.path?.hasPrefix("/auth/v1/token") == true })
    #expect(request.headerFields[.tag] == "yes")
  }

  @Test
  func realtimeKeepsCallerMiddlewaresWhenSDKInstallsItsOwn() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: SupabaseClient.Configuration.Auth(
          storage: InMemoryAuthStorage(),
          autoRefresh: .manual
        ),
        realtime: SupabaseClient.Configuration.Realtime(http: .init(middlewares: [TagMiddleware()]))
      )
    )

    let middlewares = client.realtime.configuration.http.middlewares
    #expect(middlewares.contains { $0 is TagMiddleware })
    #expect(middlewares.contains { $0 is TraceContextMiddleware })
  }

  @Test
  func authEventsDoNotBuildRealtime() async throws {
    let client = try makeRealtimeAuthClient()

    await client.handleTokenChanged(event: .initialSession, session: nil)
    await client.handleTokenChanged(event: .signedIn, session: .stub(accessToken: "user-token"))
    await client.handleTokenChanged(event: .signedOut, session: nil)

    #expect(client.mutableState.realtime == nil)
  }

  @Test
  func authEventsReachAnExistingRealtimeClient() async throws {
    let client = try makeRealtimeAuthClient()
    let realtime = client.realtime

    await client.handleTokenChanged(
      event: .tokenRefreshed, session: .stub(accessToken: "refreshed-token"))
    #expect(await realtime.accessToken == "refreshed-token")

    await client.handleTokenChanged(event: .signedOut, session: nil)
    #expect(await realtime.accessToken == "PUBLISHABLE_KEY")
  }

  @Test(arguments: [AuthEvent.passwordRecovery, .userUpdated, .mfaChallengeVerified])
  func anyEventThatChangesTheAccessTokenReachesRealtime(event: AuthEvent) async throws {
    let client = try makeRealtimeAuthClient()
    let realtime = client.realtime

    await client.handleTokenChanged(event: event, session: .stub(accessToken: "new-token"))

    #expect(await realtime.accessToken == "new-token")
  }

  @Test
  func realtimeLoggerIsNotOverwrittenByTheGlobalLogger() throws {
    let client = try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: .init(storage: InMemoryAuthStorage(), autoRefresh: .manual),
        global: .init(logger: Logging.Logger(label: "global")),
        realtime: SupabaseClient.Configuration.Realtime(logger: Logging.Logger(label: "realtime"))
      )
    )

    #expect(client.realtime.logger.label == "realtime")
    #expect(client.realtime.logger[metadataKey: "system"] == "realtime")
  }

  /// A third-party `accessToken` keeps the client from listening for auth events, so only the
  /// events a test delivers reach `handleTokenChanged`.
  private func makeRealtimeAuthClient() throws -> SupabaseClient {
    try SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      configuration: SupabaseClient.Configuration(
        auth: .init(storage: InMemoryAuthStorage(), accessToken: { nil }),
        realtime: SupabaseClient.Configuration.Realtime(observesAppLifecycle: false)
      )
    )
  }
}

extension Session {
  static func stub(accessToken: String) -> Session {
    Session(
      accessToken: accessToken,
      tokenType: "bearer",
      expiresIn: .seconds(3600),
      expiresAt: Date(timeIntervalSince1970: 4_102_444_800),
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
