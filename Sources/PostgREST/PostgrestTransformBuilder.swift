import ConcurrencyExtras
import Foundation
import HTTPTypes

/// Builder for applying result transformations such as ordering, pagination, and response format.
///
/// ``PostgrestTransformBuilder`` sits between ``PostgrestFilterBuilder`` (WHERE clauses) and
/// ``PostgrestBuilder/execute(options:)-96tpd`` (sending the request). All transformation methods
/// return `self` so they can be chained freely.
///
/// > Note: Thread Safety: Inherits thread-safe mutable state management from ``PostgrestBuilder``.
///
/// > Important: Do not modify the same builder instance from multiple concurrent tasks.
///
/// ## Topics
///
/// ### Returning Modified Rows
///
/// - ``select(_:)``
///
/// ### Ordering and Pagination
///
/// - ``order(_:ascending:nullsFirst:referencedTable:)``
/// - ``limit(_:referencedTable:)``
/// - ``range(from:to:referencedTable:)``
///
/// ### Response Format
///
/// - ``single()``
/// - ``csv()``
/// - ``geojson()``
/// - ``stripNulls()``
///
/// ### Query Analysis
///
/// - ``explain(analyze:verbose:settings:buffers:wal:format:)``
///
/// ### Limiting Affected Rows
///
/// - ``maxAffected(_:)``
public class PostgrestTransformBuilder: PostgrestBuilder, @unchecked Sendable {
  /// Requests that the server return the modified rows from a write operation.
  ///
  /// By default, INSERT, UPDATE, UPSERT, and DELETE operations do not return the affected rows.
  /// Calling this method adds a `return=representation` preference and sets the `select` query
  /// parameter, so the modified rows appear in ``PostgrestResponse/value``.
  ///
  /// ```swift
  /// let updated: [Todo] = try await client
  ///   .from("todos")
  ///   .update(["done": true])
  ///   .eq("id", value: 1)
  ///   .select("id, task, done")
  ///   .execute()
  ///   .value
  /// ```
  ///
  /// - Parameter columns: A comma-separated list of columns to retrieve. Defaults to `"*"` (all columns).
  /// - Returns: The same builder instance so calls can be chained.
  public func select(_ columns: String = "*") -> PostgrestTransformBuilder {
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
    mutableState.withValue {
      $0.request.query.appendOrUpdate(URLQueryItem(name: "select", value: cleanedColumns))
      $0.request.headers.appendOrUpdate(.prefer, value: "return=representation")
    }
    return self
  }

  /// Sorts the query result by the specified column.
  ///
  /// Call this method multiple times to sort by multiple columns. When sorting a referenced
  /// (embedded) table, pass the table name via `referencedTable`; note that this only affects
  /// the ordering of the parent table's rows when the join uses `!inner`.
  ///
  /// ```swift
  /// // Order by created_at descending, then by id ascending
  /// .order("created_at", ascending: false)
  /// .order("id")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to sort by.
  ///   - ascending: When `true` (the default), results are sorted ascending (`ASC`).
  ///   - nullsFirst: When `true`, `NULL` values appear before non-null values. Defaults to `false`.
  ///   - referencedTable: The name of an embedded table to order by its columns. Defaults to `nil`.
  /// - Returns: The same builder instance so calls can be chained.
  public func order(
    _ column: String,
    ascending: Bool = true,
    nullsFirst: Bool = false,
    referencedTable: String? = nil
  ) -> PostgrestTransformBuilder {
    mutableState.withValue {
      let key = referencedTable.map { "\($0).order" } ?? "order"
      let existingOrderIndex = $0.request.query.firstIndex { $0.name == key }
      let value =
        "\(column).\(ascending ? "asc" : "desc").\(nullsFirst ? "nullsfirst" : "nullslast")"

      if let existingOrderIndex,
        let currentValue = $0.request.query[existingOrderIndex].value
      {
        $0.request.query[existingOrderIndex] = URLQueryItem(
          name: key,
          value: "\(currentValue),\(value)"
        )
      } else {
        $0.request.query.append(URLQueryItem(name: key, value: value))
      }
    }

    return self
  }

