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
  /// let changes = try await channel.postgresChanges(of: Todo.self, where: { $0.listID.eq(listID) })
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
  /// The Realtime filter grammar is smaller than PostgREST's. It joins conditions with `&&` and
  /// negates one condition with `!`. This method throws for `||` and for `!` over a group,
  /// because the grammar cannot write them. The server judges the rest, such as the operators
  /// and the columns. When it refuses the filter, ``RealtimeChannel/subscribe()`` throws a
  /// ``RealtimeError`` of kind ``RealtimeError/Kind-swift.struct/server`` with the server's
  /// message.
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  ///
  /// - Parameters:
  ///   - relation: The relation to watch.
  ///   - event: The change events to receive. Defaults to ``PostgresChangeEvent/all``.
  ///   - filter: Builds the filter from the relation's columns, or `nil` for every row.
  ///   - decoder: The decoder ``TypedPostgresChange/row()`` uses. `nil` uses the decoder of the
  ///     typed query API, a `JSONDecoder.supabase()`, so a row decodes the same from a query and
  ///     from a change.
  /// - Returns: An `AsyncStream` of ``TypedPostgresChange`` values.
  /// - Throws: ``RealtimeError`` with kind ``RealtimeError/Kind-swift.struct/invalidRequest``
  ///   when the Realtime filter grammar cannot write the filter. The message names the part.
  @_spi(Experimental)
  nonisolated public func postgresChanges<R: _PostgrestRelation>(
    of relation: R.Type,
    event: PostgresChangeEvent = .all,
    where filter: ((R.Columns) -> _PostgrestFilter<R>)? = nil,
    decoder: JSONDecoder? = nil
  ) async throws -> AsyncStream<TypedPostgresChange<R>> {
    let rawFilter = try filter.map { try $0(R.columns).realtimeFilter }
    return await postgresChanges(
      of: R.self, event: event, schema: R.schema, table: R.relationName, rawFilter: rawFilter,
      select: nil, decoder: decoder ?? PostgrestClient.Configuration.jsonDecoder
    )
  }

  // Without the SPI import the solver reports "missing argument for parameter 'table'". This
  // visible twin catches the call and names the fix. The extra `Void` parameter only avoids a
  // redeclaration.
  /// Unavailable. Names the SPI import that the typed `postgresChanges(of:event:where:decoder:)`
  /// needs.
  @available(
    *, unavailable,
    message:
      "The typed query API is experimental. Opt in with `@_spi(Experimental) import Supabase`."
  )
  nonisolated public func postgresChanges<R: _PostgrestRelation>(
    of relation: R.Type,
    event: PostgresChangeEvent = .all,
    where filter: ((R.Columns) -> _PostgrestFilter<R>)? = nil,
    decoder: JSONDecoder? = nil,
    _: Void = ()
  ) async throws -> AsyncStream<TypedPostgresChange<R>> {
    fatalError()
  }
}

extension _PostgrestFilter {
  /// The filter in the grammar of a `postgres_changes` binding: `column=operator.value`
  /// conditions joined by commas, which the server ANDs.
  ///
  /// The server judges the operators and the columns. Only the parts the grammar cannot write
  /// throw here.
  ///
  /// - Throws: ``RealtimeError`` with kind ``RealtimeError/Kind-swift.struct/invalidRequest``
  ///   naming the first part the grammar cannot write.
  var realtimeFilter: String {
    get throws {
      do {
        return try realtimeConditions().joined(separator: ",")
      } catch {
        throw RealtimeError(
          kind: .invalidRequest, message: error.reason,
          underlyingError: error)
      }
    }
  }

  /// The filter's conditions in the `postgres_changes` grammar.
  ///
  /// - Throws: ``UnsupportedRealtimeFilter`` naming the first part the grammar cannot write.
  func realtimeConditions() throws(UnsupportedRealtimeFilter) -> [String] {
    try node.realtimeConditions()
  }
}

/// A part of a typed filter that the `postgres_changes` filter grammar cannot write.
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
      if case .invalid(let reason) = operand {
        throw UnsupportedRealtimeFilter(reason: reason)
      }
      return "\(column)=\(prefix)\(`operator`.token).\(operand.grouped)"
    case .raw(let column, let operand):
      if negated, operand.hasPrefix("not.") {
        return "\(column)=\(operand.dropFirst("not.".count))"
      }
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
}
