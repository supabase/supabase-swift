public import Foundation
public import Helpers
public import Logging
@_spi(Experimental) public import Storage

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

/// Configuration options for customizing ``SupabaseClient`` behavior.
///
/// Pass an instance of this struct to ``SupabaseClient/init(supabaseURL:supabaseKey:options:)``
/// to override defaults for any sub-client.
public struct SupabaseClientOptions: Sendable {
  /// Options for the database (PostgREST) sub-client.
  public let db: DatabaseOptions
  /// Options for the Auth sub-client.
  public let auth: AuthOptions
  /// Options shared across all sub-clients.
  public let global: GlobalOptions
  /// Options for the Edge Functions sub-client.
  public let functions: FunctionsOptions
  /// Options for the Realtime sub-client.
  public let realtime: RealtimeOptions
  /// Options for the Storage sub-client.
  public let storage: StorageOptions

  /// Options for the database (PostgREST) sub-client.
  public struct DatabaseOptions: Sendable {
    /// The Postgres schema which your tables belong to. Must be on the list of exposed schemas in
    /// Supabase.
    public let schema: String?

    /// The JSONEncoder to use when encoding database request objects.
    ///
    /// Applies to the untyped API (`from(_:)` with a table name, `rpc(_:)`) only. The typed API
    /// always uses a fixed encoder.
    public let encoder: JSONEncoder

    /// The JSONDecoder to use when decoding database response objects.
    ///
    /// Applies to the untyped API (`from(_:)` with a table name, `rpc(_:)`) only. The typed API
    /// always uses a fixed decoder.
    public let decoder: JSONDecoder

    /// Whether to automatically retry transient (network, 503 or 520) PostgREST errors on GET
    /// and HEAD requests. Defaults to `true`.
    public let retry: Bool

    public init(
      schema: String? = nil,
      encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder,
      retry: Bool = true
    ) {
      self.schema = schema
      self.encoder = encoder
      self.decoder = decoder
      self.retry = retry
    }
  }

  /// Options for the Auth sub-client.
  public struct AuthOptions: Sendable {
    /// A storage provider. Used to store the logged-in session. `nil` uses the platform's default
    /// storage. See ``AuthClient/Configuration/storage``.
    public let storage: (any AuthStorage)?

    /// Default URL to be used for redirect on the flows that requires it.
    public let redirectToURL: URL?

    /// Optional key name used for storing tokens in local storage.
    public let storageKey: String?

    /// When the Auth client refreshes the session on its own. See
    /// ``AuthClient/Configuration/autoRefresh``.
    public let autoRefresh: AuthClient.AutoRefreshPolicy

    /// Whether auto refresh pauses in the background and resumes in the foreground. See
    /// ``AuthClient/Configuration/observesAppLifecycle``.
    public let observesAppLifecycle: Bool

    /// Overrides ``SupabaseClientOptions/GlobalOptions/http`` for Auth, field by field: a `nil`
    /// transport or timeout falls back to the global one, and its middlewares run after the
    /// global ones. `nil` uses the global configuration as is. Auth requests only; PostgREST,
    /// Storage and Functions keep the global configuration.
    public let http: HTTPClientConfiguration?

    /// Overrides ``SupabaseClientOptions/GlobalOptions/logger`` for Auth. `nil` uses the global
    /// logger.
    public let logger: Logging.Logger?

    /// Overrides ``SupabaseClientOptions/GlobalOptions/clock`` for Auth: the clock auto refresh
    /// and Auth's request-retry backoff sleep on. `nil` uses the global clock.
    ///
    /// Every other sub-client keeps following ``SupabaseClientOptions/GlobalOptions/clock``, so
    /// set this only to drive Auth apart from them.
    public let clock: (any Clock<Duration>)?

    /// Optional function for using a third-party authentication system with Supabase. The function should return an access token or ID token (JWT) by obtaining it from the third-party auth client library.
    /// Note that this function may be called concurrently and many times. Use memoization and locking techniques if this is not supported by the client libraries.
    /// When set, the `auth` namespace of the Supabase client cannot be used.
    /// When set, the client also never refreshes a stored session on its own, whatever ``autoRefresh`` says.
    /// Create another client if you wish to use Supabase Auth and third-party authentications concurrently in the same application.
    public let accessToken: (@Sendable () async throws -> String?)?

    public init(
      storage: (any AuthStorage)? = nil,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      autoRefresh: AuthClient.AutoRefreshPolicy = .automatic,
      observesAppLifecycle: Bool = true,
      http: HTTPClientConfiguration? = nil,
      logger: Logging.Logger? = nil,
      clock: (any Clock<Duration>)? = nil,
      accessToken: (@Sendable () async throws -> String?)? = nil
    ) {
      self.storage = storage
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.autoRefresh = autoRefresh
      self.observesAppLifecycle = observesAppLifecycle
      self.http = http
      self.logger = logger
      self.clock = clock
      self.accessToken = accessToken
    }
  }

