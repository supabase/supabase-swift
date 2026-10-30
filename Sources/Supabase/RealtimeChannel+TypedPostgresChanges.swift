//
//  RealtimeChannel+TypedPostgresChanges.swift
//  Supabase
//
//  Created by Guilherme Souza on 30/10/26.
//

public import Foundation
import Helpers
public import PostgREST
public import Realtime

extension RealtimeChannel {
  /// Returns an async stream of the row changes in a relation, bound to the relation's row type.
  ///
  /// The relation names the schema and the table. The `where` closure narrows the rows with the
  /// same column namespace a typed query uses. Call ``TypedPostgresChange/row()`` on each change
  /// to decode its record as `R`.
  ///
  /// The stream shapes the join request. Open it before you call ``RealtimeChannel/subscribe()``.
  ///
  /// ```swift
  /// let changes = await channel.postgresChanges(for: Todo.self, where: { $0.listID.eq(listID) })
  /// try await channel.subscribe()
  /// for await change in changes {
  ///   switch change.kind {
  ///   case .insert: todos.append(try change.row())
  ///   case .update: todos.replace(try change.row())
  ///   case .delete: todos.removeAll { $0.id == change.oldRecord?["id"]?.intValue }
  ///   default: break
  ///   }
  /// }
  /// ```
  ///
  /// Realtime understands fewer filters than PostgREST. The filter can use `eq`, `neq`, `gt`,
  /// `gte`, `lt`, `lte`, `in`, `like`, `ilike`, `regexMatch`, `regexIMatch`, `isDistinct`, and the
  /// `IS` checks, on stored columns. It can negate one condition with `!` and join conditions with
  /// `&&`. Any other filter is a programmer error and traps: `||`, `!` over a group, the array,
  /// range, JSON and full-text operators, and JSON paths.
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  ///
  /// - Parameters:
  ///   - relation: The relation to watch.
  ///   - event: The change events to receive. Defaults to ``PostgresChangeEvent/all``.
  ///   - filter: Builds the filter from the relation's columns, or `nil` for every row.
  ///   - decoder: The decoder ``TypedPostgresChange/row()`` uses. Defaults to the decoder
  ///     PostgREST uses, so a row decodes the same from a query and from a change.
  /// - Returns: An `AsyncStream` of ``TypedPostgresChange`` values.
  @_spi(Experimental)
  nonisolated public func postgresChanges<R: _PostgrestRelation>(
    for relation: R.Type,
    event: PostgresChangeEvent = .all,
    where filter: ((R.Columns) -> _PostgrestFilter<R>)? = nil,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
  ) async -> AsyncStream<TypedPostgresChange<R>> {
    let rawFilter = filter.map { $0(R.columns).realtimeFilter }
    return await postgresChanges(
      of: R.self, event: event, schema: R.schema, table: R.relationName, rawFilter: rawFilter,
      select: nil, decoder: decoder
    )
  }

  // Without the SPI import the solver reports "extra argument 'for' in call". This visible twin
  // catches the call and names the fix. The extra `Void` parameter only avoids a redeclaration.
  @available(
    *, unavailable,
    message:
      "The typed query API is experimental. Opt in with `@_spi(Experimental) import Supabase`."
  )
  nonisolated public func postgresChanges<R: _PostgrestRelation>(
    for relation: R.Type,
    event: PostgresChangeEvent = .all,
    where filter: ((R.Columns) -> _PostgrestFilter<R>)? = nil,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder,
    _: Void = ()
  ) async -> AsyncStream<TypedPostgresChange<R>> {
    fatalError()
  }
}

extension _PostgrestFilter {
  /// The filter in the grammar of a `postgres_changes` binding: `column=operator.value`
  /// conditions joined by commas, which the server ANDs.
  var realtimeFilter: String {
    node.realtimeConditions.joined(separator: ",")
  }
}

extension PostgrestFilterNode {
  fileprivate var realtimeConditions: [String] {
    switch self {
    case .and(let children):
      return children.flatMap(\.realtimeConditions)
    case .not(.not(let inner)):
      return inner.realtimeConditions
    case .not(let inner):
      return [inner.realtimeCondition(negated: true)]
    case .comparison, .raw, .or:
      return [realtimeCondition(negated: false)]
    }
  }

  private func realtimeCondition(negated: Bool) -> String {
    let prefix = negated ? "not." : ""
    switch self {
    case .comparison(let column, let `operator`, let operand):
      precondition(
        !column.contains("->"),
        "Realtime cannot filter on the JSON path `\(column)`. Filter on a stored column."
      )
      Self.requireRealtimeSupport(`operator`)
      if case .invalid(let reason) = operand {
        preconditionFailure(reason)
      }
      return "\(column)=\(prefix)\(`operator`.token).\(operand.grouped)"
    case .raw(let column, let operand):
      return "\(column)=\(prefix)\(operand)"
    case .or:
      preconditionFailure(
        "Realtime filters cannot use `||`. Join conditions with `&&`, or open one stream per branch."
      )
    case .and, .not:
      preconditionFailure(
        "Realtime filters cannot negate a group of conditions. Apply `!` to one condition."
      )
    }
  }

  private static func requireRealtimeSupport(_ operator: _PostgrestFilterOperator) {
    switch `operator` {
    case .eq, .neq, .gt, .gte, .lt, .lte, .is, .isDistinct, .in, .like, .ilike, .regexMatch,
      .regexIMatch:
      return
    case .likeAllOf, .likeAnyOf, .ilikeAllOf, .ilikeAnyOf, .contains, .containedBy, .overlaps,
      .rangeLt, .rangeGt, .rangeGte, .rangeLte, .rangeAdjacent, .textSearch:
      preconditionFailure("Realtime filters do not support the `\(`operator`.token)` operator.")
    }
  }
}
