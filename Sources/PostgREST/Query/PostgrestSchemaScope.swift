//
//  PostgrestSchemaScope.swift
//  PostgREST
//
//  Created by Ranbir Singh on 18/09/26.
//

extension PostgrestClient {
  /// Returns a scope that only queries relations declared to live in the given schema.
  ///
  /// ```swift
  /// try await client.schema(PrivateSchema.self).from(Secret.self).select().execute().value
  /// ```
  ///
  /// Passing a relation from another schema is *no such overload* rather than a request the
  /// database rejects. Use ``PostgrestClient/schema(_:)->PostgrestClient`` with a string when
  /// the schema is not known at compile time.
  ///
  /// - Precondition: This client has no schema set. Choosing a second schema is a programmer
  ///   error.
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  ///
  /// - Parameter schema: The schema type to query.
  /// - Returns: A ``_PostgrestSchemaScope`` for that schema.
  @_spi(Experimental)
  public func schema<S: _PostgrestSchema>(_ schema: S.Type) -> _PostgrestSchemaScope<S> {
    precondition(
      configuration.schema == nil,
      """
      schema(_:) must be called on a client with no schema set, got one scoped to \
      "\(configuration.schema ?? "")".
      """
    )
    return _PostgrestSchemaScope(client: self.schema(S.name))
  }

  // See the unavailable `from(_:_:)` twin.
  @available(
    *, unavailable,
    message:
      "The typed query API is experimental. Opt in with `@_spi(Experimental) import Supabase`."
  )
  public func schema<S: _PostgrestSchema>(_ schema: S.Type, _: Void = ()) -> _PostgrestSchemaScope<
    S
  > {
    fatalError()
  }
}

/// A client scoped to one schema, returned by
/// ``PostgrestClient/schema(_:)->_PostgrestSchemaScope<S>``.
///
/// The `Schema` parameter is a compile-time-only marker: it carries no data and exists so that
/// ``from(_:)`` can require the relation to name the same schema.
public struct _PostgrestSchemaScope<Schema: _PostgrestSchema>: Sendable {
  let client: PostgrestClient

  /// Returns a typed source for a relation that belongs to this schema.
  ///
  /// - Parameter relation: The relation type to query.
  /// - Returns: A ``_PostgrestSource`` for that relation.
  public func from<R: _PostgrestRelation>(_ relation: R.Type) -> _PostgrestSource<R>
  where R.Schema == Schema {
    _PostgrestSource(client: client)
  }
}
