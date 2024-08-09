import Foundation
import Helpers

public class PostgrestTransformBuilder: PostgrestBuilder, @unchecked Sendable {
  /// Perform a SELECT on the query result.
  ///
  /// By default, `.insert()`, `.update()`, `.upsert()`, and `.delete()` do not return modified rows. By calling this method, modified rows are returned in `value`.
  ///
  /// - Parameters:
  ///   - columns: The columns to retrieve, separated by commas.
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

      if let prefer = $0.request.headers["Prefer"] {
        var components = prefer.components(separatedBy: ",")

        if let index = components.firstIndex(where: { $0.hasPrefix("return=") }) {
          components[index] = "return=representation"
        } else {
          components.append("return=representation")
        }

        $0.request.headers["Prefer"] = components.joined(separator: ",")
      } else {
        $0.request.headers["Prefer"] = "return=representation"
      }
    }
    return self
  }

  /// Order the query result by `column`.
  ///
  /// You can call this method multiple times to order by multiple columns.
  /// You can order referenced tables, but it only affects the ordering of theparent table if you use `!inner` in the query.
  ///
  /// - Parameters:
  ///   - column: The column to order by.
  ///   - ascending: If `true`, the result will be in ascending order.
  ///   - nullsFirst: If `true`, `null`s appear first. If `false`, `null`s appear last.
  ///   - referencedTable: Set this to order a referenced table by its columns.
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

  /// Limits the query result by `count`.
  /// - Parameters:
  ///   - count: The maximum number of rows to return.
  ///   - referencedTable: Set this to limit rows of referenced tables instead of the parent table.
  public func limit(_ count: Int, referencedTable: String? = nil) -> PostgrestTransformBuilder {
    mutableState.withValue {
      let key = referencedTable.map { "\($0).limit" } ?? "limit"
      if let index = $0.request.query.firstIndex(where: { $0.name == key }) {
        $0.request.query[index] = URLQueryItem(name: key, value: "\(count)")
      } else {
        $0.request.query.append(URLQueryItem(name: key, value: "\(count)"))
      }
    }
    return self
  }

  /// Limit the query result by starting at an offset (`from`) and ending at the offset (`from + to`).
  ///
  /// Only records within this range are returned.
  /// This respects the query order and if there is no order clause the range could behave unexpectedly.
  /// The `from` and `to` values are 0-based and inclusive: `range(from: 1, to: 3)` will include the second, third and fourth rows of the query.
  ///
  /// - Parameters:
  ///   - from: The starting index from which to limit the result.
  ///   - to: The last index to which to limit the result.
  ///   - referencedTable: Set this to limit rows of referenced tables instead of the parent table.
  public func range(
    from: Int,
    to: Int,
    referencedTable: String? = nil
  ) -> PostgrestTransformBuilder {
    let keyOffset = referencedTable.map { "\($0).offset" } ?? "offset"
    let keyLimit = referencedTable.map { "\($0).limit" } ?? "limit"

    mutableState.withValue {
      if let index = $0.request.query.firstIndex(where: { $0.name == keyOffset }) {
        $0.request.query[index] = URLQueryItem(name: keyOffset, value: "\(from)")
      } else {
        $0.request.query.append(URLQueryItem(name: keyOffset, value: "\(from)"))
      }

      // Range is inclusive, so add 1
      if let index = $0.request.query.firstIndex(where: { $0.name == keyLimit }) {
        $0.request.query[index] = URLQueryItem(
          name: keyLimit,
          value: "\(to - from + 1)"
        )
      } else {
        $0.request.query.append(URLQueryItem(
          name: keyLimit,
          value: "\(to - from + 1)"
        ))
      }
    }

    return self
  }

  /// Return `value` as a single object instead of an array of objects.
  ///
  /// Query result must be one row (e.g. using `.limit(1)`), otherwise this returns an error.
  public func single() -> PostgrestTransformBuilder {
    mutableState.withValue {
      $0.request.headers["Accept"] = "application/vnd.pgrst.object+json"
    }
    return self
  }

  ///  Return `value` as a string in CSV format.
  public func csv() -> PostgrestTransformBuilder {
    mutableState.withValue {
      $0.request.headers["Accept"] = "text/csv"
    }
    return self
  }

  /// Return `value` as an object in [GeoJSON](https://geojson.org) format.
  public func geojson() -> PostgrestTransformBuilder {
    mutableState.withValue {
      $0.request.headers["Accept"] = "application/geo+json"
    }
    return self
  }

  /// Return `data` as the EXPLAIN plan for the query.
  ///
  /// You need to enable the [db_plan_enabled](https://supabase.com/docs/guides/database/debugging-performance#enabling-explain)
  /// setting before using this method.
  ///
  /// - Parameters:
  ///   - analyze: If `true`, the query will be executed and the actual run time will be returned
  ///   - verbose: If `true`, the query identifier will be returned and `data` will include the
  /// output columns of the query
  ///   - settings: If `true`, include information on configuration parameters that affect query
  /// planning
  ///   - buffers: If `true`, include information on buffer usage
  ///   - wal: If `true`, include information on WAL record generation
  ///   - format: The format of the output, can be `"text"` (default) or `"json"`
  public func explain(
    analyze: Bool = false,
    verbose: Bool = false,
    settings: Bool = false,
    buffers: Bool = false,
    wal: Bool = false,
    format: String = "text"
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
      let forMediaType = $0.request.headers["Accept"] ?? "application/json"
      $0.request
        .headers["Accept"] =
        "application/vnd.pgrst.plan+\"\(format)\"; for=\(forMediaType); options=\(options);"
    }

    return self
  }
}
