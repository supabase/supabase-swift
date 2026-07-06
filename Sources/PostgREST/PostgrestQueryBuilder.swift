import ConcurrencyExtras
import Foundation
import HTTPTypes

/// Builder for SELECT, INSERT, UPDATE, UPSERT, and DELETE operations on a table or view.
///
/// Obtain a ``PostgrestQueryBuilder`` by calling ``PostgrestClient/from(_:)`` and then chain one
/// of the operation methods. Most methods return a ``PostgrestFilterBuilder`` so you can narrow the
/// affected rows with WHERE clauses before executing.
///
/// ```swift
/// // INSERT a single row
/// try await client
///   .from("todos")
///   .insert(["task": "Buy milk", "done": false])
///   .execute()
///
/// // SELECT with a filter
/// let todos: [Todo] = try await client
///   .from("todos")
///   .select()
///   .eq("done", value: false)
///   .execute()
///   .value
/// ```
///
/// > Note: Thread Safety: Inherits thread-safe mutable state management from ``PostgrestBuilder``.
///
/// > Important: Do not modify the same builder instance from multiple concurrent tasks.
///
/// ## Topics
///
/// ### Querying Rows
///
/// - ``select(_:head:count:)``
///
/// ### Inserting Rows
///
/// - ``insert(_:returning:count:)``
///
/// ### Updating Rows
///
/// - ``update(_:returning:count:)``
///
/// ### Upsert Rows
///
/// - ``upsert(_:onConflict:returning:count:ignoreDuplicates:)``
///
/// ### Deleting Rows
///
/// - ``delete(returning:count:)``
public final class PostgrestQueryBuilder: PostgrestBuilder, @unchecked Sendable {
  /// Performs a SELECT query on the table or view.
  ///
  /// By default all columns are returned (`*`). You can request specific columns, rename them,
  /// and embed related rows in a single call using PostgREST's column-selection syntax.
  ///
  /// ```swift
  /// // All columns
  /// .select()
  ///
  /// // Specific columns
  /// .select("id, task, done")
  ///
  /// // Column alias
  /// .select("taskName:task")
  ///
  /// // Embed related table
  /// .select("*, comments(*)")
  /// ```
  ///
  /// - Parameters:
  ///   - columns: A comma-separated list of columns to retrieve. Columns may be aliased using
  ///     `alias:column` syntax. Defaults to `"*"` (all columns).
  ///   - head: When `true`, the request uses the HEAD method and no rows are returned.
  ///     Useful when combined with `count` to retrieve only the total row count.
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  /// - Returns: A ``PostgrestFilterBuilder`` for applying WHERE clauses and executing the query.
  public func select(
    _ columns: String = "*",
    head: Bool = false,
    count: CountOption? = nil
  ) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.method = .get
      // remove whitespaces except when quoted.
      var quoted = false
      let cleanedColumns = columns.compactMap { char -> String? in
        if char.isWhitespace, !quoted {
          return nil
        }
        if char == "\"" {
          quoted = !quoted
        }
        return String(char)
      }
      .joined(separator: "")

      $0.request.query.appendOrUpdate(URLQueryItem(name: "select", value: cleanedColumns))

