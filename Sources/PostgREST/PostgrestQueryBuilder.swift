import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers

/// Builder for SELECT, INSERT, UPDATE, UPSERT, and DELETE operations on a table or view.
///
/// Obtain a builder by calling ``PostgrestClient/from(_:)-3z9a4`` (untyped, `Table == AnyTable`)
/// or ``PostgrestClient/from(_:)-8yq6b`` (typed, `Table` is a ``TableRepresentable``) and then
/// chain one of the operation methods.
///
/// The String-based API (`select(_:)`, `insert(_:)`, …) is available on every specialization.
/// The typed KeyPath/associated-type API (`select()`, `insert(_ value: Table.Insert)`, …) is
/// available only when `Table` conforms to ``ReadOnlyTableRepresentable`` / ``TableRepresentable``.
///
/// ```swift
/// // Untyped
/// let todos: [Todo] = try await client
///   .from("todos")
///   .select()
///   .eq("done", value: false)
///   .execute()
///   .value
///
/// // Typed
/// let todos = try await client
///   .from(Todo.self)
///   .select()
///   .eq(\.done, value: false)
///   .execute()
///   .value
/// ```
public final class TypedPostgrestQueryBuilder<Table>: PostgrestBuilder, @unchecked Sendable {

  // MARK: - Shared mutation helpers (used by both String and typed methods)

  func applySelect(_ columns: String, head: Bool, count: CountOption?) {
    mutableState.withValue {
      $0.request.method = .get
      $0.request.query.appendOrUpdate(
        URLQueryItem(name: "select", value: Self.cleanColumns(columns)))
      if let count {
        $0.request.headers.appendOrUpdate(.prefer, value: "count=\(count.rawValue)")
      }
      if head {
        $0.request.method = .head
      }
    }
  }

