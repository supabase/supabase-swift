//
//  AuthClientConfiguration.swift
//
//
//  Created by Guilherme Souza on 29/04/24.
//

import Alamofire
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension AuthClient {
  /// FetchHandler is a type alias for asynchronous network request handling.
  public typealias FetchHandler =
    @Sendable (
      _ request: URLRequest
    ) async throws -> (Data, URLResponse)

  /// Configuration struct represents the client configuration.
  public struct Configuration: Sendable {
    /// The URL of the Auth server.
    public let url: URL

    /// Any additional headers to send to the Auth server.
    public var headers: [String: String]
    public let flowType: AuthFlowType

    /// Default URL to be used for redirect on the flows that requires it.
    public let redirectToURL: URL?

    /// Optional key name used for storing tokens in local storage.
    public var storageKey: String?

    /// Provider your own local storage implementation to use instead of the default one.
    public let localStorage: any AuthLocalStorage

    /// Custom SupabaseLogger implementation used to inspecting log messages from the Auth library.
    public let logger: (any SupabaseLogger)?
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder

    /// A custom fetch implementation.
    public let fetch: FetchHandler

    /// Alamofire session to use for making requests.
    public let alamofireSession: Alamofire.Session

    /// Set to `true` if you want to automatically refresh the token before expiring.
    public let autoRefreshToken: Bool

    let initWithFetch: Bool

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
    ///   - encoder: The JSON encoder to use for encoding requests.
    ///   - decoder: The JSON decoder to use for decoding responses.
    ///   - alamofireSession: Alamofire session to use for making requests.
    ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
    public init(
      url: URL? = nil,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      localStorage: any AuthLocalStorage,
      logger: (any SupabaseLogger)? = nil,
      encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
      alamofireSession: Alamofire.Session = .default,
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
        encoder: encoder,
        decoder: decoder,
        fetch: { try await alamofireSession.session.data(for: $0) },
        alamofireSession: alamofireSession,
        autoRefreshToken: autoRefreshToken
      )
    }

    init(
      url: URL?,
      headers: [String: String],
      flowType: AuthFlowType,
      redirectToURL: URL?,
      storageKey: String?,
      localStorage: any AuthLocalStorage,
      logger: (any SupabaseLogger)?,
      encoder: JSONEncoder,
      decoder: JSONDecoder,
      fetch: FetchHandler?,
      alamofireSession: Alamofire.Session,
      autoRefreshToken: Bool
    ) {
      let headers = headers.merging(Configuration.defaultHeaders) { l, _ in l }

      self.url = url ?? defaultAuthURL
      self.headers = headers
      self.flowType = flowType
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.localStorage = localStorage
      self.logger = logger
      self.encoder = encoder
      self.decoder = decoder
      self.fetch = fetch ?? { try await alamofireSession.session.data(for: $0) }
      self.alamofireSession = alamofireSession
      self.autoRefreshToken = autoRefreshToken
      self.initWithFetch = fetch != nil
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
  ///   - encoder: The JSON encoder to use for encoding requests.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - alamofireSession: Alamofire session to use for making requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  public init(
    url: URL? = nil,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
    alamofireSession: Alamofire.Session = .default,
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
        encoder: encoder,
        decoder: decoder,
        alamofireSession: alamofireSession,
        autoRefreshToken: autoRefreshToken
      )
    )
  }
}