  /// Options shared across all Supabase sub-clients.
  public struct GlobalOptions: Sendable {
    /// Optional headers for initializing the client, it will be passed down to all sub-clients.
    public let headers: [String: String]

    /// The logger to use across all Supabase sub-packages. Defaults to a build-config-aware
    /// logger: visible (warning+) in debug builds, silent in release builds.
    public let logger: Logging.Logger

    /// The transport, middleware chain and request timeout every sub-client sends through.
    ///
    /// A `nil` ``HTTPClientConfiguration/transport`` (the default) uses ``URLSessionTransport``
    /// over `URLSession.shared`. To send through your own `URLSession`, pass
    /// `URLSessionTransport(session:)` as the transport. The middlewares run before the SDK's own
    /// (trace context, access-token injection) and before the request reaches the transport; in
    /// a module that retries (Auth, PostgREST) they run once per attempt.
    /// ``HTTPClientConfiguration/timeout`` is the idle timeout for every request; leave it `nil`
    /// for the defaults (60 seconds; 150 for Edge Functions).
    public let http: HTTPClientConfiguration

    /// The clock the time-based sub-client behaviors sleep on: Auth's token auto-refresh, Auth's
    /// and Storage's request-retry backoff, and Realtime's heartbeat timer and reconnect backoff.
    ///
    /// Defaults to `ContinuousClock()`. Pass a `TestClock` to drive those behaviors
    /// deterministically in tests instead of waiting out real seconds. `TestClock` comes from
    /// [swift-clocks](https://github.com/pointfreeco/swift-clocks); add it to your test target
    /// yourself, as this package does not export it.
    public let clock: any Clock<Duration>

    /// Creates the shared options.
    /// - Parameters:
    ///   - headers: Extra headers sent on every request made by every sub-client.
    ///   - http: The transport, middleware chain and request timeout every sub-client sends
    ///     through. A `nil` transport (the default) uses ``URLSessionTransport`` over
    ///     `URLSession.shared`.
    ///   - logger: The logger used across all Supabase sub-packages.
    ///   - clock: The clock every time-based sub-client behavior sleeps on. Defaults to
    ///     `ContinuousClock()`.
    public init(
      headers: [String: String] = [:],
      http: HTTPClientConfiguration = .init(),
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase"),
      clock: any Clock<Duration> = ContinuousClock()
    ) {
      self.headers = headers
      self.http = http
      self.logger = logger
      self.clock = clock
    }
  }

  /// Options for the Edge Functions sub-client.
  public struct FunctionsOptions: Sendable {
    /// The region to invoke functions in. `nil` lets the platform choose.
    public var region: FunctionRegion?

    /// The JSON decoder to use for decoding function response bodies.
    public var decoder: JSONDecoder

    /// Overrides ``SupabaseClientOptions/GlobalOptions/http`` for Functions, field by field: a
    /// `nil` transport or timeout falls back to the global one, and its middlewares run after the
    /// global ones. `nil` uses the global configuration as is.
    public var http: HTTPClientConfiguration?

    /// Overrides ``SupabaseClientOptions/GlobalOptions/logger`` for Functions. `nil` uses the
    /// global logger.
    public var logger: Logger?

    public init(
      region: FunctionRegion? = nil,
      decoder: JSONDecoder = .supabase(),
      http: HTTPClientConfiguration? = nil,
      logger: Logger? = nil
    ) {
      self.region = region
      self.decoder = decoder
      self.http = http
      self.logger = logger
    }
  }

  /// Options for the Storage sub-client.
  public struct StorageOptions: Sendable {
    /// Whether storage client should be initialized with the new hostname format, i.e. `project-ref.storage.supabase.co`
    public let usesNewHostname: Bool

    /// Whether to automatically retry transient Storage errors on reads (`GET`, `HEAD`,
    /// `list(path:options:)` and each page of `objects(prefix:options:)`). Writes are never
    /// retried. Defaults to `true`.
    public let retryEnabled: Bool

    /// How resumable uploads are chunked, retried and persisted. See
    /// `StorageClient.Configuration.resumable`.
    ///
    /// - Warning: Experimental. See `ResumableUpload`.
    @_spi(Experimental) public var resumable = ResumableUploadConfiguration()

    public init(usesNewHostname: Bool = false, retryEnabled: Bool = true) {
      self.usesNewHostname = usesNewHostname
      self.retryEnabled = retryEnabled
    }
  }

