public import Clocks
public import Foundation
public import Helpers
public import Logging

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
  public let realtime: RealtimeClientOptions
  /// Options for the Storage sub-client.
  public let storage: StorageOptions

  /// Options for the database (PostgREST) sub-client.
  public struct DatabaseOptions: Sendable {
    /// The Postgres schema which your tables belong to. Must be on the list of exposed schemas in
    /// Supabase.
    public let schema: String?

    /// The JSONEncoder to use when encoding database request objects.
    public let encoder: JSONEncoder

    /// The JSONDecoder to use when decoding database response objects.
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
    /// A storage provider. Used to store the logged-in session.
    public let storage: any AuthLocalStorage

    /// Default URL to be used for redirect on the flows that requires it.
    public let redirectToURL: URL?

    /// Optional key name used for storing tokens in local storage.
    public let storageKey: String?

    /// OAuth flow to use - defaults to PKCE flow. PKCE is recommended for mobile and server-side
    /// applications.
    public let flowType: AuthFlowType

    /// Set to `true` if you want to automatically refresh the token before expiring.
    public let automaticallyRefreshesToken: Bool

    /// Optional function for using a third-party authentication system with Supabase. The function should return an access token or ID token (JWT) by obtaining it from the third-party auth client library.
    /// Note that this function may be called concurrently and many times. Use memoization and locking techniques if this is not supported by the client libraries.
    /// When set, the `auth` namespace of the Supabase client cannot be used.
    /// Create another client if you wish to use Supabase Auth and third-party authentications concurrently in the same application.
    public let accessToken: (@Sendable () async throws -> String?)?

    public init(
      storage: any AuthLocalStorage,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
      automaticallyRefreshesToken: Bool = AuthClient.Configuration
        .defaultAutomaticallyRefreshesToken,
      accessToken: (@Sendable () async throws -> String?)? = nil
    ) {
      self.storage = storage
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.flowType = flowType
      self.automaticallyRefreshesToken = automaticallyRefreshesToken
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

    /// The clock the time-based sub-client behaviors sleep on: Auth's token auto-refresh and
    /// request-retry backoff, and Realtime's heartbeat timer and reconnect backoff.
    ///
    /// Defaults to `ContinuousClock()`. Pass a `TestClock` (swift-clocks) to drive those
    /// behaviors deterministically in tests instead of waiting out real seconds.
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
    /// The Region to invoke the functions in.
    public let region: String?

    /// The JSON decoder to use for decoding function response bodies.
    public let decoder: JSONDecoder

    @_disfavoredOverload
    public init(
      region: String? = nil,
      decoder: JSONDecoder = JSONDecoder()
    ) {
      self.region = region
      self.decoder = decoder
    }

    public init(
      region: FunctionRegion? = nil,
      decoder: JSONDecoder = JSONDecoder()
    ) {
      self.init(region: region?.rawValue, decoder: decoder)
    }
  }

  /// Options for the Storage sub-client.
  public struct StorageOptions: Sendable {
    /// Whether storage client should be initialized with the new hostname format, i.e. `project-ref.storage.supabase.co`
    public let usesNewHostname: Bool

    public init(usesNewHostname: Bool = false) {
      self.usesNewHostname = usesNewHostname
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
    realtime: RealtimeClientOptions = .init(),
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
  #if !os(Linux) && !os(Android)
    public init(
      db: DatabaseOptions = .init(),
      global: GlobalOptions = .init(),
      functions: FunctionsOptions = .init(),
      realtime: RealtimeClientOptions = .init(),
      storage: StorageOptions = .init()
    ) {
      self.db = db
      auth = .init()
      self.global = global
      self.functions = functions
      self.realtime = realtime
      self.storage = storage
    }
  #endif
}

extension SupabaseClientOptions.AuthOptions {
  #if !os(Linux) && !os(Android)
    public init(
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
      automaticallyRefreshesToken: Bool = AuthClient.Configuration
        .defaultAutomaticallyRefreshesToken,
      accessToken: (@Sendable () async throws -> String?)? = nil
    ) {
      self.init(
        storage: AuthClient.Configuration.defaultLocalStorage,
        redirectToURL: redirectToURL,
        storageKey: storageKey,
        flowType: flowType,
        automaticallyRefreshesToken: automaticallyRefreshesToken,
        accessToken: accessToken
      )
    }
  #endif
}
