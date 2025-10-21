import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct SupabaseClientOptions: Sendable {
  public let db: DatabaseOptions
  public let auth: AuthOptions
  public let global: GlobalOptions
  public let functions: FunctionsOptions
  public let realtime: RealtimeClientOptions
  public let storage: StorageOptions

  public struct DatabaseOptions: Sendable {
    /// The Postgres schema which your tables belong to. Must be on the list of exposed schemas in
    /// Supabase.
    public let schema: String?

    /// The JSONEncoder to use when encoding database request objects.
    public let encoder: JSONEncoder

    /// The JSONDecoder to use when decoding database response objects.
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

    /// The JSON encoder to use for encoding requests.
    public let encoder: JSONEncoder

    /// The JSON decoder to use for decoding responses.
    public let decoder: JSONDecoder

    /// Set to `true` if you want to automatically refresh the token before expiring.
    public let autoRefreshToken: Bool

    /// When `true`, emits the locally stored session immediately as the initial session,
    /// regardless of its validity or expiration. When `false`, emits the initial session
    /// after attempting to refresh the local stored session (legacy behavior).
    ///
    /// Default is `false` for backward compatibility. This will change to `true` in the next major release.
    public let emitLocalSessionAsInitialSession: Bool

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
      encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
      autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
      emitLocalSessionAsInitialSession: Bool = false,
      accessToken: (@Sendable () async throws -> String?)? = nil
    ) {
      self.storage = storage
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.flowType = flowType
      self.encoder = encoder
      self.decoder = decoder
      self.autoRefreshToken = autoRefreshToken
      self.emitLocalSessionAsInitialSession = emitLocalSessionAsInitialSession
      self.accessToken = accessToken
    }
  }

  public struct GlobalOptions: Sendable {
    /// Optional headers for initializing the client, it will be passed down to all sub-clients.
    public let headers: [String: String]

    /// A session to use for making requests, defaults to `URLSession.shared`.
    public let session: URLSession

    /// The logger  to use across all Supabase sub-packages.
    public let logger: (any SupabaseLogger)?

    public init(
      headers: [String: String] = [:],
      session: URLSession = .shared,
      logger: (any SupabaseLogger)? = nil
    ) {
      self.headers = headers
      self.session = session
      self.logger = logger
    }
  }

  public struct FunctionsOptions: Sendable {
    /// The Region to invoke the functions in.
    public let region: FunctionRegion?

    public init(region: FunctionRegion? = nil) {
      self.region = region
    }
  }

  public struct StorageOptions: Sendable {
    /// Whether storage client should be initialized with the new hostname format, i.e. `project-ref.storage.supabase.co`
    public let useNewHostname: Bool
    
    public init(useNewHostname: Bool = false) {
      self.useNewHostname = useNewHostname
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
      flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
      encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
      autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
      emitLocalSessionAsInitialSession: Bool = false,
      accessToken: (@Sendable () async throws -> String?)? = nil
    ) {
      self.init(
        storage: AuthClient.Configuration.defaultLocalStorage,
        redirectToURL: redirectToURL,
        storageKey: storageKey,
        flowType: flowType,
        encoder: encoder,
        decoder: decoder,
        autoRefreshToken: autoRefreshToken,
        emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession,
        accessToken: accessToken
      )
    }
  #endif
}
