//
//  PostgrestMutation.swift
//  PostgREST
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import HTTPTypes

/// What an upsert does with a row that conflicts on its target.
///
/// Pass a value to the `resolution` parameter of a typed `upsert`. The default,
/// ``mergeDuplicates``, is the upsert everyone means by the word; ``ignoreDuplicates`` is a
/// different operation, and worth reaching for deliberately.
public struct _PostgrestConflictResolution: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates a ``_PostgrestConflictResolution`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``_PostgrestConflictResolution`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Updates the existing row with the supplied values — `ON CONFLICT DO UPDATE`.
  ///
  /// The default, and what "upsert" normally means.
  public static let mergeDuplicates: _PostgrestConflictResolution = "merge-duplicates"

  /// Leaves the existing row exactly as it is — `ON CONFLICT DO NOTHING`.
  ///
  /// Insert-if-absent. Use this for seeding reference data, backfilling, or any at-least-once job
  /// where overwriting a row someone has since edited would be data loss.
  public static let ignoreDuplicates: _PostgrestConflictResolution = "ignore-duplicates"
}

/// The stage a ``_PostgrestMutation`` is at, which decides the methods it offers.
///
/// You do not conform your own types to this. The phases are ``_PostgrestUnscopedPhase``,
/// ``_PostgrestScopedPhase`` and ``_PostgrestInsertPhase``.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public protocol _PostgrestMutationPhase {}

/// A ``_PostgrestMutationPhase`` in which the mutation can be sent.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public protocol _PostgrestExecutableMutationPhase: _PostgrestMutationPhase {}

/// The phase of an `update` or `delete` that no filter has scoped yet.
///
/// It has no `execute()`, because an unfiltered `update` or `delete` writes every row in the
/// relation. Call ``_PostgrestMutation/where(_:)`` to scope it, or ``_PostgrestMutation/all()`` to
/// write every row on purpose. Either one moves it to ``_PostgrestScopedPhase``.
public enum _PostgrestUnscopedPhase: _PostgrestMutationPhase {}

/// The phase of an `update` or `delete` that a filter, or ``_PostgrestMutation/all()``, has
/// scoped. It can be sent, and more filters can still be added.
public enum _PostgrestScopedPhase: _PostgrestExecutableMutationPhase {}

/// The phase of an `insert` or `upsert`.
///
/// It can be sent, but it cannot be filtered. An insert has no existing rows to filter, and
/// PostgREST ignores a filter sent with a `POST`.
public enum _PostgrestInsertPhase: _PostgrestExecutableMutationPhase {}

/// A write request against a writable relation.
///
/// Obtain one from `insert`, `upsert`, `update` or `delete` on a ``_PostgrestSource``. Those
/// methods exist only where the relation conforms to ``_PostgrestWritableRelation``, so a read-only
/// view cannot be written.
///
/// `Phase` decides what the mutation offers. An `update` or `delete` starts in
/// ``_PostgrestUnscopedPhase`` and cannot be sent until it is scoped, so writing every row takes a
/// deliberate ``all()``:
///
/// ```swift
/// try await client.from(Todo.self).delete().where { $0.id.eq(1) }.execute()  // one row
/// try await client.from(Todo.self).delete().all().execute()                  // every row
/// try await client.from(Todo.self).delete().execute()                        // does not compile
/// ```
///
/// An `insert` or `upsert` is in ``_PostgrestInsertPhase``, which can be sent but not filtered.
///
/// This is a value type: chaining off the same mutation twice gives two independent requests.
///
/// > Warning: Part of the typed query API, which is experimental. Its shape may change in a minor
/// > release. Opt in with `@_spi(Experimental) import Supabase`.
public struct _PostgrestMutation<R: _PostgrestWritableRelation, Phase: _PostgrestMutationPhase>:
  Sendable
{
  let client: PostgrestClient

  /// The request this mutation sends.
  public var request: _PostgrestRequest
}