  func applyInsert(
    _ values: some Encodable, returning: PostgrestReturningOptions?, count: CountOption?
  ) throws {
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
      Self.appendColumns(to: &$0.request)
    }
  }

  func applyUpsert(
    _ values: some Encodable,
    onConflict: String?,
    returning: PostgrestReturningOptions,
    count: CountOption?,
    ignoreDuplicates: Bool
  ) throws {
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
      Self.appendColumns(to: &$0.request)
    }
  }

  func applyUpdate(
    _ values: some Encodable, returning: PostgrestReturningOptions, count: CountOption?
  ) throws {
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
  }

  func applyDelete(returning: PostgrestReturningOptions, count: CountOption?) {
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
  }

  private static func cleanColumns(_ columns: String) -> String {
    var quoted = false
    return columns.compactMap { char -> String? in
      if char.isWhitespace, !quoted { return nil }
      if char == "\"" { quoted.toggle() }
      return String(char)
    }
    .joined(separator: "")
  }

  private static func appendColumns(to request: inout Helpers.HTTPRequest) {
    if let body = request.body,
      let jsonObject = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]]
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
  }

  // MARK: - String API (available on every specialization)

  /// Performs a SELECT query on the table or view using a raw column expression.
  ///
  /// - Parameters:
  ///   - columns: A comma-separated list of columns to retrieve. Columns may be aliased using
  ///     `alias:column` syntax.
  ///   - head: When `true`, the request uses the HEAD method and no rows are returned.
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. See ``CountOption``.
  /// - Returns: A filter builder for applying WHERE clauses and executing the query.
  public func select(
    _ columns: String,
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, AnyTable> {
    applySelect(columns, head: head, count: count)
    return TypedPostgrestFilterBuilder(self)
  }

  /// Inserts one or more rows into the table or view.
  public func insert(
    _ values: some Encodable,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) throws -> TypedPostgrestFilterBuilder<Table, AnyTable> {
    try applyInsert(values, returning: returning, count: count)
    return TypedPostgrestFilterBuilder(self)
  }

  /// Inserts rows, updating existing rows on conflict (upsert).
  public func upsert(
    _ values: some Encodable,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false
  ) throws -> TypedPostgrestFilterBuilder<Table, AnyTable> {
    try applyUpsert(
      values, onConflict: onConflict, returning: returning, count: count,
      ignoreDuplicates: ignoreDuplicates)
    return TypedPostgrestFilterBuilder(self)
  }

  /// Performs a partial UPDATE on rows that match subsequent filters.
  public func update(
    _ values: some Encodable,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) throws -> TypedPostgrestFilterBuilder<Table, AnyTable> {
    try applyUpdate(values, returning: returning, count: count)
    return TypedPostgrestFilterBuilder(self)
  }

  /// Performs a DELETE on rows that match subsequent filters.
  public func delete(
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, AnyTable> {
    applyDelete(returning: returning, count: count)
    return TypedPostgrestFilterBuilder(self)
  }
}

// MARK: - Untyped no-argument select (`AnyTable`)

extension TypedPostgrestQueryBuilder where Table == AnyTable {
  /// Performs a SELECT of all columns (`*`).
  public func select(
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<AnyTable, AnyTable> {
    applySelect("*", head: head, count: count)
    return TypedPostgrestFilterBuilder(self)
  }
}

// MARK: - Typed SELECT (read-only + read-write tables)

extension TypedPostgrestQueryBuilder where Table: ReadOnlyTableRepresentable {
  /// Selects all columns, returning `[Table]` (the full row type).
  public func select(
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table> {
    applySelect(Table.selectString, head: head, count: count)
    return TypedPostgrestFilterBuilder(self)
  }

  /// Selects only the columns defined by `Selection`, returning `[Selection]`.
  public func select<S: SelectionRepresentable>(
    _ selection: S.Type,
    head: Bool = false,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, S> {
    applySelect(S.selectString, head: head, count: count)
    return TypedPostgrestFilterBuilder(self)
  }
}

// MARK: - Typed writes (read-write tables only)

extension TypedPostgrestQueryBuilder where Table: TableRepresentable {
  /// Inserts a single typed row.
  public func insert(
    _ value: Table.Insert,
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) throws -> TypedPostgrestTransformBuilder<Table, Table> {
    try applyInsert(value, returning: returning, count: count)
    return TypedPostgrestTransformBuilder(self)
  }

  /// Inserts multiple typed rows.
  public func insert(
    _ values: [Table.Insert],
    returning: PostgrestReturningOptions? = nil,
    count: CountOption? = nil
  ) throws -> TypedPostgrestTransformBuilder<Table, Table> {
    try applyInsert(values, returning: returning, count: count)
    return TypedPostgrestTransformBuilder(self)
  }

  /// Upserts a single typed row.
  public func upsert(
    _ value: Table.Insert,
    onConflict: String? = nil,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil,
    ignoreDuplicates: Bool = false
  ) throws -> TypedPostgrestTransformBuilder<Table, Table> {
    try applyUpsert(
      value, onConflict: onConflict, returning: returning, count: count,
      ignoreDuplicates: ignoreDuplicates)
    return TypedPostgrestTransformBuilder(self)
  }

  /// Updates rows with a typed patch value.
  public func update(
    _ value: Table.Update,
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) throws -> TypedPostgrestFilterBuilder<Table, Table> {
    try applyUpdate(value, returning: returning, count: count)
    return TypedPostgrestFilterBuilder(self)
  }

  /// Deletes rows, returning a typed filter builder.
  public func delete(
    returning: PostgrestReturningOptions = .representation,
    count: CountOption? = nil
  ) -> TypedPostgrestFilterBuilder<Table, Table> {
    applyDelete(returning: returning, count: count)
    return TypedPostgrestFilterBuilder(self)
  }
}

/// The untyped SELECT/INSERT/UPDATE/UPSERT/DELETE builder.
public typealias PostgrestQueryBuilder = TypedPostgrestQueryBuilder<AnyTable>
