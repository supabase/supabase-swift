//
//  PostgrestTypedQuery.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

/// A read request against a relation, with filters and modifiers applied by key path.
///
/// `Phase` mirrors the phase parameter on ``PostgrestRequestBuilder``: it is a compile-time-only
/// marker that decides which methods are available. Filters need a
/// ``PostgrestFilterablePhase``, `order`/`limit` need a ``PostgrestTransformablePhase``, and
/// ``execute()`` needs a ``PostgrestExecutablePhase``. You never spell it out — it is inferred
/// from the chain.
///
/// Like the builder it wraps, this is a value type: chaining off the same query twice gives two
/// independent requests.
public struct PostgrestTypedQuery<
  R: PostgrestRelation,
  Output: Decodable & Sendable,
  Phase
>: Sendable {
  /// The underlying string-based builder.
  public let builder: PostgrestRequestBuilder<Phase>

  /// Wraps a builder in the typed query surface.
  ///
  /// - Parameter builder: The builder to wrap.
  public init(builder: PostgrestRequestBuilder<Phase>) {
    self.builder = builder
  }
}

extension PostgrestTypedQuery where Phase: PostgrestExecutablePhase {
  /// Sends the request and decodes the response.
  ///
  /// - Returns: A ``PostgrestResponse`` whose `value` is the decoded `Output`.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<Output> {
    try await builder.execute()
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
    try await builder.execute(options: FetchOptions(count: count))
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
    let response = try await builder.execute(options: FetchOptions(head: true, count: option))
    guard let count = response.count else {
      throw PostgrestError(
        message: """
          The response carries no row count. Expected a `Content-Range` header for \
          `Prefer: count=\(option.rawValue)`.
          """
      )
    }
    return count
  }
}