  /// Limits the number of rows returned by the query.
  ///
  /// - Parameters:
  ///   - count: The maximum number of rows to return.
  ///   - referencedTable: The name of an embedded table to limit instead of the parent table. Defaults to `nil`.
  /// - Returns: The same builder instance so calls can be chained.
  public func limit(_ count: Int, referencedTable: String? = nil) -> PostgrestTransformBuilder {
    mutableState.withValue {
      let key = referencedTable.map { "\($0).limit" } ?? "limit"
      $0.request.query.appendOrUpdate(URLQueryItem(name: key, value: "\(count)"))
    }
    return self
  }

  /// Returns only the rows within the specified zero-based, inclusive index range.
  ///
  /// The range is applied after any ORDER BY clause. Both `from` and `to` are inclusive, so
  /// `range(from: 0, to: 9)` returns the first 10 rows.
  ///
  /// > Important: Without an ORDER BY clause, the range may return rows in an unpredictable order.
  /// > Chain ``order(_:ascending:nullsFirst:referencedTable:)`` before ``range(from:to:referencedTable:)``
  /// > for deterministic pagination.
  ///
  /// ```swift
  /// // Second page of 10 items
  /// .order("id")
  /// .range(from: 10, to: 19)
  /// ```
  ///
  /// - Parameters:
  ///   - from: The zero-based index of the first row to return.
  ///   - to: The zero-based index of the last row to return (inclusive).
  ///   - referencedTable: The name of an embedded table to paginate instead of the parent table. Defaults to `nil`.
  /// - Returns: The same builder instance so calls can be chained.
  public func range(
    from: Int,
    to: Int,
    referencedTable: String? = nil
  ) -> PostgrestTransformBuilder {
    let keyOffset = referencedTable.map { "\($0).offset" } ?? "offset"
    let keyLimit = referencedTable.map { "\($0).limit" } ?? "limit"

    mutableState.withValue {
      $0.request.query.appendOrUpdate(URLQueryItem(name: keyOffset, value: "\(from)"))

      // Range is inclusive, so add 1
      $0.request.query.appendOrUpdate(URLQueryItem(name: keyLimit, value: "\(to - from + 1)"))
    }

    return self
  }

  /// Instructs PostgREST to return a single JSON object instead of an array.
  ///
  /// The query must return exactly one row; otherwise PostgREST returns an error. Pair this
  /// with ``limit(_:referencedTable:)`` (limit 1) or a unique filter to guarantee a single result.
  ///
  /// ```swift
  /// let todo: Todo = try await client
  ///   .from("todos")
  ///   .select()
  ///   .eq("id", value: 42)
  ///   .single()
  ///   .execute()
  ///   .value
  /// ```
  ///
  /// - Returns: The same builder instance so calls can be chained.
  public func single() -> PostgrestTransformBuilder {
    mutableState.withValue {
      $0.request.headers[.accept] = "application/vnd.pgrst.object+json"
    }
    return self
  }

  /// Sets the response format to CSV.
  ///
  /// The raw CSV text is available in ``PostgrestResponse/data``. Convert it to a `String`
  /// using ``PostgrestResponse/string(encoding:)``.
  ///
  /// > Note: ``csv()`` cannot be combined with ``stripNulls()``.
  ///
  /// - Returns: The same builder instance so calls can be chained.
  public func csv() -> PostgrestTransformBuilder {
    mutableState.withValue {
      let preferComponents = $0.request.headers[.prefer]?.components(separatedBy: ",") ?? []
      if preferComponents.contains("return=stripped-nulls") {
        $0.pendingError = "`.csv()` cannot be combined with `.stripNulls()`"
      }
      $0.request.headers[.accept] = "text/csv"
    }
    return self
  }

