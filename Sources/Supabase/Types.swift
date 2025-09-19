import Alamofire
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Configuration options for the Supabase client.
///
/// This struct contains all the configuration options for customizing the behavior
/// of different Supabase services including database, authentication, storage, and functions.
public struct SupabaseClientOptions: Sendable {
  public let db: DatabaseOptions
  public let auth: AuthOptions
  public let global: GlobalOptions
  public let functions: FunctionsOptions
  public let realtime: RealtimeClientOptions
  public let storage: StorageOptions

  /// Configuration options for the database client.
  public struct DatabaseOptions: Sendable {
    /// The Postgres schema which your tables belong to. Must be on the list of exposed schemas in
    /// Supabase. Defaults to "public" if not specified.
    public let schema: String?

    /// The JSONEncoder to use when encoding database request objects.
    /// Useful for custom date formatting or other encoding preferences.
    public let encoder: JSONEncoder

    /// The JSONDecoder to use when decoding database response objects.
    /// Useful for custom date parsing or other decoding preferences.
    public let decoder: JSONDecoder

    public init(
      schema: String? = nil,
      encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
    ) {
      self.schema = schema
      self.encoder = encoder
      self.decoder = decoder
    }
  }

  /// Configuration options for the authentication client.
  public struct AuthOptions: Sendable {
    /// A storage provider. Used to store the logged-in session.
    /// Common implementations include `KeychainLocalStorage` for secure storage
    /// and `InMemoryLocalStorage` for testing.
    public let storage: any AuthLocalStorage

    /// Default URL to be used for redirect on the flows that requires it.
    /// This is used for OAuth flows and password reset emails.
    public let redirectToURL: URL?

    /// Optional key name used for storing tokens in local storage.
    /// If not provided, a default key will be used.
    public let storageKey: String?

    /// OAuth flow to use - defaults to PKCE flow. PKCE is recommended for mobile and server-side
    /// applications as it provides better security than the implicit flow.
    public let flowType: AuthFlowType?

    /// Set to `true` if you want to automatically refresh the token before expiring.
    public let autoRefreshToken: Bool?

    /// Optional function for using a third-party authentication system with Supabase. The function should return an access token or ID token (JWT) by obtaining it from the third-party auth client library.
    /// Note that this function may be called concurrently and many times. Use memoization and locking techniques if this is not supported by the client libraries.
    /// When set, the `auth` namespace of the Supabase client cannot be used.
    /// Create another client if you wish to use Supabase Auth and third-party authentications concurrently in the same application.
    public let accessToken: (@Sendable () async throws -> String?)?

    public init(
      storage: any AuthLocalStorage,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      flowType: AuthFlowType? = nil,
      autoRefreshToken: Bool? = nil,
      accessToken: (@Sendable () async throws -> String?)? = nil
    ) {
      self.storage = storage
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.flowType = flowType
      self.autoRefreshToken = autoRefreshToken
      self.accessToken = accessToken
    }
  }

  public struct GlobalOptions: Sendable {
    /// Optional headers for initializing the client, it will be passed down to all sub-clients.
    public let headers: [String: String]

    /// An Alamofire session to use for making requests across all Supabase modules.
    /// Defaults to `Alamofire.Session.default`.
    public let session: Alamofire.Session

    /// The logger to use across all Supabase sub-packages.
    public let logger: SupabaseLogger?

    /// Request timeout interval in seconds. Defaults to 60 seconds.
    public let timeoutInterval: TimeInterval

    public init(
      headers: [String: String] = [:],
      session: Alamofire.Session = .default,
      logger: SupabaseLogger? = nil,
      timeoutInterval: TimeInterval = 60.0
    ) {
      self.headers = headers
      self.session = session
      self.logger = logger
      self.timeoutInterval = timeoutInterval
    }
  }

  public struct FunctionsOptions: Sendable {
    /// The Region to invoke the functions in.
    public let region: String?

    @_disfavoredOverload
    public init(region: String? = nil) {
      self.region = region
    }

    public init(region: FunctionRegion? = nil) {
      self.init(region: region?.rawValue)
    }
  }

  public struct StorageOptions: Sendable {
    /// Whether storage client should be initialized with the new hostname format, i.e. `project-ref.storage.supabase.co`
    public let useNewHostname: Bool

    /// Upload retry count for failed uploads. Defaults to 3.
    public let uploadRetryCount: Int

    /// Timeout for upload operations in seconds. Defaults to 60 seconds.
    public let uploadTimeoutInterval: TimeInterval

    public init(
      useNewHostname: Bool = false,
      uploadRetryCount: Int = 3,
      uploadTimeoutInterval: TimeInterval = 60.0
    ) {
      self.useNewHostname = useNewHostname
      self.uploadRetryCount = uploadRetryCount
      self.uploadTimeoutInterval = uploadTimeoutInterval
    }
  }

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
      flowType: AuthFlowType? = nil,
      autoRefreshToken: Bool? = nil,
      accessToken: (@Sendable () async throws -> String?)? = nil
    ) {
      self.init(
        storage: AuthClient.Configuration.defaultLocalStorage,
        redirectToURL: redirectToURL,
        storageKey: storageKey,
        flowType: flowType,
        autoRefreshToken: autoRefreshToken,
        accessToken: accessToken
      )
    }
  #endif
}
