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

  /// Selects the columns declared by a selection type.
  ///
  /// ```swift
  /// let rows = try await client.from(Todo.self).select(TodoSummary.self).execute().value
  /// ```
  ///
  /// The `where` clause is what makes a declared selection safe to pass around: a selection names
  /// the relation it was declared against, so handing it to a different relation is *no such
  /// overload* rather than a request PostgREST rejects.
  ///
  /// - Parameter selection: A type declaring the columns to fetch, normally annotated with
  ///   `@SelectionOf` from the `PostgrestMacros` module.
  /// - Returns: A ``PostgrestTypedQuery`` decoding into `[S]`.
  public func select<S: PostgrestSelection>(
    _ selection: S.Type
  ) -> PostgrestTypedQuery<R, [S], PostgrestFilterPhase> where S.Source == R {
    PostgrestTypedQuery(builder: builder.select(S.selectString))
  }
}
