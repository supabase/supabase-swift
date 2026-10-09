//
//  PostgrestSource.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation

extension PostgrestClient {
  /// Returns a typed source for a relation, so column and relation names are checked by the
  /// compiler instead of being spelled as strings.
  ///
  /// ```swift
  /// let todos = try await client.from(Todo.self).select().execute().value
  /// ```
  ///
  /// A relation that names a schema other than ``_PublicSchema`` is queried in that schema, unless
  /// this client was already scoped to one, in which case the client's schema wins.
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  ///
  /// - Parameter relation: The relation type to query.
  /// - Returns: A ``_PostgrestSource`` for that relation.
  @_spi(Experimental)
  public func from<R: _PostgrestRelation>(_ relation: R.Type) -> _PostgrestSource<R> {
    let client =
      configuration.schema == nil && R.schema != _PublicSchema.name
      ? schema(R.schema)
      : self
    return _PostgrestSource(client: client)
  }

  // Without the SPI import the solver blames the argument instead: "cannot convert value of type
  // 'Todo.Type' to expected argument type 'String'". This visible twin catches the call and names
  // the fix. The extra `Void` parameter only avoids a redeclaration; with the SPI import, the
  // available overload ranks above it.
  @available(
    *, unavailable,
    message:
      "The typed query API is experimental. Opt in with `@_spi(Experimental) import Supabase`."
  )
  public func from<R: _PostgrestRelation>(_ relation: R.Type, _: Void = ()) -> _PostgrestSource<R> {
    fatalError()
  }
}

/// A relation that has been chosen but for which no operation has been picked yet.
///
/// It is called a *source* rather than a table because it may be a view, and rather than a query
/// because no operation has been chosen. Obtain one by passing a relation type to
/// `PostgrestClient.from(_:)`.
///
/// This is a value type: chaining off the same source twice gives two independent requests.
public struct _PostgrestSource<R: _PostgrestRelation>: Sendable {
  let client: PostgrestClient

  var request: _PostgrestRequest { client.makeRequest(R.relationName) }

  /// Selects every column of the relation.
  ///
  /// - Returns: A ``_PostgrestQuery`` decoding into `[R]`.
  public func select() -> _PostgrestQuery<R, [R]> {
    select(columns: R.selectString)
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
  /// - Returns: A ``_PostgrestQuery`` decoding into `[S]`.
  public func select<S: _PostgrestSelection>(
    _ selection: S.Type
  ) -> _PostgrestQuery<R, [S]> where S.Source == R {
    select(columns: S.selectString)
  }

  private func select<Output>(columns: String) -> _PostgrestQuery<R, Output> {
    var request = request
    request.query.append(URLQueryItem(name: "select", value: columns))
    return _PostgrestQuery(client: client, request: request)
  }
}
