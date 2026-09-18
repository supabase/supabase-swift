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
  /// - Parameter schema: The schema type to query.
  /// - Returns: A ``PostgrestSchemaScope`` for that schema.
  public func schema<S: PostgrestSchema>(_ schema: S.Type) -> PostgrestSchemaScope<S> {
    PostgrestSchemaScope(client: self.schema(S.name))
  }
}

/// A client scoped to one schema, obtained by passing a schema type to ``PostgrestClient``'s
/// `schema(_:)`.
///
/// The `Schema` parameter is a compile-time-only marker: it carries no data and exists so that
/// `from(_:)` can require the relation to name the same schema.
public struct PostgrestSchemaScope<Schema: PostgrestSchema>: Sendable {
  let client: PostgrestClient

  /// Returns a typed source for a relation that belongs to this schema.
  ///
  /// - Parameter relation: The relation type to query.
  /// - Returns: A ``PostgrestTypedSource`` for that relation.
  public func from<R: PostgrestRelation>(_ relation: R.Type) -> PostgrestTypedSource<R>
  where R.Schema == Schema {
    PostgrestTypedSource(builder: client.from(R.relationName))
  }

  /// Returns an untyped query builder for a relation named as a string.
  ///
  /// - Parameter relation: The relation's name.
  /// - Returns: A ``PostgrestQueryBuilder`` for that relation.
  public func from(_ relation: String) -> PostgrestQueryBuilder {
    client.from(relation)
  }
}
