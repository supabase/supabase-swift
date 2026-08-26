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
  /// - Parameter values: The row to insert, in the relation's `Insert` shape. Primary keys and
  ///   defaulted columns are optional there, so either can be left out and filled in by the
  ///   database.
  /// - Returns: A ``PostgrestTypedMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func insert(_ values: R.Insert) throws -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(builder: try builder.insert(values, returning: .minimal))
  }

  /// Inserts rows, updating any that conflict.
  ///
  /// - Parameters:
  ///   - values: The rows to upsert.
  ///   - onConflict: Comma-separated unique columns that determine a duplicate. Defaults to the
  ///     relation's primary key.
  /// - Returns: A ``PostgrestTypedMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func upsert(
    _ values: R.Insert,
    onConflict: String? = nil
  ) throws -> PostgrestTypedMutation<R> {
    PostgrestTypedMutation(
      builder: try builder.upsert(values, onConflict: onConflict, returning: .minimal)
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