extension _PostgrestMutation: _PostgrestFilterableRequest where Phase == _PostgrestScopedPhase {
  public typealias Relation = R
}

extension _PostgrestMutation where Phase == _PostgrestUnscopedPhase {
  /// Scopes the write by a filter, so it touches only the rows the filter matches.
  ///
  /// ```swift
  /// try await client.from(Todo.self).delete().where { $0.isDone.eq(true) }.execute()
  /// ```
  ///
  /// More `where` calls can follow. They are ANDed with this one.
  ///
  /// - Parameter build: Builds the filter from the relation's columns.
  /// - Returns: A mutation in ``_PostgrestScopedPhase``, which can be sent.
  public func `where`(
    _ build: (R.Columns) -> _PostgrestFilter<R>
  ) -> _PostgrestMutation<R, _PostgrestScopedPhase> {
    all().where(build)
  }

  /// Writes every row in the relation, on purpose.
  ///
  /// ```swift
  /// try await client.from(Todo.self).delete().all().execute()
  /// ```
  ///
  /// This adds nothing to the request. It only moves the mutation to ``_PostgrestScopedPhase``,
  /// so a write without a filter is something you spell out, not something you forget.
  ///
  /// - Returns: A mutation in ``_PostgrestScopedPhase``, which can be sent.
  public func all() -> _PostgrestMutation<R, _PostgrestScopedPhase> {
    _PostgrestMutation<R, _PostgrestScopedPhase>(client: client, request: request)
  }
}

extension _PostgrestMutation where Phase: _PostgrestExecutableMutationPhase {
  /// Requests the affected rows back, decoded as `[R]`.
  ///
  /// This replaces only the `return=` preference in the `Prefer` header, so it composes with
  /// whatever else a write method already set there — `upsert` puts `resolution=` in the same
  /// header, and losing it there would silently turn the upsert into a plain insert.
  /// `return=representation` alone returns every column, so no `select` parameter is needed.
  ///
  /// - Returns: A ``_PostgrestQuery`` decoding into `[R]`.
  public func returning() -> _PostgrestQuery<R, [R]> {
    var request = request
    request.setPreference("return=representation")
    return _PostgrestQuery(client: client, request: request)
  }

  /// Sends the request, discarding the response body.
  @discardableResult
  public func execute() async throws -> PostgrestResponse<Void> {
    try await request.execute(on: client) { _ in () }
  }

  /// Sends the request, discarding the response body but asking how many rows it affected.
  ///
  /// ```swift
  /// let removed = try await client.from(Todo.self).delete()
  ///   .where { $0.isDone.eq(true) }
  ///   .execute(count: .exact)
  ///   .count
  /// ```
  ///
  /// This composes with ``returning()``, which sets a different `Prefer` preference: the count is
  /// applied when the request is sent, and each preference replaces only its own key.
  ///
  /// - Parameter count: The counting algorithm. See ``CountOption`` for the accuracy/speed
  ///   trade-off.
  /// - Returns: A ``PostgrestResponse`` whose ``PostgrestResponse/count`` is the number of rows
  ///   affected.
  @discardableResult
  public func execute(count: CountOption) async throws -> PostgrestResponse<Void> {
    var request = request
    request.setPreference("count=\(count.rawValue)")
    return try await request.execute(on: client) { _ in () }
  }
}