  /// Instructs PostgREST to omit `null` values from the JSON response.
  ///
  /// Requires PostgREST 11.2.0 or later.
  ///
  /// > Note: ``stripNulls()`` cannot be combined with ``csv()``.
  ///
  /// - Returns: The same builder instance so calls can be chained.
  public func stripNulls() -> PostgrestTransformBuilder {
    mutableState.withValue {
      if $0.request.headers[.accept] == "text/csv" {
        $0.pendingError = "`.stripNulls()` cannot be combined with `.csv()`"
      }
      $0.request.headers.appendOrUpdate(.prefer, value: "return=stripped-nulls")
    }
    return self
  }

  /// Sets the response format to [GeoJSON](https://geojson.org).
  ///
  /// Use this when querying geometry or geography columns from a PostGIS-enabled table.
  /// The response is a GeoJSON `FeatureCollection`.
  ///
  /// - Returns: The same builder instance so calls can be chained.
  public func geojson() -> PostgrestTransformBuilder {
    mutableState.withValue {
      $0.request.headers[.accept] = "application/geo+json"
    }
    return self
  }

  /// Returns the PostgreSQL EXPLAIN plan for the query instead of the query results.
  ///
  /// Use this to understand and debug query performance. You must enable the
  /// [`db_plan_enabled`](https://supabase.com/docs/guides/database/debugging-performance#enabling-explain)
  /// setting in your Supabase project before calling this method.
  ///
  /// ```swift
  /// let plan = try await client
  ///   .from("todos")
  ///   .select()
  ///   .explain(analyze: true, format: .json)
  ///   .execute()
  ///   .string()
  /// ```
  ///
  /// - Parameters:
  ///   - analyze: When `true`, the query is actually executed and actual run time statistics are included.
  ///   - verbose: When `true`, the query identifier and output column names are included.
  ///   - settings: When `true`, planner configuration parameters that affect the plan are included.
  ///   - buffers: When `true`, buffer usage statistics are included (requires `analyze: true`).
  ///   - wal: When `true`, WAL record generation statistics are included (requires `analyze: true`).
  ///   - format: The output format. See ``ExplainFormat``. Defaults to ``ExplainFormat/text``.
  /// - Returns: The same builder instance so calls can be chained.
  public func explain(
    analyze: Bool = false,
    verbose: Bool = false,
    settings: Bool = false,
    buffers: Bool = false,
    wal: Bool = false,
    format: ExplainFormat = .text
  ) -> PostgrestTransformBuilder {
    mutableState.withValue {
      let options = [
        analyze ? "analyze" : nil,
        verbose ? "verbose" : nil,
        settings ? "settings" : nil,
        buffers ? "buffers" : nil,
        wal ? "wal" : nil,
      ]
      .compactMap { $0 }
      .joined(separator: "|")
      let forMediaType = $0.request.headers[.accept] ?? "application/json"
      $0.request.headers[.accept] =
        "application/vnd.pgrst.plan+\(format.rawValue); for=\"\(forMediaType)\"; options=\(options);"
    }

    return self
  }

  /// Limits the maximum number of rows that a write operation may affect.
  ///
  /// When the number of affected rows would exceed `value`, PostgREST returns an error and
  /// rolls back the transaction. This is a safety mechanism to prevent accidental mass updates
  /// or deletes.
  ///
  /// Requires PostgREST v13 or later. Compatible with PATCH, DELETE, and RPC calls only.
  ///
  /// > Note: This method does not validate the HTTP method. Ensure you only use it with
  /// > ``PostgrestQueryBuilder/update(_:returning:count:)``,
  /// > ``PostgrestQueryBuilder/delete(returning:count:)``, or
  /// > ``PostgrestClient/rpc(_:params:head:get:count:)``.
  ///
  /// - Parameter value: The maximum number of rows that the operation may affect.
  /// - Returns: The same builder instance so calls can be chained.
  public func maxAffected(_ value: Int) -> PostgrestTransformBuilder {
    mutableState.withValue {
      $0.request.headers.appendOrUpdate(.prefer, value: "handling=strict")
      $0.request.headers.appendOrUpdate(.prefer, value: "max-affected=\(value)")
    }
    return self
  }
}
