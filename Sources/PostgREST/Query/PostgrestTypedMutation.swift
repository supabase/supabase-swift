//
//  PostgrestTypedMutation.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

/// A write request against a writable relation.
///
/// Obtain one from `insert`, `upsert`, `update` or `delete` on a ``PostgrestTypedSource``. Those
/// methods exist only where the relation conforms to ``PostgrestWritableRelation``, so a read-only
/// view cannot be written.
///
/// Like the builder it wraps, this is a value type: chaining off the same mutation twice gives
/// two independent requests.
public struct PostgrestTypedMutation<R: PostgrestWritableRelation>: PostgrestKeyPathFilterable,
  Sendable
{
  public typealias Relation = R
  public typealias Phase = PostgrestFilterPhase

  /// The underlying string-based builder.
  public let builder: PostgrestFilterBuilder

  /// Wraps a builder in the typed mutation surface.
  ///
  /// - Parameter builder: The builder to wrap.
  public init(builder: PostgrestFilterBuilder) {
    self.builder = builder
  }

  /// Requests the affected rows back, decoded as `[R]`.
  ///
  /// This replaces the `Prefer` header rather than appending to it. The write methods set
  /// `return=minimal` so a plain ``execute()`` does not transfer rows, and appending would leave
  /// `Prefer: return=minimal,return=representation`, which is contradictory.
  /// `return=representation` alone returns every column, so no `select` parameter is needed.
  ///
  /// > Note: Because this replaces the whole header, do not combine it with any other `Prefer`
  /// > preference on a mutation. Slice 0 sets none.
  ///
  /// - Returns: A ``PostgrestTypedQuery`` decoding into `[R]`.
  public func returning() -> PostgrestTypedQuery<R, [R], PostgrestFilterPhase> {
    PostgrestTypedQuery(
      builder: builder.setHeader(name: "Prefer", value: "return=representation")
    )
  }

  /// Sends the request, discarding the response body.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<Void> {
    try await builder.execute()
  }
}

extension PostgrestTypedSource where R: PostgrestWritableRelation {
  /// Inserts a row.
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .insert(Todo.Draft(task: "buy milk"))
  ///   .execute()
  /// ```
  ///
  /// - Parameter values: The row to insert, in the relation's
  ///   ``PostgrestWritableRelation/Draft`` shape. Primary keys and defaulted columns are optional
  ///   there, so either can be left out and filled in by the database.
  /// - Returns: A ``PostgrestTypedMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func insert(_ values: R.Draft) throws -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(builder: try builder.insert(values, returning: .minimal))
  }

  /// Inserts a row, updating it instead if it conflicts on a unique constraint of your choosing.
  ///
  /// ```swift
  /// // merge on the `email` unique index rather than on the key
  /// try await client.from(User.self)
  ///   .upsert(User.Draft(email: "a@example.com", name: "Ada"), onConflict: \.email)
  ///   .execute()
  /// ```
  ///
  /// The target is spelled as key paths into the relation's ``PostgrestRelation/Columns``
  /// namespace, so a column that does not exist is a compile error rather than a PostgREST 400.
  /// Taking a first column plus the rest also makes an empty target unrepresentable.
  ///
  /// To merge on the primary key, use ``upsert(_:)``, which derives the target instead.
  ///
  /// - Parameters:
  ///   - values: The row to upsert, in the relation's ``PostgrestWritableRelation/Draft`` shape.
  ///   - column: The first column of the unique constraint to merge on.
  ///   - additional: The remaining columns, for a constraint spanning more than one.
  /// - Returns: A ``PostgrestTypedMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func upsert<
    First: PostgrestColumnExpression,
    each Rest: PostgrestColumnExpression
  >(
    _ values: R.Draft,
    onConflict column: KeyPath<R.Columns, First>,
    _ additional: repeat KeyPath<R.Columns, each Rest>
  ) throws -> PostgrestTypedMutation<R> {
    var names = [R.columns[keyPath: column].postgrestExpression]
    repeat names.append(R.columns[keyPath: each additional].postgrestExpression)
    return PostgrestTypedMutation(
      builder: try builder.upsert(
        values,
        onConflict: names.joined(separator: ","),
        returning: .minimal
      )
    )
  }

  /// Updates the rows matched by the filters applied to the returned value.
  ///
  /// > Important: With no filter this updates every row in the relation.
  ///
  /// The closure assigns to the columns this update changes. A column it never names stays out of
  /// the request body and the database leaves it alone; a column assigned `nil` is sent as an
  /// explicit `null` and is cleared.
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .update {
  ///     $0.task = "buy oat milk"
  ///     $0.dueDate = nil
  ///   }
  ///   .eq(\.id, 1)
  ///   .execute()
  /// ```
  ///
  /// - Parameter build: A closure that assigns to the columns to change.
  /// - Returns: A ``PostgrestTypedMutation`` to scope, then execute.
  /// - Throws: An encoding error if the assigned values cannot be serialized.
  public func update(
    _ build: (inout PostgrestUpdate<R>) -> Void
  ) throws -> PostgrestTypedMutation<R> {
    try update(PostgrestUpdate(build))
  }

  /// Updates the rows matched by the filters applied to the returned value.
  ///
  /// Takes an update built elsewhere, so the layer that decides what changes does not have to be
  /// the layer that sends it.
  ///
  /// > Important: With no filter this updates every row in the relation.
  ///
  /// - Parameter values: The columns to change.
  /// - Returns: A ``PostgrestTypedMutation`` to scope, then execute.
  /// - Throws: An encoding error if the assigned values cannot be serialized.
  public func update(_ values: PostgrestUpdate<R>) throws -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(builder: try builder.update(values, returning: .minimal))
  }

  /// Deletes the rows matched by the filters applied to the returned value.
  ///
  /// > Important: With no filter this deletes every row in the relation.
  ///
  /// - Returns: A ``PostgrestTypedMutation`` to scope, then execute.
  public func delete() -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(builder: builder.delete(returning: .minimal))
  }
}

extension PostgrestTypedSource where R: PostgrestWritableRelation & PostgrestKeyedRelation {
  /// Inserts a row, updating it instead if it conflicts on the relation's primary key.
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .upsert(Todo.Draft(id: 1, task: "buy milk"))
  ///   .execute()
  /// ```
  ///
  /// The conflict target comes from ``PostgrestKeyedRelation/primaryKeyColumns``, which is why this
  /// overload exists only where the relation declares a key. On a keyless relation the database has
  /// nothing to merge on, so an upsert with no target is not a merge at all — it inserts another row
  /// every call. Requiring the conformance makes that a compile error instead; use
  /// ``upsert(_:onConflict:_:)`` there and name a unique constraint the relation does have.
  ///
  /// The same ``PostgrestWritableRelation/Draft`` serves this and ``insert(_:)``: it is a row the
  /// database has not stored yet, whether this call ends up inserting it or merging it into an
  /// existing one.
  ///
  /// > Note: The target only takes effect if the columns it names are in the body. A key the
  /// > database generates is optional in `Draft`, so omitting it still inserts.
  ///
  /// - Parameter values: The row to upsert, in the relation's ``PostgrestWritableRelation/Draft``
  ///   shape.
  /// - Returns: A ``PostgrestTypedMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func upsert(_ values: R.Draft) throws -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(
      builder: try builder.upsert(
        values,
        onConflict: R.primaryKeyColumns.joined(separator: ","),
        returning: .minimal
      )
    )
  }
}
