//
//  PostgrestTypedSource.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

extension PostgrestClient {
  /// Returns a typed source for a relation, so column and relation names are checked by the
  /// compiler instead of being spelled as strings.
  ///
  /// ```swift
  /// let todos = try await client.from(Todo.self).select().execute().value
  /// ```
  ///
  /// - Parameter relation: The relation type to query.
  /// - Returns: A ``PostgrestTypedSource`` for that relation.
  public func from<R: PostgrestRelation>(_ relation: R.Type) -> PostgrestTypedSource<R> {
    PostgrestTypedSource(builder: from(R.relationName))
  }
}

/// A relation that has been chosen but for which no operation has been picked yet.
///
/// It is called a *source* rather than a table because it may be a view, and rather than a query
/// because no operation has been chosen. Obtain one by passing a relation type to
/// `PostgrestClient.from(_:)`.
///
/// Like the builder it wraps, this is a value type: chaining off the same source twice gives two
/// independent requests.
public struct PostgrestTypedSource<R: PostgrestRelation>: Sendable {
  let builder: PostgrestQueryBuilder

  /// Selects every column of the relation.
  ///
  /// - Returns: A ``PostgrestTypedQuery`` decoding into `[R]`.
  public func select() -> PostgrestTypedQuery<R, [R], PostgrestFilterPhase> {
    PostgrestTypedQuery(builder: builder.select(R.selectString))
  }
}
