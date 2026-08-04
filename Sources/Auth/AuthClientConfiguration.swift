//
//  AuthClientConfiguration.swift
//
//
//  Created by Guilherme Souza on 29/04/24.
//

public import Foundation

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

extension AuthClient {
  /// FetchHandler is a type alias for asynchronous network request handling.
  public typealias FetchHandler =
    @Sendable (
      _ request: URLRequest
    ) async throws -> (Data, URLResponse)

  /// Configuration options for ``AuthClient``.
  ///
  /// ## Topics
  ///
  /// ### Networking
  /// - ``url``
  /// - ``headers``
  /// - ``flowType``
  /// - ``redirectToURL``
  /// - ``fetch``
  ///
  /// ### Storage
  /// - ``localStorage``
  /// - ``storageKey``
  ///
  /// ### Encoding / decoding
  /// - ``encoder``
  /// - ``decoder``
  /// - ``jsonEncoder``
  /// - ``jsonDecoder``
  ///
  /// ### Token refresh
  /// - ``autoRefreshToken``
  /// - ``defaultAutoRefreshToken``
  /// - ``emitLocalSessionAsInitialSession``
  ///
  /// ### Defaults
  /// - ``defaultFlowType``
  /// - ``defaultHeaders``
  public struct Configuration: Sendable {
    /// The URL of the Auth server.
    public let url: URL

    /// Any additional headers to send to the Auth server.
    public var headers: [String: String]

    /// The OAuth / sign-in flow type to use (``AuthFlowType/implicit`` or ``AuthFlowType/pkce``).
    public let flowType: AuthFlowType

    /// Default URL to be used for redirect on the flows that requires it.
    public let redirectToURL: URL?

    /// Optional key name used for storing tokens in local storage.
    public var storageKey: String?

    /// Provider your own local storage implementation to use instead of the default one.
    public let localStorage: any AuthLocalStorage

    /// Custom SupabaseLogger implementation used to inspecting log messages from the Auth library.
    public let logger: (any SupabaseLogger)?

    /// The JSON encoder used to serialize request bodies sent to the Auth server.
    let resolvedEncoder: JSONEncoder

    /// The JSON decoder used to deserialize responses received from the Auth server.
    let resolvedDecoder: JSONDecoder

    /// The JSON encoder used to serialize request bodies sent to the Auth server.
    @available(
      *,
      deprecated,
      message:
        "Customizing Auth's JSON encoding is no longer supported and this property will be removed in a future major version."
    )
    public var encoder: JSONEncoder { resolvedEncoder }

    /// The JSON decoder used to deserialize responses received from the Auth server.
    @available(
      *,
      deprecated,
      message:
        "Customizing Auth's JSON decoding is no longer supported and this property will be removed in a future major version."
    )
    public var decoder: JSONDecoder { resolvedDecoder }

    /// A custom fetch implementation.
    public let fetch: FetchHandler

    /// Set to `true` if you want to automatically refresh the token before expiring.
    public let autoRefreshToken: Bool

    /// When `true`, emits the locally stored session immediately as the initial session,
    /// regardless of its validity or expiration. When `false`, emits the initial session
    /// after attempting to refresh the local stored session (legacy behavior).
    ///
    /// Default is `false` for backward compatibility. This will change to `true` in the next major release.
    ///
    /// - Note: If you rely on the initial session to opt users in, you need to add an additional
    ///   check for `session.isExpired` when this is set to `true`.
    public let emitLocalSessionAsInitialSession: Bool

    /// Initializes a AuthClient Configuration with optional parameters.
    ///
    /// - Parameters:
    ///   - url: The base URL of the Auth server.
    ///   - headers: Custom headers to be included in requests.
    ///   - flowType: The authentication flow type.
    ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
    ///   - storageKey: Optional key name used for storing tokens in local storage.
    ///   - localStorage: The storage mechanism for local data.
    ///   - logger: The logger to use.
    ///   - fetch: The asynchronous fetch handler for network requests.
    ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
    ///   - emitLocalSessionAsInitialSession: When `true`, emits the locally stored session immediately as the initial session.
    public init(
      url: URL? = nil,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      localStorage: any AuthLocalStorage,
      logger: (any SupabaseLogger)? = nil,
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
      autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
      emitLocalSessionAsInitialSession: Bool = false
    ) {
      self.init(
        url: url,
        headers: headers,
        flowType: flowType,
        redirectToURL: redirectToURL,
        storageKey: storageKey,
        localStorage: localStorage,
        logger: logger,
        resolvedEncoder: AuthClient.Configuration.jsonEncoder,
        resolvedDecoder: AuthClient.Configuration.jsonDecoder,
        fetch: fetch,
        autoRefreshToken: autoRefreshToken,
        emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
      )
    }

    /// Designated initializer that stores the resolved JSON encoder/decoder.
    ///
    /// Kept internal so the (deprecated) initializers that still accept custom
    /// `encoder`/`decoder` values can share the field-assignment logic without
    /// exposing the customization point publicly.
    init(
      url: URL? = nil,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      localStorage: any AuthLocalStorage,
      logger: (any SupabaseLogger)? = nil,
      resolvedEncoder: JSONEncoder,
      resolvedDecoder: JSONDecoder,
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
      autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
      emitLocalSessionAsInitialSession: Bool = false
    ) {
      let headers = headers.merging(Configuration.defaultHeaders) { l, _ in l }

      self.url = url ?? defaultAuthURL
      self.headers = headers
      self.flowType = flowType
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.localStorage = localStorage
      self.logger = logger
      self.resolvedEncoder = resolvedEncoder
      self.resolvedDecoder = resolvedDecoder
      self.fetch = fetch
      self.autoRefreshToken = autoRefreshToken
      self.emitLocalSessionAsInitialSession = emitLocalSessionAsInitialSession
    }
  }

  /// Initializes a AuthClient with optional parameters.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type..
  ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
  ///   - storageKey: Optional key name used for storing tokens in local storage.
  ///   - localStorage: The storage mechanism for local data..
  ///   - logger: The logger to use.
  ///   - fetch: The asynchronous fetch handler for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  ///   - emitLocalSessionAsInitialSession: When `true`, emits the locally stored session immediately as the initial session.
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken,
    emitLocalSessionAsInitialSession: Bool = false
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        headers: headers,
        flowType: flowType,
        redirectToURL: redirectToURL,
        storageKey: storageKey,
        localStorage: localStorage,
        logger: logger,
        fetch: fetch,
        autoRefreshToken: autoRefreshToken,
        emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
      )
    )
  }
}
