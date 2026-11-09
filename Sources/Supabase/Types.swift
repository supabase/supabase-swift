public import Foundation
public import Helpers
public import Logging
@_spi(Experimental) public import Storage

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

extension SupabaseClient {
  /// The settings a ``SupabaseClient`` is created with.
  ///
  /// Pass it to ``SupabaseClient/init(supabaseURL:supabaseKey:configuration:)`` to override the
  /// defaults of any sub-client. The client derives each sub-client's URL and key itself, so no
  /// type here repeats a module's own configuration type.
  ///
  /// ```swift
  /// var configuration = SupabaseClient.Configuration()
  /// configuration.database.schema = "private"
  /// configuration.global.headers["X-App"] = "my-app"
  /// let supabase = SupabaseClient(
  ///   supabaseURL: supabaseURL,
  ///   supabaseKey: supabaseKey,
  ///   configuration: configuration
  /// )
  /// ```
  public struct Configuration: Sendable {
    /// Settings for the database (PostgREST) sub-client.
    public var database: Database
    /// Settings for the Auth sub-client.
    public var auth: Auth
    /// Settings shared across all sub-clients.
    public var global: Global
    /// Settings for the Edge Functions sub-client.
    public var functions: Functions
    /// Settings for the Realtime sub-client.
    public var realtime: Realtime
    /// Settings for the Storage sub-client.
    public var storage: Storage

    /// Settings for the database (PostgREST) sub-client.
    public struct Database: Sendable {
      /// The Postgres schema which your tables belong to. Must be on the list of exposed schemas in
      /// Supabase.
      public var schema: String?

      /// The JSONEncoder to use when encoding database request objects.
      ///
      /// Applies to the untyped API (`from(_:)` with a table name, `rpc(_:)`) only. The typed API
      /// always uses a fixed encoder.
      public var encoder: JSONEncoder

      /// The JSONDecoder to use when decoding database response objects.
      ///
      /// Applies to the untyped API (`from(_:)` with a table name, `rpc(_:)`) only. The typed API
      /// always uses a fixed decoder.
      public var decoder: JSONDecoder

      /// Whether to automatically retry transient (network, 503 or 520) PostgREST errors on GET
      /// and HEAD requests. Defaults to `true`.
      public var retry: Bool

      /// Creates the database settings.
      /// - Parameters:
      ///   - schema: The Postgres schema queries target. `nil` uses `public`.
      ///   - encoder: The encoder for request bodies of the untyped API. Defaults to a new
      ///     `JSONEncoder.supabase()`.
      ///   - decoder: The decoder for responses of the untyped API. Defaults to a new
      ///     `JSONDecoder.supabase()`.
      ///   - retry: Whether to retry transient errors on GET and HEAD requests.
      public init(
        schema: String? = nil,
        encoder: JSONEncoder = .supabase(),
        decoder: JSONDecoder = .supabase(),
        retry: Bool = true
      ) {
        self.schema = schema
        self.encoder = encoder
        self.decoder = decoder
        self.retry = retry
      }
    }

    /// Settings for the Auth sub-client.
    public struct Auth: Sendable {
      /// A storage provider. Used to store the logged-in session. `nil` uses the platform's default
      /// storage. See ``AuthClient/Configuration/storage``.
      public var storage: (any AuthStorage)?

      /// Default URL to be used for redirect on the flows that requires it.
      public var redirectToURL: URL?

      /// Optional key name used for storing tokens in local storage.
      public var storageKey: String?

      /// When the Auth client refreshes the session on its own. See
      /// ``AuthClient/Configuration/autoRefresh``.
      public var autoRefresh: AuthClient.AutoRefreshPolicy

      /// Whether auto refresh pauses in the background and resumes in the foreground. See
      /// ``AuthClient/Configuration/observesAppLifecycle``.
      public var observesAppLifecycle: Bool

      /// Overrides ``SupabaseClient/Configuration/Global/http`` for Auth, field by field: a `nil`
      /// transport or timeout falls back to the global one, and its middlewares run after the
      /// global ones. `nil` uses the global configuration as is. Auth requests only; PostgREST,
      /// Storage and Functions keep the global configuration.
      public var http: HTTPClientConfiguration?

