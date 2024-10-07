//
//  AuthClientConfiguration.swift
//
//
//  Created by Guilherme Souza on 29/04/24.
//

import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension AuthClient {
  /// FetchHandler is a type alias for asynchronous network request handling.
  public typealias FetchHandler = @Sendable (
    _ request: URLRequest
  ) async throws -> (Data, URLResponse)

  /// Configuration struct represents the client configuration.
  public struct Configuration: Sendable {
    public let url: URL
    public var headers: [String: String]
    public let flowType: AuthFlowType
    public let redirectToURL: URL?

    /// Optional key name used for storing tokens in local storage.
    public var storageKey: String?
    public let localStorage: any AuthLocalStorage
    @available(*, deprecated, message: "SupabaseLogger is deprecated in favor of Logging from apple/swift-log")
    public let logger: (any SupabaseLogger)?
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder
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
    ///   - logger: The logger to use.
    ///   - encoder: The JSON encoder to use for encoding requests.
    ///   - decoder: The JSON decoder to use for decoding responses.
    ///   - fetch: The asynchronous fetch handler for network requests.
    ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
    public init(
      url: URL,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      storageKey: String? = nil,
      localStorage: any AuthLocalStorage,
      logger: (any SupabaseLogger)? = nil,
      encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
      autoRefreshToken: Bool = AuthClient.Configuration.defaultAutoRefreshToken
    ) {
      let headers = headers.merging(Configuration.defaultHeaders) { l, _ in l }

      self.url = url
      self.headers = headers
      self.flowType = flowType
      self.redirectToURL = redirectToURL
      self.storageKey = storageKey
      self.localStorage = localStorage
      self.logger = logger
      self.encoder = encoder
      self.decoder = decoder
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
  ///   - logger: The logger to use.
  ///   - encoder: The JSON encoder to use for encoding requests.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - fetch: The asynchronous fetch handler for network requests.
  ///   - autoRefreshToken: Set to `true` if you want to automatically refresh the token before expiring.
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    storageKey: String? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
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
        encoder: encoder,
        decoder: decoder,
        fetch: fetch,
        autoRefreshToken: autoRefreshToken
      )
    )
  }
}
