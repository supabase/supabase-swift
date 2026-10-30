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
  /// range, JSON and full-text operators, JSON paths, and casts. A `raw` filter must follow the
  /// same rules.
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
  ///
  /// A filter Realtime cannot run is a programmer error, so this traps with the reason.
  var realtimeFilter: String {
    do {
      return try realtimeConditions().joined(separator: ",")
    } catch {
      preconditionFailure(error.reason)
    }
  }

  /// The filter's conditions in the `postgres_changes` grammar.
  ///
  /// - Throws: ``UnsupportedRealtimeFilter`` naming the first part Realtime cannot run.
  func realtimeConditions() throws(UnsupportedRealtimeFilter) -> [String] {
    try node.realtimeConditions()
  }
}

/// A part of a typed filter that a `postgres_changes` binding cannot express.
struct UnsupportedRealtimeFilter: Error {
  var reason: String
}

extension PostgrestFilterNode {
  fileprivate func realtimeConditions() throws(UnsupportedRealtimeFilter) -> [String] {
    switch self {
    case .and(let children):
      var conditions: [String] = []
      for child in children {
        conditions += try child.realtimeConditions()
      }
      return conditions
    case .not(.not(let inner)):
      return try inner.realtimeConditions()
    case .not(let inner):
      return [try inner.realtimeCondition(negated: true)]
    case .comparison, .raw, .or:
      return [try realtimeCondition(negated: false)]
    }
  }

  private func realtimeCondition(negated: Bool) throws(UnsupportedRealtimeFilter) -> String {
    let prefix = negated ? "not." : ""
    switch self {
    case .comparison(let column, let `operator`, let operand):
      try Self.requireRealtimeColumn(column)
      try Self.requireRealtimeOperator(`operator`.token)
      if case .invalid(let reason) = operand {
        throw UnsupportedRealtimeFilter(reason: reason)
      }
      return "\(column)=\(prefix)\(`operator`.token).\(operand.grouped)"
    case .raw(let column, let operand):
      try Self.requireRealtimeColumn(column)
      var expression = Substring(operand)
      if expression.hasPrefix("not.") {
        guard !negated else {
          throw UnsupportedRealtimeFilter(
            reason: "Realtime filters cannot negate `\(column)=\(operand)` again.")
        }
        expression = expression.dropFirst("not.".count)
      }
      guard expression.contains(".") else {
        throw UnsupportedRealtimeFilter(
          reason:
            "The raw Realtime filter `\(column)=\(operand)` is not in the `operator.value` form."
        )
      }
      try Self.requireRealtimeOperator(String(expression.prefix { $0 != "." }))
      return "\(column)=\(prefix)\(operand)"
    case .or where !negated:
      throw UnsupportedRealtimeFilter(
        reason:
          "Realtime filters cannot use `||`. Join conditions with `&&`, or open one stream per branch."
      )
    case .and, .or, .not:
      throw UnsupportedRealtimeFilter(
        reason: "Realtime filters cannot negate a group of conditions. Apply `!` to one condition."
      )
    }
  }

  /// The values of the server's `realtime.equality_op` type. A raw node is checked against the
  /// same list as a typed operator, so both spellings accept and reject the same filters.
  private static let realtimeOperators: Set<String> = [
    "eq", "neq", "gt", "gte", "lt", "lte", "in", "like", "ilike", "is", "match", "imatch",
    "isdistinct",
  ]

  private static func requireRealtimeOperator(_ token: String) throws(UnsupportedRealtimeFilter) {
    guard realtimeOperators.contains(token) else {
      throw UnsupportedRealtimeFilter(
        reason: "Realtime filters do not support the `\(token)` operator.")
    }
  }

  private static func requireRealtimeColumn(_ column: String) throws(UnsupportedRealtimeFilter) {
    if column.contains("->") {
      throw UnsupportedRealtimeFilter(
        reason: "Realtime cannot filter on the JSON path `\(column)`. Filter on a stored column.")
    }
    if column.contains("::") {
      throw UnsupportedRealtimeFilter(
        reason: "Realtime cannot filter on the cast `\(column)`. Filter on a stored column.")
    }
  }
}
