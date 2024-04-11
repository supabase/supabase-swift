//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 16/01/24.
//

import Foundation

extension PostgrestClient.Configuration {
  /// Initializes a new configuration for the PostgREST client.
  /// - Parameters:
  ///   - url: The URL of the PostgREST server.
  ///   - schema: The schema to use.
  ///   - headers: The headers to include in requests.
  ///   - fetch: The fetch handler to use for requests.
  ///   - encoder: The JSONEncoder to use for encoding.
  ///   - decoder: The JSONDecoder to use for decoding.
  @available(
    *,
    deprecated,
    message: "Replace usages of this initializer with new init(url:schema:headers:logger:fetch:encoder:decoder:)"
  )
  public init(
    url: URL,
    schema: String? = nil,
    headers: [String: String] = [:],
    fetch: @escaping PostgrestClient.FetchHandler = { try await URLSession.shared.data(for: $0) },
    encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
  ) {
    self.init(
      url: url,
      schema: schema,
      headers: headers,
      logger: nil,
      fetch: fetch,
      encoder: encoder,
      decoder: decoder
    )
  }
}

extension PostgrestClient {
  /// Creates a PostgREST client with the specified parameters.
  /// - Parameters:
  ///   - url: The URL of the PostgREST server.
  ///   - schema: The schema to use.
  ///   - headers: The headers to include in requests.
  ///   - session: The URLSession to use for requests.
  ///   - encoder: The JSONEncoder to use for encoding.
  ///   - decoder: The JSONDecoder to use for decoding.
  @available(
    *,
    deprecated,
    message: "Replace usages of this initializer with new init(url:schema:headers:logger:fetch:encoder:decoder:)"
  )
  public convenience init(
    url: URL,
    schema: String? = nil,
    headers: [String: String] = [:],
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
  ) {
    self.init(
      url: url,
      schema: schema,
      headers: headers,
      logger: nil,
      fetch: fetch,
      encoder: encoder,
      decoder: decoder
    )
  }
}
