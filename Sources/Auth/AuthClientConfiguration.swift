//
//  AuthClientConfiguration.swift
//
//
//  Created by Guilherme Souza on 29/04/24.
//

public import Foundation
public import Logging

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
  /// - ``jsonEncoder``
  /// - ``jsonDecoder``
  ///
  /// ### Token refresh
  /// - ``autoRefreshToken``
  /// - ``defaultAutoRefreshToken``
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

    /// The logger used by the Auth library. Defaults to a build-config-aware logger: visible
    /// (warning+) in debug builds, silent in release builds. Pass your own `Logging.Logger` for
    /// custom behavior — see swift-log's documentation for available `LogHandler`s.
    public let logger: Logging.Logger

    /// The JSON encoder used to serialize request bodies sent to the Auth server.
    let resolvedEncoder: JSONEncoder

    /// The JSON decoder used to deserialize responses received from the Auth server.
    let resolvedDecoder: JSONDecoder

    /// A custom fetch implementation.
    public let fetch: FetchHandler

    /// Set to `true` if you want to automatically refresh the token before expiring.
    public let autoRefreshToken: Bool

    /// Initializes a AuthClient Configuration with optional parameters.
    ///
    /// - Parameters:
    ///   - url: The base URL of the Auth server.
    ///   - headers: Custom headers to be included in requests.
    ///   - flowType: The authentication flow type.
    ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
    ///   - storageKey: Optional key name used for storing tokens in local storage.
    ///   - localStorage: The storage mechanism for local data.
    ///   - logger: The logger to use. Defaults to a build-config-aware logger — see `Configuration.logger`.
    ///   - fetch: The asynchronous fetch handler for network requests.
    ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
    public init(
      url: URL? = nil,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      localStorage: any AuthLocalStorage,
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth"),
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
      autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken
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
        autoRefreshToken: autoRefreshToken
      )
    }

    /// Designated initializer that stores the resolved JSON encoder/decoder.
    ///
    /// Kept internal since customizing Auth's JSON encoding/decoding is not a
    /// publicly supported customization point.
    init(
      url: URL? = nil,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      localStorage: any AuthLocalStorage,
      logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth"),
      resolvedEncoder: JSONEncoder,
      resolvedDecoder: JSONDecoder,
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
      autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken
    ) {
      let headers = headers.merging(Configuration.defaultHeaders) { l, _ in l }

      self.url = url ?? defaultAuthURL
      self.headers = headers
      self.flowType = flowType
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.localStorage = localStorage
      var logger = logger
      logger[metadataKey: "system"] = "auth"
      self.logger = logger
      self.resolvedEncoder = resolvedEncoder
      self.resolvedDecoder = resolvedDecoder
      self.fetch = fetch
      self.autoRefreshToken = autoRefreshToken
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
  ///   - logger: The logger to use. Defaults to a build-config-aware logger — see `Configuration.logger`.
  ///   - fetch: The asynchronous fetch handler for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.auth"),
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken
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
        autoRefreshToken: autoRefreshToken
      )
    )
  }
}
