//
//  PostgrestQuery.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import HTTPTypes

/// A read request against a relation, with filters and modifiers applied through the relation's
/// columns.
///
/// `Output` is what ``execute()`` decodes: `[R]` or `[S]` after a select, `Element` after
/// ``single()``, and `Element?` after ``maybeSingle()``. You never spell it out — it is inferred
/// from the chain.
///
/// `where`, `order`, `limit` and `range` return the same type, so they can be applied in any
/// order.
///
/// This is a value type: chaining off the same query twice gives two independent requests.
///
/// > Warning: Part of the typed query API, which is alpha. Its shape may change in a minor release.
public struct PostgrestQuery<R: PostgrestRelation, Output: Decodable & Sendable>: Sendable {
  let client: PostgrestClient

  /// The request this query sends.
  public var request: PostgrestRequest

  /// Turns a 2xx body into `Output`. Chosen by the method that produced this query, so
  /// ``maybeSingle()`` can decode an array and enforce at most one row.
  let decode: @Sendable (Data) throws -> Output

  init(
    client: PostgrestClient,
    request: PostgrestRequest,
    decode: @escaping @Sendable (Data) throws -> Output = {
      try Self.decoder.decode(Output.self, from: $0)
    }
  ) {
    self.client = client
    self.request = request
    self.decode = decode
  }
}

extension PostgrestQuery: PostgrestFilterableRequest {
  public typealias Relation = R
}

extension PostgrestQuery {
  /// Sends the request and decodes the response.
  ///
  /// - Returns: A ``PostgrestResponse`` whose `value` is the decoded `Output`.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<Output> {
    try await send(request)
  }

  /// Sends the request and decodes the response, asking the server for a total row count as well.
  ///
  /// One round trip returns both the page and the total, which is what a paginated view needs:
  ///
  /// ```swift
  /// let page = try await client.from(Todo.self).select()
  ///   .where { $0.isDone.eq(false) }
  ///   .limit(20)
  ///   .execute(count: .exact)
  ///
  /// page.value  // [Todo], at most 20 of them
  /// page.count  // every row matching the filter, ignoring the limit
  /// ```
  ///
  /// The count respects the filters but ignores `limit`. Use ``count(_:)`` when the rows are not
  /// wanted at all.
  ///
  /// - Parameter count: The counting algorithm. See ``CountOption`` for the accuracy/speed
  ///   trade-off.
  /// - Returns: A ``PostgrestResponse`` whose `value` is the decoded `Output` and whose
  ///   ``PostgrestResponse/count`` is the total.
  @discardableResult
  public func execute(count: CountOption) async throws -> PostgrestResponse<Output> {
    var request = request
    request.setPreference("count=\(count.rawValue)")
    return try await send(request)
  }

  /// Asks the server how many rows match, without transferring any of them.
  ///
  /// This is a HEAD request: PostgREST reports the total in the `Content-Range` header and sends
  /// no body, so counting a large table costs no rows.
  ///
  /// ```swift
  /// let remaining = try await client.from(Todo.self).select()
  ///   .where { $0.isDone.eq(false) }
  ///   .count(.exact)
  /// ```
  ///
  /// Use ``execute(count:)`` instead when the rows are wanted too — asking for both separately
  /// is two round trips for what the server returns in one.
  ///
  /// - Parameter option: The counting algorithm. See ``CountOption`` for the accuracy/speed
  ///   trade-off.
  /// - Returns: The number of rows matching the filters.
  /// - Throws: ``PostgrestError`` if the response carries no count, or any error thrown by the
  ///   request itself.
  public func count(_ option: CountOption) async throws -> Int {
    var request = request
    request.method = .head
    request.setPreference("count=\(option.rawValue)")
    let response = try await request.execute(on: client) { _ in () }
    guard let count = response.count else {
      throw PostgrestError(
        kind: .decoding,
        message: """
          The response carries no row count. Expected a `Content-Range` header for \
          `Prefer: count=\(option.rawValue)`.
          """
      )
    }
    return count
  }

  private func send(_ request: PostgrestRequest) async throws -> PostgrestResponse<Output> {
    try await request.execute(on: client, decode: decode)
  }

  /// The typed API never uses the client's configured decoder. Column names come from each row
  /// type's `CodingKeys`, and a key strategy on a shared decoder would silently make them wrong.
  static var decoder: JSONDecoder { PostgrestClient.Configuration.jsonDecoder }

  private static var objectMediaType: String { "application/vnd.pgrst.object+json" }
}

