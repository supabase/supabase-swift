//
//  SupabaseClient+Stream.swift
//  Supabase
//
//  Created by Guilherme Souza on 30/10/26.
//

import Foundation
import Helpers
public import PostgREST
import Realtime

extension SupabaseClient {
  /// Returns the rows of a relation as a stream that stays in sync with the database.
  ///
  /// Each element is the full current result set. The first element comes after the initial
  /// fetch. A new element comes after every insert, update or delete that changes the result.
  ///
  /// ```swift
  /// for try await todos in supabase.stream(Todo.self, where: { $0.listId.eq(listID) }) {
  ///   self.todos = todos
  /// }
  /// ```
  ///
  /// The stream opens a channel of its own and removes it when the iteration ends. It subscribes
  /// first, then fetches, so no change is lost between the two. Changes that arrive during the
  /// fetch apply on top of its rows, matched by primary key. After the channel joins again, for
  /// example after a reconnect, the stream fetches again, because changes sent while the channel
  /// was away are lost.
  ///
  /// Rows keep the order of the fetch. A new row goes at the end. Sort the rows yourself when the
  /// order matters.
  ///
  /// The filter applies to the fetch and to the changes, so it takes only what Realtime can run:
  /// `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `in`, `like`, `ilike`, `regexMatch`, `regexIMatch`,
  /// `isDistinct` and the `IS` checks, on stored columns, with `!` on one condition and `&&`.
  /// Any other filter is a programmer error and traps.
  ///
  /// > Note: Realtime checks the filter against the new row only. An update that moves a row out
  /// > of the filter does not reach the stream, so the row stays until the next fetch. Realtime
  /// > cannot filter deletes, so a filtered stream receives the primary key of every deleted row
  /// > in the table and ignores the ones it does not hold.
  ///
  /// > Warning: The typed query API is experimental. Its shape may change in a minor release.
  /// > Opt in with `@_spi(Experimental) import Supabase`.
  ///
  /// - Parameters:
  ///   - relation: The relation to read. It needs a primary key, so changes can be matched to
  ///     rows.
  ///   - filter: Builds the filter from the relation's columns, or `nil` for every row.
  /// - Returns: An `AsyncThrowingStream` of the current rows. It throws when the subscribe or a
  ///   fetch fails, when the channel fails for good, or when a changed row does not decode as `R`.
  @_spi(Experimental)
  public func stream<R: _PostgrestKeyedRelation>(
    _ relation: R.Type,
    where filter: ((R.Columns) -> _PostgrestFilter<R>)? = nil
  ) -> AsyncThrowingStream<[R], any Error> {
    liveRows(from: liveQueryUpdates(R.self, filter: filter?(R.columns)))
  }

  /// The rows of each ``LiveQueryUpdate/rows(_:)`` update. Stale updates carry no rows.
  func liveRows<R: Sendable>(
    from updates: AsyncThrowingStream<LiveQueryUpdate<R>, any Error>
  ) -> AsyncThrowingStream<[R], any Error> {
    let (rows, output) = AsyncThrowingStream<[R], any Error>.makeStream()
    let task = Task {
      do {
        for try await update in updates {
          if case .rows(let rows) = update {
            output.yield(rows)
          }
        }
        output.finish()
      } catch {
        output.finish(throwing: error)
      }
    }
    output.onTermination = { _ in task.cancel() }
    return rows
  }

  func liveQueryUpdates<R: _PostgrestKeyedRelation>(
    _: R.Type,
    filter: _PostgrestFilter<R>?
  ) -> AsyncThrowingStream<LiveQueryUpdate<R>, any Error> {
    makeLiveQueryUpdates { [self] in
      await liveQuerySource(for: R.self, filter: filter)
    }
  }

  /// Opens a dedicated channel for a live query and returns what the query runs against.
  func liveQuerySource<R: _PostgrestKeyedRelation>(
    for _: R.Type,
    filter: _PostgrestFilter<R>?
  ) async -> LiveQuerySource<R> {
    let realtimeFilter = filter?.realtimeFilter
    var bindings = [
      PostgresJoinConfig(
        event: .all, schema: R.schema, table: R.relationName, filter: realtimeFilter)
    ]
    if realtimeFilter != nil {
      bindings.append(PostgresJoinConfig(event: .delete, schema: R.schema, table: R.relationName))
    }

    let realtime = realtime
    let channel = await realtime.channel(
      "live:\(R.schema).\(R.relationName):\(UUID().uuidString.lowercased())"
    )
    let signals = await channel.postgresChangesSignals(bindings: bindings)

    let selection = from(R.self).select(LiveRowSelection<R>.self)
    let query = filter.map { filter in selection.where { _ in filter } } ?? selection

    return LiveQuerySource(
      signals: signals,
      primaryKey: R.primaryKeyColumns,
      decode: { try $0.decode(as: R.self) },
      subscribe: { try await channel.subscribe() },
      fetch: { try await query.execute().value.map(\.liveRow) },
      finish: { await realtime.removeChannel(channel) }
    )
  }
}

/// Selects a whole row of `R` and keeps its primary key values, to match changes to it.
private struct LiveRowSelection<R: _PostgrestKeyedRelation>: _PostgrestSelection {
  typealias Source = R

  static var selectString: String { R.selectString }

  let liveRow: LiveRow<R>

  /// - Throws: `DecodingError` when the row lacks a primary key column. Without its key, no
  ///   change could ever match the row.
  init(from decoder: any Decoder) throws {
    let values = try JSONObject(from: decoder)
    let key = try R.primaryKeyColumns.map { column in
      guard let value = values[column] else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: """
              A live query needs the primary key column `\(column)` in every row, but \
              `\(R.self).selectString` does not select it.
              """
          )
        )
      }
      return value
    }
    liveRow = LiveRow(key: key, row: try R(from: decoder))
  }
}
