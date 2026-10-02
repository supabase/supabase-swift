//
//  PostgrestTypedSource+Unavailable.swift
//  PostgREST
//
//  Created by Guilherme Souza on 02/10/26.
//

// Unconstrained, unavailable twins of every constrained member of `PostgrestTypedSource`, so a
// misuse such as `client.from(ReadOnly.self).delete()` names the real problem (SDK-1621).
//
// Without them the solver blames `from`: "cannot convert value of type 'ReadOnly.Type' to
// expected argument type 'String'". A failed requirement on a member of a constrained extension
// costs 10 in the solver's fix score, and passing a relation type to the legacy
// `from(_ table: String)` costs 2, so the legacy overload wins the diagnosis.
// `@_disfavoredOverload` on it changes nothing: it only ranks solutions that need no fix. A twin
// lets the typed path resolve with no fix at all, and the error becomes the twin's message.
//
// A writable call still picks the real member: an unavailable choice ranks below an available
// one. The typed mutation and selection tests would stop compiling if it did not. The diagnostic
// itself is a compile failure, which a Swift Testing test cannot assert.

extension PostgrestTypedSource {
  @available(
    *, unavailable,
    message: "delete() needs a PostgrestWritableRelation; this relation is read-only"
  )
  public func delete() -> Never {
    fatalError()
  }

  @_disfavoredOverload
  @available(
    *, unavailable,
    message: "insert(_:) takes the relation's Draft, which only a PostgrestWritableRelation has"
  )
  public func insert<T>(_ values: T) -> Never {
    fatalError()
  }

  // Closure form only: a `PostgrestUpdate<R>` cannot be built for a read-only `R`. The closure's
  // `$0` has nothing to infer from here, so the error is "cannot infer type of closure parameter"
  // rather than this message, but it lands on `update` instead of on `from`.
  @_disfavoredOverload
  @available(*, unavailable, message: "update(_:) needs a PostgrestWritableRelation")
  public func update<T>(_ build: (inout T) -> Void) -> Never {
    fatalError()
  }

  @_disfavoredOverload
  @available(
    *, unavailable,
    message:
      "upsert(_:) merges on the primary key, so it needs a PostgrestWritableRelation with a @PrimaryKey (PostgrestKeyedRelation); name a unique constraint with upsert(_:onConflict:) otherwise"
  )
  public func upsert<T>(
    _ values: T,
    resolution: PostgrestConflictResolution = .mergeDuplicates
  ) -> Never {
    fatalError()
  }

  @_disfavoredOverload
  @available(
    *, unavailable,
    message:
      "upsert(_:onConflict:) takes the relation's Draft, which only a PostgrestWritableRelation has, and key paths to its stored columns"
  )
  public func upsert<T>(
    _ values: T,
    onConflict column: PartialKeyPath<R.Columns>,
    _ additional: PartialKeyPath<R.Columns>...,
    resolution: PostgrestConflictResolution = .mergeDuplicates
  ) -> Never {
    fatalError()
  }

  @_disfavoredOverload
  @available(
    *, unavailable,
    message: "select(_:) takes a selection declared against this relation; its Source must be R"
  )
  public func select<S: PostgrestSelection>(_ selection: S.Type) -> Never {
    fatalError()
  }
}