      /// Overrides ``SupabaseClient/Configuration/Global/logger`` for Auth. `nil` uses the global
      /// logger.
      public var logger: Logging.Logger?

      /// Overrides ``SupabaseClient/Configuration/Global/clock`` for Auth: the clock auto refresh
      /// and Auth's request-retry backoff sleep on. `nil` uses the global clock.
      ///
      /// Every other sub-client keeps following ``SupabaseClient/Configuration/Global/clock``, so
      /// set this only to drive Auth apart from them.
      public var clock: (any Clock<Duration>)?

      /// Optional function for using a third-party authentication system with Supabase. The function should return an access token or ID token (JWT) by obtaining it from the third-party auth client library.
      /// Note that this function may be called concurrently and many times. Use memoization and locking techniques if this is not supported by the client libraries.
      /// When set, the `auth` namespace of the Supabase client cannot be used.
      /// When set, the client also never refreshes a stored session on its own, whatever ``autoRefresh`` says.
      /// Create another client if you wish to use Supabase Auth and third-party authentications concurrently in the same application.
      public var accessToken: (@Sendable () async throws -> String?)?

      /// Creates the Auth settings.
      /// - Parameters:
      ///   - storage: Where the session is stored. `nil` uses the platform default.
      ///   - redirectToURL: The default redirect URL for Auth flows.
      ///   - storageKey: The storage key for the session. `nil` derives it from the project.
      ///   - autoRefresh: When the client refreshes the session.
      ///   - observesAppLifecycle: Whether auto refresh follows the app's foreground state.
      ///   - http: Overrides the global HTTP settings for Auth requests, field by field. `nil`
      ///     uses the global value.
      ///   - logger: Overrides the global logger for Auth. `nil` uses the global value.
      ///   - clock: Overrides the global clock for Auth. `nil` uses the global value.
      ///   - accessToken: A third-party token source. When set, ``SupabaseClient/auth`` cannot be
      ///     used.
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

    /// Settings shared across all Supabase sub-clients.
    public struct Global: Sendable {
      /// Optional headers for initializing the client, it will be passed down to all sub-clients.
      public var headers: [String: String]

      /// The logger to use across all Supabase sub-packages. Defaults to a build-config-aware
      /// logger: visible (warning+) in debug builds, silent in release builds.
      public var logger: Logging.Logger

      /// The transport, middleware chain and request timeout every sub-client sends through.
      ///
      /// A `nil` ``HTTPClientConfiguration/transport`` (the default) uses ``URLSessionTransport``
      /// over `URLSession.shared`. To send through your own `URLSession`, pass
      /// `URLSessionTransport(session:)` as the transport. The middlewares run before the SDK's own
      /// (trace context, access-token injection) and before the request reaches the transport; in
      /// a module that retries (Auth, PostgREST) they run once per attempt.
      /// ``HTTPClientConfiguration/timeout`` is the idle timeout for every request; leave it `nil`
      /// for the defaults (60 seconds; 150 for Edge Functions).
      public var http: HTTPClientConfiguration

      /// The clock the time-based sub-client behaviors sleep on: Auth's token auto-refresh, Auth's
      /// and Storage's request-retry backoff, and Realtime's heartbeat timer and reconnect backoff.
      ///
      /// Defaults to `ContinuousClock()`. Pass a `TestClock` to drive those behaviors
      /// deterministically in tests instead of waiting out real seconds. `TestClock` comes from
      /// [swift-clocks](https://github.com/pointfreeco/swift-clocks); add it to your test target
      /// yourself, as this package does not export it.
      public var clock: any Clock<Duration>

      /// Creates the shared settings.
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

    /// Settings for the Edge Functions sub-client.
    public struct Functions: Sendable {
      /// The region to invoke functions in. `nil` lets the platform choose.
      public var region: FunctionRegion?

      /// The JSON decoder to use for decoding function response bodies.
      public var decoder: JSONDecoder