// `maxAffected(_:)` bounds the rows a filter selected, so only a scoped mutation offers it.
// `dryRun()` has no such limit: PostgREST accepts `tx=rollback` on every write.
extension _PostgrestMutation where Phase == _PostgrestScopedPhase {
  /// Limits the number of rows the write may affect.
  ///
  /// When the number of affected rows would exceed `value`, PostgREST rejects the request and
  /// rolls back the transaction instead of applying a partial write. A safety net against an
  /// unintentionally broad update or delete.
  ///
  /// Requires PostgREST v13 or later. Only a scoped `update` or `delete` offers it: PostgREST
  /// rejects it on an insert.
  ///
  /// This replaces only the `handling=` and `max-affected=` preferences in the `Prefer` header,
  /// so it composes with whatever else the mutation already set there — ``returning()``,
  /// ``dryRun()``, an upsert's `resolution=`, or a count.
  ///
  /// - Parameter value: The maximum number of rows this write may affect.
  /// - Returns: A ``_PostgrestMutation`` so calls can be chained.
  public func maxAffected(_ value: Int) -> Self {
    var mutation = self
    mutation.request.setPreference("handling=strict")
    mutation.request.setPreference("max-affected=\(value)")
    return mutation
  }
}

extension _PostgrestMutation {
  /// Runs the write, then rolls back its transaction instead of committing it.
  ///
  /// The write executes — including any trigger side effects — and the response reflects what
  /// would have happened, but nothing is persisted. Useful for testing a mutation without
  /// touching real data.
  ///
  /// Requires PostgREST's `db-tx-end` setting to allow a client-controlled rollback.
  ///
  /// This replaces only the `tx=` preference in the `Prefer` header, so it composes with
  /// whatever else the mutation already set there — ``returning()``, ``maxAffected(_:)``, or a
  /// count.
  ///
  /// - Returns: A ``_PostgrestMutation`` so calls can be chained.
  public func dryRun() -> Self {
    var mutation = self
    mutation.request.setPreference("tx=rollback")
    return mutation
  }
}