      if let count {
        $0.request.headers[.prefer] = "count=\(count.rawValue)"
      }
      if head {
        $0.request.method = .head
      }
    }

    return PostgrestFilterBuilder(self)
  }

  /// Inserts one or more rows into the table or view.
  ///
  /// By default, inserted rows are not returned. To receive the inserted data, chain with
  /// ``PostgrestTransformBuilder/select(_:)`` after calling this method.
  ///
  /// ```swift
  /// // Insert a single row
  /// try await client
  ///   .from("todos")
  ///   .insert(["task": "Buy groceries", "done": false])
  ///   .execute()
  ///
  /// // Insert multiple rows and return them
  /// let inserted: [Todo] = try await client
  ///   .from("todos")
  ///   .insert([Todo(task: "A"), Todo(task: "B")])
  ///   .select()
  ///   .execute()
  ///   .value
  /// ```
  ///
  /// - Parameters:
  ///   - values: An `Encodable` value representing a single row or an array of rows to insert.
  ///   - returning: Controls which rows PostgREST returns. Defaults to `nil` (server decides).
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  /// - Returns: A ``PostgrestFilterBuilder`` for applying additional constraints or executing the request.
  /// - Throws: An encoding error if `values` cannot be serialized, or ``PostgrestError`` on server error.
  public func insert(
    _ values: some Encodable,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    let body = try configuration.encoder.encode(values)

    try mutableState.withValue {
      $0.request.method = .post
      var prefersHeaders: [String] = []
      if let returning {
        prefersHeaders.append("return=\(returning.rawValue)")
      }
      $0.request.body = body
      if let count {
        prefersHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers[.prefer] {
        prefersHeaders.insert(prefer, at: 0)
      }
      if !prefersHeaders.isEmpty {
        $0.request.headers[.prefer] = prefersHeaders.joined(separator: ",")
      }
      if let body = $0.request.body,
        let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]]
      {
        let allKeys = jsonObject.flatMap(\.keys)
        let uniqueKeys = Set(allKeys).sorted()
        $0.request.query.appendOrUpdate(
          URLQueryItem(
            name: "columns",
            value: uniqueKeys.map { "\"\($0)\"" }.joined(separator: ",")
          )
        )
      }
    }

    return PostgrestFilterBuilder(self)
  }

  /// Inserts rows, updating existing rows on conflict (upsert).
  ///
  /// Depending on `onConflict`, this is equivalent to an INSERT … ON CONFLICT DO UPDATE. If the
  /// conflict column(s) match an existing row, the row is merged or ignored depending on
  /// `ignoreDuplicates`.
  ///
  /// By default, upserted rows are returned. To suppress this, pass `.minimal` as `returning`.
  ///
  /// ```swift
  /// // Upsert a row, merging on the "id" column
  /// let upserted: Todo = try await client
  ///   .from("todos")
  ///   .upsert(Todo(id: 1, task: "Buy milk"))
  ///   .select()
  ///   .single()
  ///   .execute()
  ///   .value
  /// ```
  ///
  /// - Parameters:
  ///   - values: An `Encodable` value representing a single row or an array of rows.
  ///   - onConflict: Comma-separated UNIQUE column(s) that determine whether a row is a duplicate.
  ///     When `nil`, PostgREST uses the table's primary key.
  ///   - returning: Controls which rows PostgREST returns after the upsert. Defaults to ``PostgrestReturningOptions/representation``.
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  ///   - ignoreDuplicates: When `true`, conflicting rows are silently ignored. When `false` (the
  ///     default), conflicting rows are merged with the supplied values.
  /// - Returns: A ``PostgrestFilterBuilder`` for applying additional constraints or executing the request.
  /// - Throws: An encoding error if `values` cannot be serialized, or ``PostgrestError`` on server error.
  public func upsert(
    _ values: some Encodable,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false
  ) throws -> PostgrestFilterBuilder {
    let body = try configuration.encoder.encode(values)

    try mutableState.withValue {
      $0.request.method = .post
      var prefersHeaders = [
        "resolution=\(ignoreDuplicates ? "ignore" : "merge")-duplicates",
        "return=\(returning.rawValue)",
      ]
      if let onConflict {
        $0.request.query.appendOrUpdate(URLQueryItem(name: "on_conflict", value: onConflict))
      }
      $0.request.body = body
      if let count {
        prefersHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers[.prefer] {
        prefersHeaders.insert(prefer, at: 0)
      }
      if !prefersHeaders.isEmpty {
        $0.request.headers[.prefer] = prefersHeaders.joined(separator: ",")
      }

      if let body = $0.request.body,
        let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]]
      {
        let allKeys = jsonObject.flatMap(\.keys)
        let uniqueKeys = Set(allKeys).sorted()
        $0.request.query.appendOrUpdate(
          URLQueryItem(
            name: "columns",
            value: uniqueKeys.map { "\"\($0)\"" }.joined(separator: ",")
          )
        )
      }
    }
    return PostgrestFilterBuilder(self)
  }

  /// Performs a partial UPDATE on rows that match subsequent filters.
  ///
  /// By default, updated rows are returned as ``PostgrestReturningOptions/representation``. To
  /// suppress this, pass `.minimal` as `returning`.
  ///
  /// > Important: Omitting a filter will update **all rows** in the table. Always chain
  /// > a filter such as ``PostgrestFilterBuilder/eq(_:value:)`` before calling ``PostgrestBuilder/execute(options:)-96tpd``.
  ///
  /// ```swift
  /// try await client
  ///   .from("todos")
  ///   .update(["done": true])
  ///   .eq("id", value: 42)
  ///   .execute()
  /// ```
  ///
  /// - Parameters:
  ///   - values: An `Encodable` value with the columns to update.
  ///   - returning: Controls which rows PostgREST returns after the update. Defaults to ``PostgrestReturningOptions/representation``.
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  /// - Returns: A ``PostgrestFilterBuilder`` for scoping which rows are affected.
  /// - Throws: An encoding error if `values` cannot be serialized, or ``PostgrestError`` on server error.
  public func update(
    _ values: some Encodable,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    let body = try configuration.encoder.encode(values)
    mutableState.withValue {
      $0.request.method = .patch
      var preferHeaders = ["return=\(returning.rawValue)"]
      $0.request.body = body
      if let count {
        preferHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers[.prefer] {
        preferHeaders.insert(prefer, at: 0)
      }
      if !preferHeaders.isEmpty {
        $0.request.headers[.prefer] = preferHeaders.joined(separator: ",")
      }
    }
    return PostgrestFilterBuilder(self)
  }

  /// Performs a DELETE on rows that match subsequent filters.
  ///
  /// By default, deleted rows are returned as ``PostgrestReturningOptions/representation``. To
  /// suppress this, pass `.minimal` as `returning`.
  ///
  /// > Important: Omitting a filter will delete **all rows** in the table. Always chain
  /// > a filter such as ``PostgrestFilterBuilder/eq(_:value:)`` before calling ``PostgrestBuilder/execute(options:)-96tpd``.
  ///
  /// ```swift
  /// try await client
  ///   .from("todos")
  ///   .delete()
  ///   .eq("id", value: 42)
  ///   .execute()
  /// ```
  ///
  /// - Parameters:
  ///   - returning: Controls which rows PostgREST returns after the delete. Defaults to ``PostgrestReturningOptions/representation``.
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  /// - Returns: A ``PostgrestFilterBuilder`` for scoping which rows are deleted.
  public func delete(
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.method = .delete
      var preferHeaders = ["return=\(returning.rawValue)"]
      if let count {
        preferHeaders.append("count=\(count.rawValue)")
      }
      if let prefer = $0.request.headers[.prefer] {
        preferHeaders.insert(prefer, at: 0)
      }
      if !preferHeaders.isEmpty {
        $0.request.headers[.prefer] = preferHeaders.joined(separator: ",")
      }
    }
    return PostgrestFilterBuilder(self)
  }
}