      /// Overrides ``SupabaseClient/Configuration/Global/http`` for Functions, field by field: a
      /// `nil` transport or timeout falls back to the global one, and its middlewares run after the
      /// global ones. `nil` uses the global configuration as is.
      public var http: HTTPClientConfiguration?

      /// Overrides ``SupabaseClient/Configuration/Global/logger`` for Functions. `nil` uses the
      /// global logger.
      public var logger: Logger?

      /// Creates the Edge Functions settings.
      /// - Parameters:
      ///   - region: The default region for invocations. `nil` lets the platform pick.
      ///   - decoder: The decoder for function responses. Defaults to a new
      ///     `JSONDecoder.supabase()`.
      ///   - http: Overrides the global HTTP settings for Functions. `nil` uses the global value.
      ///   - logger: Overrides the global logger for Functions. `nil` uses the global value.
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

    /// Settings for the Storage sub-client.
    public struct Storage: Sendable {
      /// Whether storage client should be initialized with the new hostname format, i.e. `project-ref.storage.supabase.co`
      public var usesNewHostname: Bool

      /// Whether to automatically retry transient Storage errors on reads (`GET`, `HEAD`,
      /// `list(path:options:)` and each page of `objects(prefix:options:)`). Writes are never
      /// retried. Defaults to `true`.
      public var retryEnabled: Bool

      /// How resumable uploads are chunked, retried and persisted. See
      /// ``StorageClient/Configuration/resumable``.
      ///
      /// - Warning: Experimental. See `ResumableUpload`.
      @_spi(Experimental) public var resumable = ResumableUploadConfiguration()

      /// Creates the Storage settings.
      /// - Parameters:
      ///   - usesNewHostname: Whether to use the `project-ref.storage.supabase.co` hostname.
      ///   - retryEnabled: Whether to retry transient errors on reads.
      public init(usesNewHostname: Bool = false, retryEnabled: Bool = true) {
        self.usesNewHostname = usesNewHostname
        self.retryEnabled = retryEnabled
      }
    }

    /// Settings for the Realtime sub-client.
    ///
    /// `SupabaseClient` derives the URL, the `apikey` header, the access token and the clock
    /// itself, so they are not settings here.
    public struct Realtime: Sendable {
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

      /// Overrides ``SupabaseClient/Configuration/Global/logger`` for Realtime. `nil` uses the
      /// global logger.
      public var logger: Logging.Logger?

      /// Creates the Realtime settings.
      /// - Parameters:
      ///   - headers: Headers for the WebSocket upgrade request. The global headers win.
      ///   - heartbeatInterval: How often the client sends a heartbeat.
      ///   - requestTimeout: How long a push waits for the server reply.
      ///   - connectOnSubscribe: Whether subscribing to a channel connects the socket.
      ///   - disconnectOnEmptyChannelsAfter: How long the socket stays open with no channels.
      ///   - handleAppLifecycle: Whether the client follows the app lifecycle.
      ///   - monitorsNetworkPath: Whether the client reconnects when the network comes back.
      ///   - serverLogLevel: The server-side log level. `nil` uses the server default.
      ///   - webSocketTransport: The WebSocket stack. `nil` uses the default transport.
      ///   - http: The HTTP settings for `RealtimeChannel.httpSend` calls.
      ///   - logger: The logger for Realtime. `nil` uses the global logger.
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

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - database: Settings for the database (PostgREST) sub-client.
    ///   - auth: Settings for the Auth sub-client.
    ///   - global: Settings shared across all sub-clients.
    ///   - functions: Settings for the Edge Functions sub-client.
    ///   - realtime: Settings for the Realtime sub-client.
    ///   - storage: Settings for the Storage sub-client.
    public init(
      database: Database = .init(),
      auth: Auth = .init(),
      global: Global = .init(),
      functions: Functions = .init(),
      realtime: Realtime = .init(),
      storage: Storage = .init()
    ) {
      self.database = database
      self.auth = auth
      self.global = global
      self.functions = functions
      self.realtime = realtime
      self.storage = storage
    }
  }
}
