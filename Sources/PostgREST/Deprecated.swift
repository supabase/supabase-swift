//
//  Deprecated.swift
//
//
//  Created by Guilherme Souza on 16/01/24.
//

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

extension PostgrestQueryBuilder {
  @available(
    *,
    deprecated,
    renamed: "insert(_:count:)",
    message: "If you want to return the inserted value, append a select() call to the query."
  )
  public func insert(
    _ values: some Encodable & Sendable,
    returning: PostgrestReturningOptions?,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try mutableState.withValue {
      $0.request.method = .post
      var prefersHeaders: [String] = []
      if let returning {
        prefersHeaders.append("return=\(returning.rawValue)")
      }
      $0.request.body = try configuration.encoder.encode(values)
      if let count {
        prefersHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers["Prefer"] {
        prefersHeaders.insert(prefer, at: 0)
      }
      if !prefersHeaders.isEmpty {
        $0.request.headers["Prefer"] = prefersHeaders.joined(separator: ",")
      }
      if let body = $0.request.body,
         let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]]
      {
        let allKeys = jsonObject.flatMap(\.keys)
        let uniqueKeys = Set(allKeys).sorted()
        $0.request.query.append(URLQueryItem(
          name: "columns",
          value: uniqueKeys.joined(separator: ",")
        ))
      }
    }

    return PostgrestFilterBuilder(self)
  }

  @available(
    *,
    deprecated,
    renamed: "upsert(_:onConflict:count:ignoreDuplicates:)",
    message: "If you want to return the upserted value, append a select() call to the query."
  )
  public func upsert(
    _ values: some Encodable & Sendable,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false
  ) throws -> PostgrestFilterBuilder {
    try mutableState.withValue {
      $0.request.method = .post
      var prefersHeaders = [
        "resolution=\(ignoreDuplicates ? "ignore" : "merge")-duplicates",
        "return=\(returning.rawValue)",
      ]
      if let onConflict {
        $0.request.query.append(URLQueryItem(name: "on_conflict", value: onConflict))
      }
      $0.request.body = try configuration.encoder.encode(values)
      if let count {
        prefersHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers["Prefer"] {
        prefersHeaders.insert(prefer, at: 0)
      }
      if !prefersHeaders.isEmpty {
        $0.request.headers["Prefer"] = prefersHeaders.joined(separator: ",")
      }

      if let body = $0.request.body,
         let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]]
      {
        let allKeys = jsonObject.flatMap(\.keys)
        let uniqueKeys = Set(allKeys).sorted()
        $0.request.query.append(URLQueryItem(
          name: "columns",
          value: uniqueKeys.joined(separator: ",")
        ))
      }
    }
    return PostgrestFilterBuilder(self)
  }

  @available(
    *,
    deprecated,
    renamed: "update(_:count:)",
    message: "If you want to return the updated value, append a select() call to the query."
  )
  public func update(
    _ values: some Encodable & Sendable,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try mutableState.withValue {
      $0.request.method = .patch
      var preferHeaders = ["return=\(returning.rawValue)"]
      $0.request.body = try configuration.encoder.encode(values)
      if let count {
        preferHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers["Prefer"] {
        preferHeaders.insert(prefer, at: 0)
      }
      if !preferHeaders.isEmpty {
        $0.request.headers["Prefer"] = preferHeaders.joined(separator: ",")
      }
    }
    return PostgrestFilterBuilder(self)
  }

  @available(
    *,
    deprecated,
    renamed: "delete(count:)",
    message: "If you want to return the deleted values, append a select() call to the query."
  )
  public func delete(
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.method = .delete
      var preferHeaders = ["return=\(returning.rawValue)"]
      if let count {
        preferHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers["Prefer"] {
        preferHeaders.insert(prefer, at: 0)
      }
      if !preferHeaders.isEmpty {
        $0.request.headers["Prefer"] = preferHeaders.joined(separator: ",")
      }
    }
    return PostgrestFilterBuilder(self)
  }
}
