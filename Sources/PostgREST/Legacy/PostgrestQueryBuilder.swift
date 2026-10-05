public import Foundation
import HTTPTypes

// The operation methods available before an operation has been chosen. The overview prose and
// curated `## Topics` groups for these live on the ``PostgrestQueryBuilder`` type alias in
// `PostgrestRequestBuilder.swift` — DocC discards doc comments written on `extension` blocks, so a
// `///` comment here would never be rendered.
extension PostgrestRequestBuilder where Phase == PostgrestQueryPhase {
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
    var copy = PostgrestFilterBuilder(carryingFrom: self)
    copy.request.method = .get
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

    copy.query.appendOrUpdate(URLQueryItem(name: "select", value: cleanedColumns))

    if let count {
      copy.request.headerFields.appendOrUpdate(.prefer, value: "count=\(count.rawValue)")
    }
    if head {
      copy.request.method = .head
    }

    return copy
  }

  /// Inserts one or more rows into the table or view.
  ///
  /// By default, inserted rows are not returned. To receive the inserted data, chain with
  /// ``PostgrestRequestBuilder/select(_:)`` after calling this method.
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
  ///   - defaultToNull: Controls what happens to a column that some rows in a bulk payload name and
  ///     others leave out. `true` (the default) inserts `null` for the rows that omit it; `false`
  ///     sends `Prefer: missing=default` so the column's `DEFAULT` applies instead. `upsert` takes
  ///     the same option.
  ///   - encoder: The `JSONEncoder` used to serialize `values`. Overrides
  ///     ``PostgrestClient/Configuration/encoder`` when non-`nil`.
  /// - Returns: A ``PostgrestTransformBuilder`` for shaping the returned rows or executing the request.
  ///   Filters are not available: PostgREST ignores them on an insert.
  /// - Throws: An encoding error if `values` cannot be serialized, or ``PostgrestError`` on server error.
  public func insert(
    _ values: some Encodable,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil,
    defaultToNull: Bool = true,
    encoder: JSONEncoder? = nil
  ) throws -> PostgrestTransformBuilder {
    let body = try (encoder ?? configuration.encoder).encode(values)

    var copy = PostgrestTransformBuilder(carryingFrom: self)
    copy.request.method = .post
    var prefersHeaders: [String] = []
    if let returning {
      prefersHeaders.append("return=\(returning.rawValue)")
    }
    copy.body = body
    if let count {
      prefersHeaders.append("count=\(count.rawValue)")
    }
    if !defaultToNull {
      prefersHeaders.append("missing=default")
    }
    if let prefer = copy.request.headerFields[.prefer] {
      prefersHeaders.insert(prefer, at: 0)
    }
    if !prefersHeaders.isEmpty {
      copy.request.headerFields[.prefer] = prefersHeaders.joined(separator: ",")
    }
    if let body = copy.body, let columns = try columnsQueryItem(forBody: body) {
      copy.query.appendOrUpdate(columns)
    }

    return copy
  }

  /// Inserts rows, updating existing rows on conflict (upsert).
  ///
  /// Depending on `onConflict`, this is equivalent to an INSERT … ON CONFLICT DO UPDATE. If the
  /// conflict column(s) match an existing row, the row is merged or ignored depending on
  /// `ignoreDuplicates`.
  ///
  /// By default, upserted rows are not returned. To receive the upserted data, chain with
  /// ``PostgrestRequestBuilder/select(_:)`` after calling this method.
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
  ///   - returning: Controls which rows PostgREST returns after the upsert. Defaults to `nil` (server decides).
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  ///   - ignoreDuplicates: When `true`, conflicting rows are silently ignored. When `false` (the
  ///     default), conflicting rows are merged with the supplied values.
  ///   - defaultToNull: Controls what happens to a column that some rows in a bulk payload name and
  ///     others leave out. `true` (the default) inserts `null` for the rows that omit it; `false`
  ///     sends `Prefer: missing=default` so the column's `DEFAULT` applies instead. This also
  ///     decides what a row omitting the conflict target merges against: under `false` the target
  ///     resolves to the database-generated value, which is what the conflict is detected on.
  ///   - encoder: The `JSONEncoder` used to serialize `values`. Overrides
  ///     ``PostgrestClient/Configuration/encoder`` when non-`nil`.
  /// - Returns: A ``PostgrestTransformBuilder`` for shaping the returned rows or executing the request.
  ///   Filters are not available: PostgREST ignores them on an upsert.
  /// - Throws: An encoding error if `values` cannot be serialized, or ``PostgrestError`` on server error.
  public func upsert(
    _ values: some Encodable,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false,
    defaultToNull: Bool = true,
    encoder: JSONEncoder? = nil
  ) throws -> PostgrestTransformBuilder {
    let body = try (encoder ?? configuration.encoder).encode(values)

    var copy = PostgrestTransformBuilder(carryingFrom: self)
    copy.request.method = .post
    var prefersHeaders = [
      "resolution=\(ignoreDuplicates ? "ignore" : "merge")-duplicates"
    ]
    if let returning {
      prefersHeaders.append("return=\(returning.rawValue)")
    }
    if let onConflict {
      copy.query.appendOrUpdate(URLQueryItem(name: "on_conflict", value: onConflict))
    }
    copy.body = body
    if let count {
      prefersHeaders.append("count=\(count.rawValue)")
    }
    if !defaultToNull {
      prefersHeaders.append("missing=default")
    }
    if let prefer = copy.request.headerFields[.prefer] {
      prefersHeaders.insert(prefer, at: 0)
    }
    if !prefersHeaders.isEmpty {
      copy.request.headerFields[.prefer] = prefersHeaders.joined(separator: ",")
    }

    if let body = copy.body, let columns = try columnsQueryItem(forBody: body) {
      copy.query.appendOrUpdate(columns)
    }

    return copy
  }

  /// Performs a partial UPDATE on rows that match subsequent filters.
  ///
  /// By default, updated rows are not returned. To receive the updated data, chain with
  /// ``PostgrestRequestBuilder/select(_:)`` after calling this method.
  ///
  /// > Important: Omitting a filter will update **all rows** in the table. Always chain
  /// > a filter such as ``PostgrestRequestBuilder/eq(_:value:)`` before calling
  /// > ``PostgrestRequestBuilder/execute(options:)->PostgrestResponse<Void>``.
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
  ///   - returning: Controls which rows PostgREST returns after the update. Defaults to `nil` (server decides).
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  ///   - encoder: The `JSONEncoder` used to serialize `values`. Overrides
  ///     ``PostgrestClient/Configuration/encoder`` when non-`nil`.
  /// - Returns: A ``PostgrestFilterBuilder`` for scoping which rows are affected.
  /// - Throws: An encoding error if `values` cannot be serialized, or ``PostgrestError`` on server error.
  public func update(
    _ values: some Encodable,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil,
    encoder: JSONEncoder? = nil
  ) throws -> PostgrestFilterBuilder {
    let body = try (encoder ?? configuration.encoder).encode(values)

    var copy = PostgrestFilterBuilder(carryingFrom: self)
    copy.request.method = .patch
    var preferHeaders: [String] = []
    if let returning {
      preferHeaders.append("return=\(returning.rawValue)")
    }
    copy.body = body
    if let count {
      preferHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = copy.request.headerFields[.prefer] {
      preferHeaders.insert(prefer, at: 0)
    }
    if !preferHeaders.isEmpty {
      copy.request.headerFields[.prefer] = preferHeaders.joined(separator: ",")
    }

    return copy
  }

  /// Performs a DELETE on rows that match subsequent filters.
  ///
  /// By default, deleted rows are not returned. To receive the deleted data, chain with
  /// ``PostgrestRequestBuilder/select(_:)`` after calling this method.
  ///
  /// > Important: Omitting a filter will delete **all rows** in the table. Always chain
  /// > a filter such as ``PostgrestRequestBuilder/eq(_:value:)`` before calling
  /// > ``PostgrestRequestBuilder/execute(options:)->PostgrestResponse<Void>``.
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
  ///   - returning: Controls which rows PostgREST returns after the delete. Defaults to `nil` (server decides).
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  /// - Returns: A ``PostgrestFilterBuilder`` for scoping which rows are deleted.
  public func delete(
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) -> PostgrestFilterBuilder {
    var copy = PostgrestFilterBuilder(carryingFrom: self)
    copy.request.method = .delete
    var preferHeaders: [String] = []
    if let returning {
      preferHeaders.append("return=\(returning.rawValue)")
    }
    if let count {
      preferHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = copy.request.headerFields[.prefer] {
      preferHeaders.insert(prefer, at: 0)
    }
    if !preferHeaders.isEmpty {
      copy.request.headerFields[.prefer] = preferHeaders.joined(separator: ",")
    }

    return copy
  }
}

/// The `columns` query parameter for an array request body: the union of the keys across every
/// row, quoted and comma-separated.
///
/// Without it, PostgREST requires every row to carry an identical key set and rejects the whole
/// request (`PGRST102`, 400) the moment one disagrees — it never derives the column list from the
/// first object and drops the rest. Rows in one batch legitimately differ, because a nil optional
/// is omitted from the payload rather than encoded as `null`, so the union has to be sent
/// explicitly to make a ragged batch representable at all.
///
/// - Parameter body: The encoded request body.
/// - Returns: The query item, or `nil` when the body is not an array of objects, or is an array
///   that contributes no keys at all. An empty union would spell `columns=`, which names one
///   column called `""` and makes PostgREST reject the request — so an empty batch sends no
///   parameter and writes nothing, rather than failing.
/// - Throws: An error if `body` is not valid JSON.
private func columnsQueryItem(forBody body: Data) throws -> URLQueryItem? {
  guard let rows = try JSONSerialization.jsonObject(with: body) as? [[String: Any]] else {
    return nil
  }
  let uniqueKeys = Set(rows.flatMap(\.keys)).sorted()
  guard !uniqueKeys.isEmpty else { return nil }
  return URLQueryItem(
    name: "columns",
    value: uniqueKeys.map { "\"\($0)\"" }.joined(separator: ",")
  )
}
