//
//  _PostgrestFunction.swift
//  PostgREST
//
//  Created by Guilherme Souza on 07/10/26.
//

import Foundation
import Helpers
import IssueReporting

/// A database function and its arguments, called through `rpc/<name>`.
///
/// `@Function` generates the conformance; the properties are the arguments and encode as the
/// request's JSON object. A function is not a relation: it takes arguments, so a value of it is
/// what `rpc(_:)` wants and `from(_:)` does not accept.
///
/// ```swift
/// @Function("search_todos")
/// struct SearchTodos {
///   typealias Result = [Todo]
///   var keyword: String
/// }
///
/// let hits = try await client.rpc(SearchTodos(keyword: "groceries")).execute().value
/// ```
///
/// > Warning: Part of the typed query API, which is alpha. Its shape may change in a minor release.
public protocol _PostgrestFunction: Encodable, Sendable {
  /// The function's name as PostgREST addresses it, without the `rpc/` prefix.
  static var functionName: String { get }

  /// The schema the function lives in. Defaults to ``_PublicSchema``.
  associatedtype Schema: _PostgrestSchema = _PublicSchema

  /// What the function returns, decoded from the response. Defaults to `Void` for a function that
  /// returns nothing. Spell a set-returning function as an array of a relation, `[Todo]`, to filter
  /// and order its rows.
  associatedtype Result: Sendable = Void
}

/// A call to a ``_PostgrestFunction``, before it is sent.
///
/// Built by ``PostgrestClient/rpc(_:)``. A set-returning function flows into ``_PostgrestQuery``
/// through ``where(_:)``, ``order(_:)`` or ``rows()``, which is where filters, ordering and paging
/// live; any other result executes directly.
///
/// > Warning: Part of the typed query API, which is alpha. Its shape may change in a minor release.
public struct _PostgrestFunctionQuery<F: _PostgrestFunction>: Sendable {
  let client: PostgrestClient

  public var request: _PostgrestRequest

  /// Sends the call as a `GET`, with the arguments in the query string rather than the body.
  ///
  /// PostgREST then runs the function in a read-only transaction, which lets it be served by a
  /// read replica and makes a `count` possible. Use it for a function that only reads.
  ///
  /// The arguments are the JSON object the function encodes to, rendered one query item per key
  /// exactly as the untyped `rpc(_:params:get:)` renders them.
  public func readOnly() -> Self {
    var copy = self
    guard
      let body = request.body,
      let parameters = try? JSONDecoder().decode([String: JSONValue].self, from: body)
    else {
      // `@Function` always encodes an object. A hand-written conformance that does not cannot be
      // sent as query items, so the call stays a `POST` rather than losing its arguments.
      reportIssue(
        "\(F.self) does not encode as a JSON object, so readOnly() cannot render its arguments.")
      return copy
    }
    copy.request.method = .get
    copy.request.body = nil
    copy.request.leadingQuery = parameters.sorted { $0.key < $1.key }.map { key, value in
      URLQueryItem(name: key, value: client.queryValue(for: value))
    }
    return copy
  }
}

extension _PostgrestFunctionQuery where F.Result: Decodable {
  /// Sends the call and decodes its result.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<F.Result> {
    try await request.execute(on: client) {
      try PostgrestClient.Configuration.jsonDecoder.decode(F.Result.self, from: $0)
    }
  }
}

extension _PostgrestFunctionQuery where F.Result == Void {
  /// Sends the call to a function that returns nothing.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<Void> {
    try await request.execute(on: client) { _ in () }
  }
}

extension _PostgrestFunctionQuery {
  /// The rows of a set-returning function as a query, so they can be filtered, ordered, paged
  /// and counted like a relation's.
  public func rows<Row: _PostgrestRelation>() -> _PostgrestQuery<Row, [Row]>
  where F.Result == [Row] {
    _PostgrestQuery(client: client, request: request)
  }

  /// Keeps only the returned rows matching the filter. See ``_PostgrestFilterableRequest/where(_:)``.
  public func `where`<Row: _PostgrestRelation>(
    _ build: (Row.Columns) -> _PostgrestFilter<Row>
  ) -> _PostgrestQuery<Row, [Row]> where F.Result == [Row] {
    rows().where(build)
  }

  /// Orders the returned rows, like `_PostgrestQuery.order(_:)`.
  public func order<Row: _PostgrestRelation>(
    _ build: (Row.Columns) -> _PostgrestOrdering<Row>
  ) -> _PostgrestQuery<Row, [Row]> where F.Result == [Row] {
    rows().order(build)
  }
}

extension PostgrestClient {
  /// Calls a database function with typed arguments.
  ///
  /// The call is a `POST` to `rpc/<name>` carrying `function` as its JSON body. Chain
  /// ``_PostgrestFunctionQuery/readOnly()`` to send it as a `GET` instead.
  ///
  /// ```swift
  /// let hits = try await client.rpc(SearchTodos(keyword: "groceries")).execute().value
  /// ```
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  ///
  /// - Throws: The encoding error if `function` cannot be encoded.
  @_spi(Experimental)
  public func rpc<F: _PostgrestFunction>(_ function: F) throws -> _PostgrestFunctionQuery<F> {
    let client =
      configuration.schema == nil && F.Schema.name != _PublicSchema.name
      ? schema(F.Schema.name)
      : self
    var request = client.makeRequest("rpc/\(F.functionName)", method: .post)
    request.body = try PostgrestClient.Configuration.jsonEncoder.encode(function)
    return _PostgrestFunctionQuery(client: client, request: request)
  }

  // See the unavailable `from(_:_:)` twin: it names the missing SPI import.
  @available(
    *, unavailable,
    message:
      "The typed query API is experimental. Opt in with `@_spi(Experimental) import Supabase`."
  )
  public func rpc<F: _PostgrestFunction>(_ function: F, _: Void = ()) throws
    -> _PostgrestFunctionQuery<F>
  {
    fatalError()
  }
}