extension _PostgrestSource where R: _PostgrestWritableRelation {
  /// Inserts a row.
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .insert(Todo.Draft(task: "buy milk"))
  ///   .execute()
  /// ```
  ///
  /// - Parameter values: The row to insert, in the relation's
  ///   ``_PostgrestWritableRelation/Draft`` shape. Primary keys and defaulted columns are optional
  ///   there, so either can be left out and filled in by the database.
  /// - Returns: A ``_PostgrestMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func insert(_ values: R.Draft) throws -> _PostgrestMutation<R, _PostgrestInsertPhase> {
    try insertion(values)
  }

  /// Inserts a collection of rows, in a single request.
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .insert(tasks.map { Todo.Draft(task: $0) })
  ///   .execute()
  /// ```
  ///
  /// The rows do not have to encode the same columns. A draft omits a nil optional rather than
  /// sending `null`, so a batch built by `map` routinely has ragged shapes; the request names the
  /// union of the columns explicitly, which is what makes a ragged batch representable at all.
  /// Without it, PostgREST requires every row to carry an identical key set and rejects the whole
  /// request (`PGRST102`, 400) rather than writing a partial result.
  ///
  /// > Note: An empty collection is not an error. It sends a request that writes nothing, and
  /// > ``_PostgrestMutation/returning()`` on it decodes an empty array. A batch computed from a
  /// > filter or a `map` may legitimately have no rows, and making every caller guard for that is a
  /// > worse trade than one wasted round trip.
  ///
  /// - Parameter values: The rows to insert, in the relation's
  ///   ``_PostgrestWritableRelation/Draft`` shape.
  /// - Returns: A ``_PostgrestMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func insert(_ values: some Collection<R.Draft>) throws -> _PostgrestMutation<
    R, _PostgrestInsertPhase
  > {
    try insertion(Array(values))
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
  /// The target is spelled as key paths into the relation's ``_PostgrestRelation/Columns``
  /// namespace, so a column that does not exist is a compile error rather than a PostgREST 400.
  /// Taking a first column plus the rest also makes an empty target unrepresentable.
  ///
  /// Each key path must land on a ``_PostgrestStoredColumn`` of *this* relation, which is narrower
  /// than a column expression in general: `on_conflict` names columns of a unique index, so a
  /// derived expression — a cast, an aggregate — is not a target PostgREST can take, and neither
  /// is a column belonging to some other relation. Both are rejected at the call site.
  ///
  /// To merge on the primary key, use ``upsert(_:resolution:)-(R.Draft,_)``, which derives the target instead.
  ///
  /// - Parameters:
  ///   - values: The row to upsert, in the relation's ``_PostgrestWritableRelation/Draft`` shape.
  ///   - column: The first column of the unique constraint to merge on.
  ///   - additional: The remaining columns, for a constraint spanning more than one.
  ///   - resolution: What to do with a conflicting row. Defaults to
  ///     ``_PostgrestConflictResolution/mergeDuplicates``.
  /// - Returns: A ``_PostgrestMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func upsert<
    FirstValue,
    FirstNullability: _PostgrestNullability,
    each RestValue,
    each RestNullability: _PostgrestNullability
  >(
    _ values: R.Draft,
    onConflict column: KeyPath<R.Columns, _PostgrestStoredColumn<R, FirstValue, FirstNullability>>,
    _ additional: repeat KeyPath<
      R.Columns, _PostgrestStoredColumn<R, each RestValue, each RestNullability>
    >,
    resolution: _PostgrestConflictResolution = .mergeDuplicates
  ) throws -> _PostgrestMutation<R, _PostgrestInsertPhase> {
    var names = [R.columns[keyPath: column].postgrestExpression]
    repeat names.append(R.columns[keyPath: each additional].postgrestExpression)
    return try insertion(
      values, onConflict: names.joined(separator: ","), resolution: resolution)
  }

  /// Upserts a collection of rows in a single request, merging on a unique constraint of your
  /// choosing.
  ///
  /// ```swift
  /// try await client.from(User.self)
  ///   .upsert(imported.map { User.Draft(email: $0.email, name: $0.name) }, onConflict: \.email)
  ///   .execute()
  /// ```
  ///
  /// The target applies to every row in the batch, and carries the same rules as
  /// ``upsert(_:onConflict:_:resolution:)-(R.Draft,_,_,_)``: each key path must name a stored column of this
  /// relation. As with the bulk insert, the rows may encode different columns and an empty collection
  /// writes nothing rather than throwing.
  ///
  /// - Parameters:
  ///   - values: The rows to upsert, in the relation's ``_PostgrestWritableRelation/Draft`` shape.
  ///   - column: The first column of the unique constraint to merge on.
  ///   - additional: The remaining columns, for a constraint spanning more than one.
  ///   - resolution: What to do with a conflicting row. Defaults to
  ///     ``_PostgrestConflictResolution/mergeDuplicates``, and applies to every row in the batch.
  /// - Returns: A ``_PostgrestMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func upsert<
    FirstValue,
    FirstNullability: _PostgrestNullability,
    each RestValue,
    each RestNullability: _PostgrestNullability
  >(
    _ values: some Collection<R.Draft>,
    onConflict column: KeyPath<R.Columns, _PostgrestStoredColumn<R, FirstValue, FirstNullability>>,
    _ additional: repeat KeyPath<
      R.Columns, _PostgrestStoredColumn<R, each RestValue, each RestNullability>
    >,
    resolution: _PostgrestConflictResolution = .mergeDuplicates
  ) throws -> _PostgrestMutation<R, _PostgrestInsertPhase> {
    var names = [R.columns[keyPath: column].postgrestExpression]
    repeat names.append(R.columns[keyPath: each additional].postgrestExpression)
    return try insertion(
      Array(values), onConflict: names.joined(separator: ","), resolution: resolution)
  }

  /// Updates the rows matched by the filters applied to the returned value.
  ///
  /// The returned mutation cannot be sent until it is scoped: call ``_PostgrestMutation/where(_:)``,
  /// or ``_PostgrestMutation/all()`` to update every row on purpose.
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
  ///   .where { $0.id.eq(1) }
  ///   .execute()
  /// ```
  ///
  /// - Parameter build: A closure that assigns to the columns to change.
  /// - Returns: A ``_PostgrestMutation`` to scope, then execute.
  /// - Throws: An encoding error if the assigned values cannot be serialized.
  public func update(
    _ build: (inout _PostgrestUpdate<R>) -> Void
  ) throws -> _PostgrestMutation<R, _PostgrestUnscopedPhase> {
    try update(_PostgrestUpdate(build))
  }

  /// Updates the rows matched by the filters applied to the returned value.
  ///
  /// Takes an update built elsewhere, so the layer that decides what changes does not have to be
  /// the layer that sends it.
  ///
  /// The returned mutation cannot be sent until it is scoped: call ``_PostgrestMutation/where(_:)``,
  /// or ``_PostgrestMutation/all()`` to update every row on purpose.
  ///
  /// - Parameter values: The columns to change.
  /// - Returns: A ``_PostgrestMutation`` to scope, then execute.
  /// - Throws: An encoding error if the assigned values cannot be serialized.
  public func update(
    _ values: _PostgrestUpdate<R>
  ) throws -> _PostgrestMutation<R, _PostgrestUnscopedPhase> {
    mutation(.patch, body: try PostgrestClient.Configuration.jsonEncoder.encode(values))
  }

  /// Deletes the rows matched by the filters applied to the returned value.
  ///
  /// The returned mutation cannot be sent until it is scoped: call ``_PostgrestMutation/where(_:)``,
  /// or ``_PostgrestMutation/all()`` to delete every row on purpose.
  ///
  /// - Returns: A ``_PostgrestMutation`` to scope, then execute.
  public func delete() -> _PostgrestMutation<R, _PostgrestUnscopedPhase> {
    mutation(.delete)
  }
}