  /// Options for the Realtime sub-client.
  ///
  /// `SupabaseClient` derives the URL, the `apikey` header, the access token and the clock
  /// itself, so they are not settings here.
  public struct RealtimeOptions: Sendable {
    /// Headers sent with the WebSocket upgrade request. The global headers and the `apikey`
    /// header win over a header set here; names compare without regard to case.
    public var headers: [String: String]

    /// How often the client sends a heartbeat. See
    /// ``RealtimeClient/Configuration/heartbeatInterval``.
    public var heartbeatInterval: Duration

    /// How long the client waits for the server to answer a request. See
    /// ``RealtimeClient/Configuration/requestTimeout``.
    public var requestTimeout: Duration

    /// Whether subscribing to a channel connects the client. See
    /// ``RealtimeClient/Configuration/connectOnSubscribe``.
    public var connectOnSubscribe: Bool

    /// How long the client keeps the socket open after the last channel is removed. See
    /// ``RealtimeClient/Configuration/disconnectOnEmptyChannelsAfter``.
    public var disconnectOnEmptyChannelsAfter: Duration

    /// Whether the client follows the app lifecycle. See
    /// ``RealtimeClient/Configuration/handleAppLifecycle``.
    public var handleAppLifecycle: Bool

    /// Whether the client reconnects as soon as the network is back. See
    /// ``RealtimeClient/Configuration/monitorsNetworkPath``.
    public var monitorsNetworkPath: Bool

    /// How much the Realtime server logs for this connection. `nil` keeps the server's level.
    public var serverLogLevel: RealtimeServerLogLevel?

    /// The WebSocket stack the client connects with. `nil` uses
    /// ``URLSessionWebSocketTransport``.
    public var webSocketTransport: (any WebSocketTransport)?

    /// The transport and middleware chain `RealtimeChannel.httpSend` calls go through. With a
    /// `nil` transport, the global transport, middlewares and timeout apply, and these
    /// middlewares run after the global ones.
    public var http: HTTPClientConfiguration

    /// Overrides ``SupabaseClientOptions/GlobalOptions/logger`` for Realtime. `nil` uses the
    /// global logger.
    public var logger: Logging.Logger?

    public init(
      headers: [String: String] = [:],
      heartbeatInterval: Duration = RealtimeClient.Configuration.defaultHeartbeatInterval,
      requestTimeout: Duration = RealtimeClient.Configuration.defaultRequestTimeout,
      connectOnSubscribe: Bool = RealtimeClient.Configuration.defaultConnectOnSubscribe,
      disconnectOnEmptyChannelsAfter: Duration = RealtimeClient.Configuration
        .defaultDisconnectOnEmptyChannelsAfter,
      handleAppLifecycle: Bool = RealtimeClient.Configuration.defaultHandleAppLifecycle,
      monitorsNetworkPath: Bool = RealtimeClient.Configuration.defaultMonitorsNetworkPath,
      serverLogLevel: RealtimeServerLogLevel? = nil,
      webSocketTransport: (any WebSocketTransport)? = nil,
      http: HTTPClientConfiguration = .init(),
      logger: Logging.Logger? = nil
    ) {
      self.headers = headers
      self.heartbeatInterval = heartbeatInterval
      self.requestTimeout = requestTimeout
      self.connectOnSubscribe = connectOnSubscribe
      self.disconnectOnEmptyChannelsAfter = disconnectOnEmptyChannelsAfter
      self.handleAppLifecycle = handleAppLifecycle
      self.monitorsNetworkPath = monitorsNetworkPath
      self.serverLogLevel = serverLogLevel
      self.webSocketTransport = webSocketTransport
      self.http = http
      self.logger = logger
    }
  }

  /// Creates a configuration with the given options.
  /// - Parameters:
  ///   - db: Options for the database (PostgREST) sub-client.
  ///   - auth: Options for the Auth sub-client.
  ///   - global: Options shared across all sub-clients.
  ///   - functions: Options for the Edge Functions sub-client.
  ///   - realtime: Options for the Realtime sub-client.
  ///   - storage: Options for the Storage sub-client.
  public init(
    db: DatabaseOptions = .init(),
    auth: AuthOptions,
    global: GlobalOptions = .init(),
    functions: FunctionsOptions = .init(),
    realtime: RealtimeOptions = .init(),
    storage: StorageOptions = .init()
  ) {
    self.db = db
    self.auth = auth
    self.global = global
    self.functions = functions
    self.realtime = realtime
    self.storage = storage
  }
}

extension SupabaseClientOptions {
  public init(
    db: DatabaseOptions = .init(),
    global: GlobalOptions = .init(),
    functions: FunctionsOptions = .init(),
    realtime: RealtimeOptions = .init(),
    storage: StorageOptions = .init()
  ) {
    self.db = db
    auth = .init()
    self.global = global
    self.functions = functions
    self.realtime = realtime
    self.storage = storage
  }
}
