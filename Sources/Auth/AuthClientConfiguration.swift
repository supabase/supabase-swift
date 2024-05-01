//
//  AuthClientConfiguration.swift
//
//
//  Created by Guilherme Souza on 29/04/24.
//

import _Helpers
import Foundation

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
    public let localStorage: any AuthLocalStorage
    public let logger: (any SupabaseLogger)?
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder
    public let fetch: FetchHandler

    /// Initializes a AuthClient Configuration with optional parameters.
    ///
    /// - Parameters:
    ///   - url: The base URL of the Auth server.
    ///   - headers: Custom headers to be included in requests.
    ///   - flowType: The authentication flow type.
    ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
    ///   - localStorage: The storage mechanism for local data.
    ///   - logger: The logger to use.
    ///   - encoder: The JSON encoder to use for encoding requests.
    ///   - decoder: The JSON decoder to use for decoding responses.
    ///   - fetch: The asynchronous fetch handler for network requests.
    public init(
      url: URL,
      headers: [String: String] = [:],
      flowType: AuthFlowType = Configuration.defaultFlowType,
      redirectToURL: URL? = nil,
      localStorage: any AuthLocalStorage,
      logger: (any SupabaseLogger)? = nil,
      encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) }
    ) {
      let headers = headers.merging(Configuration.defaultHeaders) { l, _ in l }

      self.url = url
      self.headers = headers
      self.flowType = flowType
      self.redirectToURL = redirectToURL
      self.localStorage = localStorage
      self.logger = logger
      self.encoder = encoder
      self.decoder = decoder
      self.fetch = fetch
    }
  }

  /// Initializes a AuthClient with optional parameters.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Auth server.
  ///   - headers: Custom headers to be included in requests.
  ///   - flowType: The authentication flow type..
  ///   - redirectToURL: Default URL to be used for redirect on the flows that requires it.
  ///   - localStorage: The storage mechanism for local data..
  ///   - logger: The logger to use.
  ///   - encoder: The JSON encoder to use for encoding requests.
  ///   - decoder: The JSON decoder to use for decoding responses.
  ///   - fetch: The asynchronous fetch handler for network requests.
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    flowType: AuthFlowType = AuthClient.Configuration.defaultFlowType,
    redirectToURL: URL? = nil,
    localStorage: any AuthLocalStorage,
    logger: (any SupabaseLogger)? = nil,
    encoder: JSONEncoder = AuthClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = AuthClient.Configuration.jsonDecoder,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) }
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        headers: headers,
        flowType: flowType,
        redirectToURL: redirectToURL,
        localStorage: localStorage,
        logger: logger,
        encoder: encoder,
        decoder: decoder,
        fetch: fetch
      )
    )
  }
}
