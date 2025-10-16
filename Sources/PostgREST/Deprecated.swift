//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 16/01/24.
//

import Alamofire
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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
    message:
      "Replace usages of this initializer with new init(url:schema:headers:logger:alamofireSession:encoder:decoder:)"
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
      alamofireSession: .default,
      encoder: encoder,
      decoder: decoder
    )
  }

  /// Initializes a new configuration for the PostgREST client.
  /// - Parameters:
  ///   - url: The URL of the PostgREST server.
  ///   - schema: The schema to use.
  ///   - headers: The headers to include in requests.
  ///   - logger: The logger to use.
  ///   - fetch: The fetch handler to use for requests.
  ///   - encoder: The JSONEncoder to use for encoding.
  ///   - decoder: The JSONDecoder to use for decoding.
  @available(
    *,
    deprecated,
    message:
      "Use init(url:schema:headers:logger:alamofireSession:encoder:decoder:) instead. This initializer will be removed in a future version."
  )
  @_disfavoredOverload
  public init(
    url: URL,
    schema: String? = nil,
    headers: [String: String] = [:],
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping PostgrestClient.FetchHandler,
    encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
  ) {
    self.init(
      url: url,
      schema: schema,
      headers: headers,
      logger: logger,
      fetch: fetch,
      alamofireSession: .default,
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
  ///   - fetch: The fetch handler to use for requests.
  ///   - encoder: The JSONEncoder to use for encoding.
  ///   - decoder: The JSONDecoder to use for decoding.
  @available(
    *,
    deprecated,
    message:
      "Replace usages of this initializer with new init(url:schema:headers:logger:alamofireSession:encoder:decoder:)"
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
      configuration: Configuration(
        url: url,
        schema: schema,
        headers: headers,
        logger: nil,
        fetch: fetch,
        encoder: encoder,
        decoder: decoder
      )
    )
  }

  /// Creates a PostgREST client with the specified parameters.
  /// - Parameters:
  ///   - url: The URL of the PostgREST server.
  ///   - schema: The schema to use.
  ///   - headers: The headers to include in requests.
  ///   - logger: The logger to use.
  ///   - fetch: The fetch handler to use for requests.
  ///   - encoder: The JSONEncoder to use for encoding.
  ///   - decoder: The JSONDecoder to use for decoding.
  @available(
    *,
    deprecated,
    message:
      "Use init(url:schema:headers:logger:alamofireSession:encoder:decoder:) instead. This initializer will be removed in a future version."
  )
  @_disfavoredOverload
  public convenience init(
    url: URL,
    schema: String? = nil,
    headers: [String: String] = [:],
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler,
    encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        schema: schema,
        headers: headers,
        logger: logger,
        fetch: fetch,
        encoder: encoder,
        decoder: decoder
      )
    )
  }
}

extension PostgrestFilterBuilder {

  @available(*, deprecated, renamed: "like(_:pattern:)")
  public func like(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    like(column, pattern: value)
  }

  @available(*, deprecated, renamed: "in(_:values:)")
  public func `in`(
    _ column: String,
    value: [any PostgrestFilterValue]
  ) -> PostgrestFilterBuilder {
    `in`(column, values: value)
  }

  @available(*, deprecated, message: "Use textSearch(_:query:config:type) with .plain type.")
  public func plfts(
    _ column: String,
    query: any PostgrestFilterValue,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    textSearch(column, query: query, config: config, type: .plain)
  }

  @available(*, deprecated, message: "Use textSearch(_:query:config:type) with .phrase type.")
  public func phfts(
    _ column: String,
    query: any PostgrestFilterValue,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    textSearch(column, query: query, config: config, type: .phrase)
  }

  @available(*, deprecated, message: "Use textSearch(_:query:config:type) with .websearch type.")
  public func wfts(
    _ column: String,
    query: any PostgrestFilterValue,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    textSearch(column, query: query, config: config, type: .websearch)
  }

  @available(*, deprecated, renamed: "ilike(_:pattern:)")
  public func ilike(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    ilike(column, pattern: value)
  }
}

@available(
  *,
  deprecated,
  renamed: "PostgrestFilterValue"
)
public typealias URLQueryRepresentable = PostgrestFilterValue
