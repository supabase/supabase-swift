//
//  PostgrestRpc.swift
//  PostgREST
//
//  Created by Lukas Klingsbo on 15/10/26.
//

import Foundation
import Helpers

extension PostgrestClient {
  /// Calls Postgres functions with typed arguments and results.
  ///
  /// The schema generator adds one method per function to ``_PostgrestRpc``, so a call reads
  /// like a Swift call:
  ///
  /// ```swift
  /// let books = try await client.rpc.searchBooks(query: "dune")
  ///   .where { $0.price.lt(20) }
  ///   .execute()
  ///   .value
  /// ```
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  @_spi(Experimental)
  public var rpc: _PostgrestRpc {
    _PostgrestRpc(client: self)
  }
}

/// The entry points for calling a Postgres function, returned by ``PostgrestClient/rpc``.
///
/// Generated code extends this type with one method per function. The methods here are what those
/// call, and what a hand-written call uses when nothing is generated.
///
/// A function in a schema other than ``_PublicSchema`` is called in that schema, unless the client
/// was already scoped to one, in which case the client's schema wins.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public struct _PostgrestRpc: Sendable {
  let client: PostgrestClient

  /// Calls a function that returns rows of a relation, or of a `RETURNS TABLE` result.
  ///
  /// The result filters, sorts and pages through the row type's columns, the same way a query of
  /// the relation does.
  ///
  /// - Parameters:
  ///   - function: The function's name.
  ///   - arguments: The function's arguments, by Postgres parameter name.
  ///   - schema: The schema the function lives in.
  /// - Returns: A ``_PostgrestQuery`` decoding into `[R]`.
  /// - Throws: An encoding error if `arguments` cannot be serialized.
  public func rows<R: _PostgrestRelation>(
    _ function: String,
    arguments: _PostgrestArguments = [:],
    schema: any _PostgrestSchema.Type = _PublicSchema.self
  ) throws -> _PostgrestQuery<R, [R]> {
    let (client, request) = try call(function, arguments: arguments, schema: schema)
    return _PostgrestQuery(client: client, request: request)
  }

  /// Calls a function that returns one row, which is `nil` when the function finds none.
  ///
  /// PostgREST answers a function that returns a row type but finds no row with an object whose
  /// every field is `null`. That object decodes as `nil`, the same as a `null` body.
  ///
  /// - Parameters:
  ///   - function: The function's name.
  ///   - arguments: The function's arguments, by Postgres parameter name.
  ///   - schema: The schema the function lives in.
  /// - Returns: A ``_PostgrestFunctionCall`` decoding into `R?`.
  /// - Throws: An encoding error if `arguments` cannot be serialized.
  public func row<R: Decodable & Sendable>(
    _ function: String,
    arguments: _PostgrestArguments = [:],
    schema: any _PostgrestSchema.Type = _PublicSchema.self
  ) throws -> _PostgrestFunctionCall<R?> {
    let (client, request) = try call(function, arguments: arguments, schema: schema)
    return _PostgrestFunctionCall(client: client, request: request) { data in
      switch try JSONValue.decoder.decode(JSONValue.self, from: data) {
      case .null:
        return nil
      case .object(let fields) where fields.values.allSatisfy({ $0 == .null }):
        return nil
      default:
        return try PostgrestClient.Configuration.jsonDecoder.decode(R.self, from: data)
      }
    }
  }

  /// Calls a function that returns a value: a scalar, an array, or a set of scalars.
  ///
  /// - Parameters:
  ///   - function: The function's name.
  ///   - arguments: The function's arguments, by Postgres parameter name.
  ///   - schema: The schema the function lives in.
  /// - Returns: A ``_PostgrestFunctionCall`` decoding into `T`.
  /// - Throws: An encoding error if `arguments` cannot be serialized.
  public func value<T: Decodable & Sendable>(
    _ function: String,
    arguments: _PostgrestArguments = [:],
    schema: any _PostgrestSchema.Type = _PublicSchema.self
  ) throws -> _PostgrestFunctionCall<T> {
    let (client, request) = try call(function, arguments: arguments, schema: schema)
    return _PostgrestFunctionCall(client: client, request: request) {
      try PostgrestClient.Configuration.jsonDecoder.decode(T.self, from: $0)
    }
  }

  /// Calls a function that returns `void`, ignoring the response body.
  ///
  /// - Parameters:
  ///   - function: The function's name.
  ///   - arguments: The function's arguments, by Postgres parameter name.
  ///   - schema: The schema the function lives in.
  /// - Returns: A ``_PostgrestFunctionCall`` that produces no value.
  /// - Throws: An encoding error if `arguments` cannot be serialized.
  public func perform(
    _ function: String,
    arguments: _PostgrestArguments = [:],
    schema: any _PostgrestSchema.Type = _PublicSchema.self
  ) throws -> _PostgrestFunctionCall<Void> {
    let (client, request) = try call(function, arguments: arguments, schema: schema)
    return _PostgrestFunctionCall(client: client, request: request) { _ in }
  }

  private func call(
    _ function: String,
    arguments: _PostgrestArguments,
    schema: any _PostgrestSchema.Type
  ) throws -> (PostgrestClient, _PostgrestRequest) {
    let client =
      client.configuration.schema == nil && schema.name != _PublicSchema.name
      ? client.schema(schema.name)
      : client
    var request = client.makeRequest("rpc/\(function)", method: .post)
    request.body = try arguments.encoded(with: PostgrestClient.Configuration.jsonEncoder)
    return (client, request)
  }
}

