import Foundation
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
    var request = self.request
    request.method = .get
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

    request.query.appendOrUpdate(URLQueryItem(name: "select", value: cleanedColumns))

    if let count {
      request.headers.appendOrUpdate(.prefer, value: "count=\(count.rawValue)")
    }
    if head {
      request.method = .head
    }

    return PostgrestFilterBuilder(carryingFrom: self, request: request)
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
  /// - Returns: A ``PostgrestFilterBuilder`` for applying additional constraints or executing the request.
  /// - Throws: An encoding error if `values` cannot be serialized, or ``PostgrestError`` on server error.
  public func insert(
    _ values: some Encodable,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    let body = try configuration.encoder.encode(values)

    var request = self.request
    request.method = .post
    var prefersHeaders: [String] = []
    if let returning {
      prefersHeaders.append("return=\(returning.rawValue)")
    }
    request.body = body
    if let count {
      prefersHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = request.headers[.prefer] {
      prefersHeaders.insert(prefer, at: 0)
    }
    if !prefersHeaders.isEmpty {
      request.headers[.prefer] = prefersHeaders.joined(separator: ",")
    }
    if let body = request.body,
      let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]]
    {
      let allKeys = jsonObject.flatMap(\.keys)
      let uniqueKeys = Set(allKeys).sorted()
      request.query.appendOrUpdate(
        URLQueryItem(
          name: "columns",
          value: uniqueKeys.map { "\"\($0)\"" }.joined(separator: ",")
        )
      )
    }

    return PostgrestFilterBuilder(carryingFrom: self, request: request)
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

    var request = self.request
    request.method = .post
    var prefersHeaders = [
      "resolution=\(ignoreDuplicates ? "ignore" : "merge")-duplicates",
      "return=\(returning.rawValue)",
    ]
    if let onConflict {
      request.query.appendOrUpdate(URLQueryItem(name: "on_conflict", value: onConflict))
    }
    request.body = body
    if let count {
      prefersHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = request.headers[.prefer] {
      prefersHeaders.insert(prefer, at: 0)
    }
    if !prefersHeaders.isEmpty {
      request.headers[.prefer] = prefersHeaders.joined(separator: ",")
    }

    if let body = request.body,
      let jsonObject = try JSONSerialization.jsonObject(with: body) as? [[String: Any]]
    {
      let allKeys = jsonObject.flatMap(\.keys)
      let uniqueKeys = Set(allKeys).sorted()
      request.query.appendOrUpdate(
        URLQueryItem(
          name: "columns",
          value: uniqueKeys.map { "\"\($0)\"" }.joined(separator: ",")
        )
      )
    }

    return PostgrestFilterBuilder(carryingFrom: self, request: request)
  }

  /// Performs a partial UPDATE on rows that match subsequent filters.
  ///
  /// By default, updated rows are returned as ``PostgrestReturningOptions/representation``. To
  /// suppress this, pass `.minimal` as `returning`.
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

    var request = self.request
    request.method = .patch
    var preferHeaders = ["return=\(returning.rawValue)"]
    request.body = body
    if let count {
      preferHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = request.headers[.prefer] {
      preferHeaders.insert(prefer, at: 0)
    }
    if !preferHeaders.isEmpty {
      request.headers[.prefer] = preferHeaders.joined(separator: ",")
    }

    return PostgrestFilterBuilder(carryingFrom: self, request: request)
  }

  /// Performs a DELETE on rows that match subsequent filters.
  ///
  /// By default, deleted rows are returned as ``PostgrestReturningOptions/representation``. To
  /// suppress this, pass `.minimal` as `returning`.
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
  ///   - returning: Controls which rows PostgREST returns after the delete. Defaults to ``PostgrestReturningOptions/representation``.
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  /// - Returns: A ``PostgrestFilterBuilder`` for scoping which rows are deleted.
  public func delete(
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> PostgrestFilterBuilder {
    var request = self.request
    request.method = .delete
    var preferHeaders = ["return=\(returning.rawValue)"]
    if let count {
      preferHeaders.append("count=\(count.rawValue)")
    }
    if let prefer = request.headers[.prefer] {
      preferHeaders.insert(prefer, at: 0)
    }
    if !preferHeaders.isEmpty {
      request.headers[.prefer] = preferHeaders.joined(separator: ",")
    }

    return PostgrestFilterBuilder(carryingFrom: self, request: request)
  }
}
