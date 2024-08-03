import Foundation
import Helpers

public class PostgrestFilterBuilder: PostgrestTransformBuilder, @unchecked Sendable {
  public enum Operator: String, CaseIterable, Sendable {
    case eq, neq, gt, gte, lt, lte, like, ilike, `is`, `in`, cs, cd, sl, sr, nxl, nxr, adj, ov, fts,
         plfts, phfts, wfts
  }

  // MARK: - Filters

  public func not(
    _ column: String,
    operator op: Operator,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue

    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "not.\(op.rawValue).\(queryValue)"
      ))
    }

    return self
  }

  public func or(
    _ filters: any URLQueryRepresentable,
    referencedTable: String? = nil
  ) -> PostgrestFilterBuilder {
    let key = referencedTable.map { "\($0).or" } ?? "or"
    let queryValue = filters.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: key, value: "(\(queryValue))"))
    }
    return self
  }

  /// Match only rows where `column` is equal to `value`.
  ///
  /// To check if the value of `column` is NULL, you should use `is()` instead.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - value: The value to filter with
  public func eq(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "eq.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` is not equal to `value`.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - value: The value to filter with
  public func neq(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "neq.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` is greater than `value`.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - value: The value to filter with
  public func gt(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "gt.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` is greater than or equal to `value`.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - value: The value to filter with
  public func gte(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "gte.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` is less than `value`.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - value: The value to filter with
  public func lt(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "lt.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` is less than or equal to `value`.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - value: The value to filter with
  public func lte(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "lte.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` matches `pattern` case-sensitively.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - pattern: The pattern to match with
  public func like(
    _ column: String,
    pattern: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = pattern.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "like.\(queryValue)"))
    }
    return self
  }

  @available(*, deprecated, renamed: "like(_:pattern:)")
  public func like(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    like(column, pattern: value)
  }

  /// Match only rows where `column` matches all of `patterns` case-sensitively.
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - patterns: The patterns to match with
  public func likeAllOf(
    _ column: String,
    patterns: [some URLQueryRepresentable]
  ) -> PostgrestFilterBuilder {
    let queryValue = patterns.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "like(all).\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` matches any of `patterns` case-sensitively.
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - patterns: The patterns to match with
  public func likeAnyOf(
    _ column: String,
    patterns: [some URLQueryRepresentable]
  ) -> PostgrestFilterBuilder {
    let queryValue = patterns.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "like(any).\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` matches `pattern` case-insensitively.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - pattern: The pattern to match with
  public func ilike(
    _ column: String,
    pattern: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = pattern.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ilike.\(queryValue)"))
    }
    return self
  }

  @available(*, deprecated, renamed: "ilike(_:pattern:)")
  public func ilike(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    ilike(column, pattern: value)
  }

  /// Match only rows where `column` matches all of `patterns` case-insensitively.
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - patterns: The patterns to match with
  public func iLikeAllOf(
    _ column: String,
    patterns: [some URLQueryRepresentable]
  ) -> PostgrestFilterBuilder {
    let queryValue = patterns.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ilike(all).\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` matches any of `patterns` case-insensitively.
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - patterns: The patterns to match with
  public func iLikeAnyOf(
    _ column: String,
    patterns: [some URLQueryRepresentable]
  ) -> PostgrestFilterBuilder {
    let queryValue = patterns.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ilike(any).\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` IS `value`.
  ///
  /// For non-boolean columns, this is only relevant for checking if the value of `column` is NULL by setting `value` to `null`.
  /// For boolean columns, you can also set `value` to `true` or `false` and it will behave the same way as `.eq()`.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - value: The value to filter with
  public func `is`(
    _ column: String,
    value: Bool?
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "is.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` is included in the `values` array.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - value: The values array to filter with
  public func `in`(
    _ column: String,
    values: [any URLQueryRepresentable]
  ) -> PostgrestFilterBuilder {
    let queryValues = values.map(\.queryValue)
    mutableState.withValue {
      $0.request.query.append(
        URLQueryItem(
          name: column,
          value: "in.(\(queryValues.joined(separator: ",")))"
        )
      )
    }
    return self
  }

  @available(*, deprecated, renamed: "in(_:values:)")
  public func `in`(
    _ column: String,
    value: [any URLQueryRepresentable]
  ) -> PostgrestFilterBuilder {
    `in`(column, values: value)
  }

  /// Match only rows where `column` contains every element appearing in `value`.
  ///
  /// Only relevant for jsonb, array, and range columns.
  ///
  /// - Parameters:
  ///   - column: The jsonb, array, or range column to filter on
  ///   - value: The jsonb, array, or range value to filter with
  public func contains(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "cs.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where every element appearing in `column` is contained by `value`.
  ///
  /// Only relevant for jsonb, array, and range columns.
  ///
  /// - Parameters:
  ///   - column: The jsonb, array, or range column to filter on
  ///   - value: The jsonb, array, or range value to filter with
  public func containedBy(
    _ column: String,
    value: some URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "cd.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where every element in `column` is less than any element in `range`.
  ///
  /// Only relevant for range columns.
  ///
  /// - Parameters:
  ///   - column: The range column to filter on
  ///   - range: The range to filter with
  public func rangeLt(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "sl.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where every element in `column` is greater than any element in `range`.
  ///
  /// Only relevant for range columns.
  ///
  /// - Parameters:
  ///   - column: The range column to filter on
  ///   - range: The range to filter with
  public func rangeGt(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "sr.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where every element in `column` is either contained in `range` or greater than any element in `range`.
  ///
  /// Only relevant for range columns.
  ///
  /// - Parameters:
  ///   - column: The range column to filter on
  ///   - range: The range to filter with
  public func rangeGte(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "nxl.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where every element in `column` is either contained in `range` or less than any element in `range`.
  ///
  /// Only relevant for range columns.
  ///
  /// - Parameters:
  ///   - column: The range column to filter on
  ///   - range: The range to filter with
  public func rangeLte(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "nxr.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` is mutually exclusive to `range` and there can be no element between the two ranges.
  ///
  /// Only relevant for range columns.
  ///
  /// - Parameters:
  ///   - column: The range column to filter on
  ///   - range: The range to filter with
  public func rangeAdjacent(
    _ column: String,
    range: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = range.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "adj.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` and `value` have an element in common.
  ///
  /// Only relevant for array and range columns.
  ///
  /// - Parameters:
  ///   - column: The array or range column to filter on
  ///   - value: The array or range value to filter with
  public func overlaps(
    _ column: String,
    value: any URLQueryRepresentable
  ) -> PostgrestFilterBuilder {
    let queryValue = value.queryValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ov.\(queryValue)"))
    }
    return self
  }

  /// Match only rows where `column` matches the query string in `query`.
  ///
  /// Only relevant for text and tsvector columns.
  ///
  /// - Parameters:
  ///   - column: The text or tsvector column to filter on
  ///   - query: The query text to match with
  ///   - config: The text search configuration to use
  ///   - type: Change how the `query` text is interpreted
  public func textSearch(
    _ column: String,
    query: any URLQueryRepresentable,
    config: String? = nil,
    type: TextSearchType? = nil
  ) -> PostgrestFilterBuilder {
    let queryValue = query.queryValue
    let configPart = config.map { "(\($0))" }

    mutableState.withValue {
      $0.request.query.append(
        URLQueryItem(
          name: column, value: "\(type?.rawValue ?? "")fts\(configPart ?? "").\(queryValue)"
        )
      )
    }
    return self
  }

  public func fts(
    _ column: String,
    query: any URLQueryRepresentable,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    textSearch(column, query: query, config: config, type: nil)
  }

  /// Match only rows which satisfy the filter. This is an escape hatch - you should use the specific filter methods wherever possible.
  ///
  /// Unlike most filters, `opearator` and `value` are used as-is and need to follow [PostgREST syntax](https://postgrest.org/en/stable/api.html#operators). You also need to make sure they are properly sanitized.
  ///
  /// - Parameters:
  ///   - column: The column to filter on
  ///   - operator: The operator to filter with, following PostgREST syntax
  ///   - value: The value to filter with, following PostgREST syntax
  public func filter(
    _ column: String,
    operator: String,
    value: String
  ) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(
        name: column,
        value: "\(`operator`).\(value)"
      ))
    }
    return self
  }

  /// Match only rows where each column in `query` keys is equal to its associated value. Shorthand for multiple `.eq()`s.
  ///
  /// - Parameter query: The object to filter with, with column names as keys mapped to their filter values
  public func match(
    _ query: [String: any URLQueryRepresentable]
  ) -> PostgrestFilterBuilder {
    let query = query.mapValues(\.queryValue)
    mutableState.withValue { mutableState in
      for (key, value) in query {
        mutableState.request.query.append(URLQueryItem(
          name: key,
          value: "eq.\(value.queryValue)"
        ))
      }
    }
    return self
  }

  // MARK: - Filter Semantic Improvements

  public func equals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    eq(column, value: value)
  }

  public func notEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    neq(column, value: value)
  }

  public func greaterThan(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    gt(column, value: value)
  }

  public func greaterThanOrEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    gte(column, value: value)
  }

  public func lowerThan(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    lt(column, value: value)
  }

  public func lowerThanOrEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    lte(column, value: value)
  }

  public func rangeLowerThan(
    _ column: String,
    range: String
  ) -> PostgrestFilterBuilder {
    rangeLt(column, range: range)
  }

  public func rangeGreaterThan(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    rangeGt(column, range: value)
  }

  public func rangeGreaterThanOrEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    rangeGte(column, range: value)
  }

  public func rangeLowerThanOrEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    rangeLte(column, range: value)
  }

  public func fullTextSearch(
    _ column: String,
    query: String,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    fts(column, query: query, config: config)
  }
}