/// The arguments of a function call, by Postgres parameter name.
///
/// Written as a dictionary literal. A `nil` value leaves the argument out, so the function's
/// default applies:
///
/// ```swift
/// try client.rpc.rows("search_books", arguments: ["query": "dune", "max_price": maxPrice])
/// ```
///
/// A function whose sole parameter is an unnamed `json` or `jsonb` receives a whole body instead,
/// through ``init(_:)``.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public struct _PostgrestArguments: Sendable, ExpressibleByDictionaryLiteral {
  private enum Storage: Sendable {
    case named([(String, any Encodable & Sendable)])
    case body(any Encodable & Sendable)
  }

  private let storage: Storage

  public init(dictionaryLiteral elements: (String, (any Encodable & Sendable)?)...) {
    storage = .named(elements.compactMap { name, value in value.map { (name, $0) } })
  }

  /// Sends `body` as the whole request body.
  ///
  /// - Parameter body: The value a function with a sole unnamed `json` or `jsonb` parameter
  ///   receives.
  public init(_ body: some Encodable & Sendable) {
    storage = .body(body)
  }

  /// The request body, or `nil` when there are no named arguments.
  func encoded(with encoder: JSONEncoder) throws -> Data? {
    switch storage {
    case .named(let arguments) where arguments.isEmpty:
      return nil
    case .named(let arguments):
      return try encoder.encode(NamedArguments(arguments: arguments))
    case .body(let body):
      return try encoder.encode(PostgrestUpdateValue(body))
    }
  }

  private struct NamedArguments: Encodable {
    let arguments: [(String, any Encodable & Sendable)]

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: PostgrestUpdateColumnKey.self)
      for (name, value) in arguments {
        try container.encode(PostgrestUpdateValue(value), forKey: PostgrestUpdateColumnKey(name))
      }
    }
  }
}

/// A call of a Postgres function whose result is not rows to filter: one row, a value, or nothing.
///
/// Obtain one from ``_PostgrestRpc/row(_:arguments:schema:)``,
/// ``_PostgrestRpc/value(_:arguments:schema:)`` or ``_PostgrestRpc/perform(_:arguments:schema:)``.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public struct _PostgrestFunctionCall<Output: Sendable>: Sendable {
  let client: PostgrestClient
  let request: _PostgrestRequest
  let decode: @Sendable (Data) throws -> Output

  /// Sends the request and decodes the response.
  ///
  /// - Returns: A ``PostgrestResponse`` whose `value` is the decoded `Output`.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<Output> {
    try await request.execute(on: client, decode: decode)
  }
}