extension _PostgrestSource where R: _PostgrestWritableRelation & _PostgrestKeyedRelation {
  /// Inserts a row, updating it instead if it conflicts on the relation's primary key.
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .upsert(Todo.Draft(id: 1, task: "buy milk"))
  ///   .execute()
  /// ```
  ///
  /// The conflict target comes from ``_PostgrestKeyedRelation/primaryKeyColumns``, which is why this
  /// overload exists only where the relation declares a key. On a keyless relation the database has
  /// nothing to merge on, so an upsert with no target is not a merge at all — it inserts another row
  /// every call. Requiring the conformance makes that a compile error instead; use
  /// ``upsert(_:onConflict:_:resolution:)-(R.Draft,_,_,_)`` there and name a unique constraint the relation does have.
  ///
  /// The same ``_PostgrestWritableRelation/Draft`` serves this and ``insert(_:)-(R.Draft)``: it is a row the
  /// database has not stored yet, whether this call ends up inserting it or merging it into an
  /// existing one.
  ///
  /// ### Omitting a generated key inserts
  ///
  /// A key the database generates (`@PrimaryKey @Default`) is optional in `Draft`. The conflict
  /// target only matches a row whose body carries the key, so the contract is: omit the key to
  /// insert, supply it to merge. Calling this in a loop with a key-less draft inserts a new row
  /// every time.
  ///
  /// ```swift
  /// // one form for both "new" and "edit": `id` is nil until the row has been saved
  /// try await client.from(Todo.self)
  ///   .upsert(Todo.Draft(id: editing?.id, task: text))
  ///   .execute()
  /// ```
  ///
  /// This is deliberate. It lets one draft back a form that both creates and edits rows. Requiring
  /// the key here would remove that pattern. If a write must never insert, use ``update(_:)-(_PostgrestUpdate<R>)`` scoped to
  /// the key.
  ///
  /// - Parameters:
  ///   - values: The row to upsert, in the relation's ``_PostgrestWritableRelation/Draft`` shape.
  ///   - resolution: What to do with a conflicting row. Defaults to
  ///     ``_PostgrestConflictResolution/mergeDuplicates``.
  /// - Returns: A ``_PostgrestMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func upsert(
    _ values: R.Draft,
    resolution: _PostgrestConflictResolution = .mergeDuplicates
  ) throws -> _PostgrestMutation<R, _PostgrestInsertPhase> {
    try insertion(
      values, onConflict: R.primaryKeyColumns.joined(separator: ","), resolution: resolution)
  }

  /// Upserts a collection of rows in a single request, merging on the relation's primary key.
  ///
  /// ```swift
  /// try await client.from(Todo.self)
  ///   .upsert(rows.map { Todo.Draft(id: $0.id, task: $0.task) })
  ///   .execute()
  /// ```
  ///
  /// The target comes from ``_PostgrestKeyedRelation/primaryKeyColumns``, exactly as in
  /// ``upsert(_:resolution:)-(R.Draft,_)``, and applies to every row in the batch. As with the bulk insert, the
  /// rows may encode different columns and an empty collection writes nothing rather than throwing.
  ///
  /// > Note: The target only takes effect for a row that carries the key columns in its body. A
  /// > row that omits a database-generated key is inserted, so a batch can mix the two. See
  /// > ``upsert(_:resolution:)-(R.Draft,_)`` for why this is the contract.
  ///
  /// - Parameters:
  ///   - values: The rows to upsert, in the relation's ``_PostgrestWritableRelation/Draft`` shape.
  ///   - resolution: What to do with a conflicting row. Defaults to
  ///     ``_PostgrestConflictResolution/mergeDuplicates``, and applies to every row in the batch.
  /// - Returns: A ``_PostgrestMutation`` to execute, or to request rows back from.
  /// - Throws: An encoding error if `values` cannot be serialized.
  public func upsert(
    _ values: some Collection<R.Draft>,
    resolution: _PostgrestConflictResolution = .mergeDuplicates
  ) throws -> _PostgrestMutation<R, _PostgrestInsertPhase> {
    try insertion(
      Array(values), onConflict: R.primaryKeyColumns.joined(separator: ","), resolution: resolution)
  }
}