extension PostgrestQuery {
  /// Returns exactly one row, decoded as `Element` rather than `[Element]`.
  ///
  /// ```swift
  /// let todo = try await client.from(Todo.self).select()
  ///   .where { $0.id.eq(1) }
  ///   .single()
  ///   .execute()
  ///   .value  // Todo
  /// ```
  ///
  /// ``execute()`` throws a ``PostgrestError`` with code `PGRST116` when the query matches no row
  /// or more than one. Use ``maybeSingle()`` when no row is a valid answer.
  ///
  /// - Returns: A ``PostgrestQuery`` decoding into a single `Element`.
  public func single<Element>() -> PostgrestQuery<R, Element> where Output == [Element] {
    var query = PostgrestQuery<R, Element>(client: client, request: request)
    query.request.headerFields[.accept] = Self.objectMediaType
    return query
  }

  /// Returns at most one row, decoded as `Element?`.
  ///
  /// ```swift
  /// let todo = try await client.from(Todo.self).select()
  ///   .where { $0.id.eq(1) }
  ///   .maybeSingle()
  ///   .execute()
  ///   .value  // Todo?
  /// ```
  ///
  /// No row decodes as `nil`. More than one row throws a ``PostgrestError`` of kind
  /// ``PostgrestError/Kind-swift.struct/decoding``, because it means the filter did not narrow the
  /// query to the one row it was meant to find.
  ///
  /// Unlike ``single()``, the request asks for the usual JSON array and the row count is checked
  /// here, so PostgREST's `PGRST116` never reaches you.
  ///
  /// > Important: The count is checked after the response arrives. On a write, such as
  /// > `delete().returning().maybeSingle()`, every matched row has already been written by then.
  ///
  /// - Returns: A ``PostgrestQuery`` decoding into `Element?`.
  public func maybeSingle<Element>() -> PostgrestQuery<R, Element?> where Output == [Element] {
    let query = PostgrestQuery<R, Element?>(client: client, request: request) {
      let rows = try Self.decoder.decode([Element].self, from: $0)
      guard rows.count <= 1 else {
        throw PostgrestError(
          kind: .decoding,
          message: "maybeSingle() expected at most one row, but the response has \(rows.count)."
        )
      }
      return rows.first
    }
    return query
  }

  /// Leaves `null` fields out of the response body.
  ///
  /// Only JSON responses have nulls to strip, so this is not available after ``csv()``,
  /// ``geojson()`` or ``explain(analyze:verbose:settings:buffers:wal:format:)``.
  ///
  /// - Returns: A new query that asks PostgREST for `nulls=stripped`.
  public func stripNulls() -> Self {
    var query = self
    query.request.stripsNulls = true
    return query
  }

  /// Returns the rows as CSV.
  ///
  /// > Note: A ``stripNulls()`` applied before this has no effect, since CSV is not JSON.
  ///
  /// - Returns: A ``PostgrestRawQuery`` whose response is the CSV text.
  public func csv() -> PostgrestRawQuery {
    rawQuery(accept: "text/csv")
  }

  /// Returns the rows as a GeoJSON `FeatureCollection`.
  ///
  /// The relation needs a PostGIS geometry column for PostgREST to build one.
  ///
  /// > Note: A ``stripNulls()`` applied before this has no effect.
  ///
  /// - Returns: A ``PostgrestRawQuery`` whose response is the GeoJSON text.
  public func geojson() -> PostgrestRawQuery {
    rawQuery(accept: "application/geo+json")
  }

  /// Returns the Postgres execution plan for the query instead of its rows.
  ///
  /// The plan is only available when the PostgREST `db_plan_enabled` setting is on, which is
  /// not the default.
  ///
  /// > Note: A ``stripNulls()`` applied before this has no effect.
  ///
  /// - Parameters:
  ///   - analyze: Runs the query and reports actual timings, not only estimates.
  ///   - verbose: Includes the output columns of each plan node.
  ///   - settings: Includes the configuration parameters that affect planning.
  ///   - buffers: Includes buffer usage. Needs `analyze`.
  ///   - wal: Includes write-ahead log record generation. Needs `analyze`.
  ///   - format: The plan format. Defaults to ``ExplainFormat/text``.
  /// - Returns: A ``PostgrestRawQuery`` whose response is the plan.
  public func explain(
    analyze: Bool = false,
    verbose: Bool = false,
    settings: Bool = false,
    buffers: Bool = false,
    wal: Bool = false,
    format: ExplainFormat = .text
  ) -> PostgrestRawQuery {
    let options = [
      analyze ? "analyze" : nil,
      verbose ? "verbose" : nil,
      settings ? "settings" : nil,
      buffers ? "buffers" : nil,
      wal ? "wal" : nil,
    ]
    .compactMap { $0 }
    .joined(separator: "|")
    let planned = request.headerFields[.accept] ?? "application/json"
    return rawQuery(
      accept:
        "application/vnd.pgrst.plan+\(format.rawValue); for=\"\(planned)\"; options=\(options);"
    )
  }

  private func rawQuery(accept: String) -> PostgrestRawQuery {
    var request = request
    request.headerFields[.accept] = accept
    return PostgrestRawQuery(client: client, request: request)
  }
}