extension _PostgrestSource where R: _PostgrestWritableRelation {
  /// A write that asks for no rows back. ``_PostgrestMutation/returning()`` opts in.
  fileprivate func mutation<Phase>(
    _ method: HTTPTypes.HTTPRequest.Method,
    body: Data? = nil,
    preferences: [String] = []
  ) -> _PostgrestMutation<R, Phase> {
    var request = request
    request.method = method
    request.body = body
    for preference in preferences + ["return=minimal"] {
      request.setPreference(preference)
    }
    return _PostgrestMutation(client: client, request: request)
  }

  fileprivate func insertion(
    _ values: some Encodable,
    onConflict: String? = nil,
    resolution: _PostgrestConflictResolution? = nil
  ) throws -> _PostgrestMutation<R, _PostgrestInsertPhase> {
    let body = try PostgrestClient.Configuration.jsonEncoder.encode(values)
    var mutation: _PostgrestMutation<R, _PostgrestInsertPhase> = mutation(
      .post, body: body, preferences: resolution.map { ["resolution=\($0.rawValue)"] } ?? [])
    if let onConflict {
      mutation.request.query.append(URLQueryItem(name: "on_conflict", value: onConflict))
    }
    if let columns = try columnsQueryItem(forBody: body) {
      mutation.request.query.append(columns)
    }
    return mutation
  }
}

/// Names the union of the columns across every row of a bulk write.
///
/// Without it PostgREST requires every row to carry an identical key set and rejects the whole
/// request (`PGRST102`, 400) rather than silently dropping any columns. A single object, or an
/// empty batch, needs no list.
private func columnsQueryItem(forBody body: Data) throws -> URLQueryItem? {
  guard let rows = try JSONSerialization.jsonObject(with: body) as? [[String: Any]] else {
    return nil
  }
  let columns = Set(rows.flatMap(\.keys)).sorted()
  guard !columns.isEmpty else { return nil }
  return URLQueryItem(name: "columns", value: columns.map { "\"\($0)\"" }.joined(separator: ","))
}
