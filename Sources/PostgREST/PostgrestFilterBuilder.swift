import ConcurrencyExtras
import Foundation
import Helpers

/// Builder for applying WHERE-clause filters to a PostgREST query.
///
/// Obtain a ``PostgrestFilterBuilder`` from ``PostgrestQueryBuilder/select(_:head:count:)``,
/// ``PostgrestQueryBuilder/insert(_:returning:count:)``, ``PostgrestQueryBuilder/update(_:returning:count:)``,
/// or other write methods. Chain one or more filter methods, then call
/// ``PostgrestBuilder/execute(options:)-96tpd`` to send the request.
///
/// All filter methods return `self` so they can be freely chained:
///
/// ```swift
/// let results: [Todo] = try await client
///   .from("todos")
///   .select()
///   .eq("done", value: false)
///   .order("created_at", ascending: false)
///   .limit(20)
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
/// ### Equality Filters
///
/// - ``eq(_:value:)``
/// - ``neq(_:value:)``
/// - ``is(_:value:)``
/// - ``isDistinct(_:value:)``
/// - ``in(_:values:)``
/// - ``notIn(_:values:)``
/// - ``match(_:)-6h9ou``
///
/// ### Comparison Filters
///
/// - ``gt(_:value:)``
/// - ``gte(_:value:)``
/// - ``lt(_:value:)``
/// - ``lte(_:value:)``
///
/// ### Pattern Matching Filters
///
/// - ``like(_:pattern:)``
/// - ``likeAllOf(_:patterns:)``
/// - ``likeAnyOf(_:patterns:)``
/// - ``ilike(_:pattern:)``
/// - ``iLikeAllOf(_:patterns:)``
/// - ``iLikeAnyOf(_:patterns:)``
/// - ``match(_:pattern:)-9qlv5``
/// - ``imatch(_:pattern:)``
///
/// ### Array and Range Filters
///
/// - ``contains(_:value:)``
/// - ``containedBy(_:value:)``
/// - ``overlaps(_:value:)``
/// - ``rangeLt(_:range:)``
/// - ``rangeGt(_:range:)``
/// - ``rangeGte(_:range:)``
/// - ``rangeLte(_:range:)``
/// - ``rangeAdjacent(_:range:)``
///
/// ### Full-Text Search
///
/// - ``textSearch(_:query:config:type:)``
/// - ``fts(_:query:config:)``
///
/// ### Logical Operators
///
/// - ``not(_:operator:value:)``
/// - ``or(_:referencedTable:)``
/// - ``filter(_:operator:value:)``
///
/// ### Operators
///
/// - ``Operator``
public class PostgrestFilterBuilder: PostgrestTransformBuilder, @unchecked Sendable {
  /// The set of PostgREST comparison operators available for use with ``not(_:operator:value:)``
  /// and ``filter(_:operator:value:)``.
  ///
  /// Most operators have dedicated convenience methods (e.g., ``eq(_:value:)``, ``gt(_:value:)``).
  /// Use ``Operator`` directly only when you need ``not(_:operator:value:)`` or the raw
  /// ``filter(_:operator:value:)`` escape hatch.
  public enum Operator: String, CaseIterable, Sendable {
    /// Equals (`=`).
    case eq
    /// Not equals (`!=`).
    case neq
    /// Greater than (`>`).
    case gt
    /// Greater than or equal (`>=`).
    case gte
    /// Less than (`<`).
    case lt
    /// Less than or equal (`<=`).
    case lte
    /// Case-sensitive LIKE pattern match.
    case like
    /// Case-insensitive ILIKE pattern match.
    case ilike
    /// Case-sensitive regex match.
    case match
    /// Case-insensitive regex match.
    case imatch
    /// IS (for NULL / boolean checks).
    case `is`
    /// IS DISTINCT FROM.
    case isdistinct
    /// IN — value is in a list.
    case `in`
    /// Contains (`@>`).
    case cs
    /// Contained by (`<@`).
    case cd
    /// Range strictly left of (`<<`).
    case sl
    /// Range strictly right of (`>>`).
    case sr
    /// Range does not extend to the left (`&>`).
    case nxl
    /// Range does not extend to the right (`&<`).
    case nxr
    /// Range is adjacent (`-|-`).
    case adj
    /// Overlaps (`&&`).
    case ov
    /// Full-text search using `to_tsquery`.
    case fts
    /// Full-text search using `plainto_tsquery`.
    case plfts
    /// Full-text search using `phraseto_tsquery`.
    case phfts
    /// Full-text search using `websearch_to_tsquery`.
    case wfts
  }

  // MARK: - Filters

  /// Negates the specified filter using the PostgREST `not.<operator>` syntax.
  ///
  /// Use this to invert any of the standard comparison operators defined in ``Operator``.
  ///
  /// ```swift
  /// // Rows where status is NOT 'active'
  /// .not("status", operator: .eq, value: "active")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - op: The ``Operator`` to negate.
  ///   - value: The filter value.
  /// - Returns: The same builder instance so calls can be chained.
  public func not(
    _ column: String,
    operator op: Operator,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue

    mutableState.withValue {
      $0.request.query.append(
        URLQueryItem(
          name: column,
          value: "not.\(op.rawValue).\(queryValue)"
        ))
    }

    return self
  }

  /// Combines multiple filters with an OR condition.
  ///
  /// The `filters` value must be a raw PostgREST filter string, for example
  /// `"done.eq.true,priority.gt.3"`. To target an embedded (referenced) table, pass its
  /// name via `referencedTable`.
  ///
  /// ```swift
  /// // Rows where done is true OR priority > 3
  /// .or("done.eq.true,priority.gt.3")
  /// ```
  ///
  /// - Parameters:
  ///   - filters: A comma-separated list of PostgREST filter expressions combined with OR logic.
  ///   - referencedTable: The name of an embedded table to apply the OR filter on. Defaults to `nil`.
  /// - Returns: The same builder instance so calls can be chained.
  public func or(
    _ filters: any PostgrestFilterValue,
    referencedTable: String? = nil
  ) -> PostgrestFilterBuilder {
    let key = referencedTable.map { "\($0).or" } ?? "or"
    let queryValue = filters.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: key, value: "(\(queryValue))"))
    }
    return self
  }

  /// Matches only rows where `column` equals `value`.
  ///
  /// To test for NULL, use ``is(_:value:)`` instead — `NULL = NULL` is false in SQL.
  ///
  /// ```swift
  /// // Rows where status equals "active"
  /// .eq("status", value: "active")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func eq(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "eq.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` is not equal to `value`.
  ///
  /// ```swift
  /// // Rows where status is not "inactive"
  /// .neq("status", value: "inactive")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func neq(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "neq.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` is greater than `value`.
  ///
  /// ```swift
  /// // Rows where score is greater than 100
  /// .gt("score", value: 100)
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func gt(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "gt.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` is greater than or equal to `value`.
  ///
  /// ```swift
  /// // Rows where score is at least 100
  /// .gte("score", value: 100)
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func gte(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "gte.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` is less than `value`.
  ///
  /// ```swift
  /// // Rows where age is under 18
  /// .lt("age", value: 18)
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func lt(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "lt.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` is less than or equal to `value`.
  ///
  /// ```swift
  /// // Rows where age is 18 or under
  /// .lte("age", value: 18)
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func lte(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "lte.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` matches `pattern` case-sensitively using SQL LIKE.
  ///
  /// Use `%` as a wildcard for any sequence of characters and `_` for a single character.
  ///
  /// ```swift
  /// // Rows where name starts with "Jo"
  /// .like("name", pattern: "Jo%")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - pattern: The LIKE pattern to match against.
  /// - Returns: The same builder instance so calls can be chained.
  public func like(
    _ column: String,
    pattern: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = pattern.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "like.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` matches **all** of the supplied LIKE `patterns` case-sensitively.
  ///
  /// ```swift
  /// // Rows where name starts with "J" and ends with "n"
  /// .likeAllOf("name", patterns: ["J%", "%n"])
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - patterns: The LIKE patterns that must all match.
  /// - Returns: The same builder instance so calls can be chained.
  public func likeAllOf(
    _ column: String,
    patterns: [some PostgrestFilterValue]
  ) -> PostgrestFilterBuilder {
    let queryValue = patterns.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "like(all).\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` matches **any** of the supplied LIKE `patterns` case-sensitively.
  ///
  /// ```swift
  /// // Rows where name starts with "Jo" or "Ma"
  /// .likeAnyOf("name", patterns: ["Jo%", "Ma%"])
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - patterns: The LIKE patterns, at least one of which must match.
  /// - Returns: The same builder instance so calls can be chained.
  public func likeAnyOf(
    _ column: String,
    patterns: [some PostgrestFilterValue]
  ) -> PostgrestFilterBuilder {
    let queryValue = patterns.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "like(any).\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` matches `pattern` case-insensitively using SQL ILIKE.
  ///
  /// Use `%` as a wildcard for any sequence of characters and `_` for a single character.
  ///
  /// ```swift
  /// // Rows where name starts with "jo" (case-insensitive)
  /// .ilike("name", pattern: "jo%")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - pattern: The ILIKE pattern to match against.
  /// - Returns: The same builder instance so calls can be chained.
  public func ilike(
    _ column: String,
    pattern: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = pattern.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ilike.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` matches **all** of the supplied ILIKE `patterns` case-insensitively.
  ///
  /// ```swift
  /// // Rows where name starts with "j" and ends with "n" (case-insensitive)
  /// .iLikeAllOf("name", patterns: ["j%", "%n"])
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - patterns: The ILIKE patterns that must all match.
  /// - Returns: The same builder instance so calls can be chained.
  public func iLikeAllOf(
    _ column: String,
    patterns: [some PostgrestFilterValue]
  ) -> PostgrestFilterBuilder {
    let queryValue = patterns.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ilike(all).\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` matches **any** of the supplied ILIKE `patterns` case-insensitively.
  ///
  /// ```swift
  /// // Rows where name starts with "jo" or "ma" (case-insensitive)
  /// .iLikeAnyOf("name", patterns: ["jo%", "ma%"])
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - patterns: The ILIKE patterns, at least one of which must match.
  /// - Returns: The same builder instance so calls can be chained.
  public func iLikeAnyOf(
    _ column: String,
    patterns: [some PostgrestFilterValue]
  ) -> PostgrestFilterBuilder {
    let queryValue = patterns.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ilike(any).\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` matches the regular expression `pattern` case-sensitively.
  ///
  /// Uses PostgreSQL's `~` operator. The pattern must be a valid POSIX regular expression.
  ///
  /// ```swift
  /// // Rows where email ends with "@supabase.io"
  /// .match("email", pattern: "@supabase\\.io$")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - pattern: The POSIX regular expression to match against.
  /// - Returns: The same builder instance so calls can be chained.
  public func match(
    _ column: String,
    pattern: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = pattern.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "match.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` matches the regular expression `pattern` case-insensitively.
  ///
  /// Uses PostgreSQL's `~*` operator. The pattern must be a valid POSIX regular expression.
  ///
  /// ```swift
  /// // Rows where email ends with "@supabase.io" (case-insensitive)
  /// .imatch("email", pattern: "@supabase\\.io$")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - pattern: The POSIX regular expression to match against.
  /// - Returns: The same builder instance so calls can be chained.
  public func imatch(
    _ column: String,
    pattern: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = pattern.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "imatch.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` IS `value`.
  ///
  /// Use this filter to check for `NULL` or boolean values. Unlike ``eq(_:value:)``, this filter
  /// correctly handles `NULL` comparisons because it uses the SQL `IS` operator rather than `=`.
  ///
  /// ```swift
  /// // Rows where deleted_at IS NULL
  /// .is("deleted_at", value: nil)
  ///
  /// // Rows where active IS TRUE
  /// .is("active", value: true)
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: `true`, `false`, or `nil` (for NULL).
  /// - Returns: The same builder instance so calls can be chained.
  public func `is`(
    _ column: String,
    value: Bool?
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "is.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` IS DISTINCT FROM `value`.
  ///
  /// Unlike ``neq(_:value:)``, this operator treats `NULL` as a comparable value: `NULL IS DISTINCT
  /// FROM NULL` evaluates to `false`, whereas `NULL != NULL` evaluates to `true` (unknown).
  ///
  /// ```swift
  /// // Rows where deleted_at IS DISTINCT FROM NULL (i.e. has a value)
  /// .isDistinct("deleted_at", value: "null")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against using IS DISTINCT FROM.
  /// - Returns: The same builder instance so calls can be chained.
  public func isDistinct(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "isdistinct.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` is one of the values in `values`.
  ///
  /// Equivalent to a SQL `IN (...)` clause.
  ///
  /// ```swift
  /// // Rows where status is "active" or "pending"
  /// .in("status", values: ["active", "pending"])
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - values: The list of acceptable values.
  /// - Returns: The same builder instance so calls can be chained.
  public func `in`(
    _ column: String,
    values: [any PostgrestFilterValue]
  ) -> PostgrestFilterBuilder {
    let queryValues = values.map { escapePostgRESTFilterValue($0.rawValue) }
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

  /// Matches only rows where `column` is not one of the values in `values`.
  ///
  /// The negation of ``in(_:values:)``.
  ///
  /// ```swift
  /// // Rows where status is NOT "archived" or "deleted"
  /// .notIn("status", values: ["archived", "deleted"])
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - values: The list of values to exclude.
  /// - Returns: The same builder instance so calls can be chained.
  public func notIn(
    _ column: String,
    values: [any PostgrestFilterValue]
  ) -> PostgrestFilterBuilder {
    let queryValues = values.map { escapePostgRESTFilterValue($0.rawValue) }
    mutableState.withValue {
      $0.request.query.append(
        URLQueryItem(
          name: column,
          value: "not.in.(\(queryValues.joined(separator: ",")))"
        )
      )
    }
    return self
  }

  /// Matches only rows where `column` contains every element in `value`.
  ///
  /// Applies the `@>` containment operator. Only relevant for `jsonb`, array, and range columns.
  ///
  /// ```swift
  /// // Rows where the tags array contains both "swift" and "ios"
  /// .contains("tags", value: ["swift", "ios"])
  /// ```
  ///
  /// - Parameters:
  ///   - column: The `jsonb`, array, or range column to filter on.
  ///   - value: The `jsonb`, array, or range value that `column` must contain.
  /// - Returns: The same builder instance so calls can be chained.
  public func contains(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "cs.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` is contained by `value`.
  ///
  /// Applies the `<@` containment operator. Only relevant for `jsonb`, array, and range columns.
  ///
  /// ```swift
  /// // Rows where the tags array is a subset of ["swift", "ios", "macos"]
  /// .containedBy("tags", value: ["swift", "ios", "macos"])
  /// ```
  ///
  /// - Parameters:
  ///   - column: The `jsonb`, array, or range column to filter on.
  ///   - value: The `jsonb`, array, or range value that must contain every element in `column`.
  /// - Returns: The same builder instance so calls can be chained.
  public func containedBy(
    _ column: String,
    value: some PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "cd.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where every element in `column` is strictly less than every element in `range`.
  ///
  /// Applies the `<<` (strictly left of) range operator. Only relevant for range columns.
  ///
  /// ```swift
  /// // Rows where the scheduled range is entirely before [2024-01-01, 2024-06-01)
  /// .rangeLt("scheduled", range: "[2024-01-01,2024-06-01)")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The range column to filter on.
  ///   - range: The range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func rangeLt(
    _ column: String,
    range: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = range.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "sl.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where every element in `column` is strictly greater than every element in `range`.
  ///
  /// Applies the `>>` (strictly right of) range operator. Only relevant for range columns.
  ///
  /// ```swift
  /// // Rows where the scheduled range is entirely after [2024-01-01, 2024-06-01)
  /// .rangeGt("scheduled", range: "[2024-01-01,2024-06-01)")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The range column to filter on.
  ///   - range: The range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func rangeGt(
    _ column: String,
    range: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = range.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "sr.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` does not extend to the left of `range`.
  ///
  /// Applies the `&>` (does not extend to left) range operator. Only relevant for range columns.
  ///
  /// ```swift
  /// // Rows where the scheduled range does not extend before 2024-01-01
  /// .rangeGte("scheduled", range: "[2024-01-01,)")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The range column to filter on.
  ///   - range: The range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func rangeGte(
    _ column: String,
    range: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = range.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "nxl.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` does not extend to the right of `range`.
  ///
  /// Applies the `&<` (does not extend to right) range operator. Only relevant for range columns.
  ///
  /// ```swift
  /// // Rows where the scheduled range does not extend past 2024-12-31
  /// .rangeLte("scheduled", range: "[,2024-12-31]")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The range column to filter on.
  ///   - range: The range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func rangeLte(
    _ column: String,
    range: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = range.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "nxr.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` and `range` are adjacent (no gap between them).
  ///
  /// Applies the `-|-` (adjacent to) range operator. There must be no element that lies between
  /// the two ranges. Only relevant for range columns.
  ///
  /// ```swift
  /// // Rows where the scheduled range is adjacent to [2024-01-01, 2024-06-01)
  /// .rangeAdjacent("scheduled", range: "[2024-01-01,2024-06-01)")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The range column to filter on.
  ///   - range: The range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func rangeAdjacent(
    _ column: String,
    range: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = range.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "adj.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` and `value` share at least one element.
  ///
  /// Applies the `&&` overlap operator. Only relevant for array and range columns.
  ///
  /// ```swift
  /// // Rows where the tags array overlaps with ["swift", "ios"]
  /// .overlaps("tags", value: ["swift", "ios"])
  /// ```
  ///
  /// - Parameters:
  ///   - column: The array or range column to filter on.
  ///   - value: The array or range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func overlaps(
    _ column: String,
    value: any PostgrestFilterValue
  ) -> PostgrestFilterBuilder {
    let queryValue = value.rawValue
    mutableState.withValue {
      $0.request.query.append(URLQueryItem(name: column, value: "ov.\(queryValue)"))
    }
    return self
  }

  /// Matches only rows where `column` matches the full-text search `query`.
  ///
  /// Only relevant for `text` and `tsvector` columns. The `config` parameter selects the
  /// text search configuration (dictionary) to use; omit it to use the database default.
  /// The `type` parameter controls how the query text is converted to a `tsquery` expression.
  ///
  /// ```swift
  /// // Basic full-text search
  /// .textSearch("content", query: "swift programming")
  ///
  /// // Web-search syntax with a specific language configuration
  /// .textSearch("content", query: "swift OR ios", config: "english", type: .websearch)
  /// ```
  ///
  /// - Parameters:
  ///   - column: The `text` or `tsvector` column to search.
  ///   - query: The search query text.
  ///   - config: The text search configuration name (e.g., `"english"`). Defaults to `nil`.
  ///   - type: The query conversion strategy. See ``TextSearchType``. Defaults to `nil` (uses `to_tsquery`).
  /// - Returns: The same builder instance so calls can be chained.
  public func textSearch(
    _ column: String,
    query: any PostgrestFilterValue,
    config: String? = nil,
    type: TextSearchType? = nil
  ) -> PostgrestFilterBuilder {
    let queryValue = query.rawValue
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

  /// Matches only rows where `column` matches the full-text search `query` using `to_tsquery`.
  ///
  /// This is a convenience wrapper around ``textSearch(_:query:config:type:)`` with no ``TextSearchType``.
  ///
  /// ```swift
  /// // Rows where content matches the full-text query "swift & programming"
  /// .fts("content", query: "swift & programming", config: "english")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The `text` or `tsvector` column to search.
  ///   - query: The search query text.
  ///   - config: The text search configuration name. Defaults to `nil`.
  /// - Returns: The same builder instance so calls can be chained.
  public func fts(
    _ column: String,
    query: any PostgrestFilterValue,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    textSearch(column, query: query, config: config, type: nil)
  }

  /// Matches only rows that satisfy a raw PostgREST filter expression.
  ///
  /// This is an escape hatch for filters not covered by the typed convenience methods. The
  /// `operator` and `value` strings are sent to PostgREST as-is and must follow
  /// [PostgREST syntax](https://postgrest.org/en/stable/api.html#operators). You are responsible
  /// for sanitizing user-supplied values to prevent injection.
  ///
  /// ```swift
  /// // Equivalent to .eq("status", value: "active")
  /// .filter("status", operator: "eq", value: "active")
  /// ```
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - operator: The PostgREST operator string (e.g., `"eq"`, `"gt"`, `"cs"`).
  ///   - value: The filter value string, already formatted for PostgREST.
  /// - Returns: The same builder instance so calls can be chained.
  public func filter(
    _ column: String,
    operator: String,
    value: String
  ) -> PostgrestFilterBuilder {
    mutableState.withValue {
      $0.request.query.append(
        URLQueryItem(
          name: column,
          value: "\(`operator`).\(value)"
        ))
    }
    return self
  }

  /// Matches only rows where each key in `query` equals its associated value.
  ///
  /// This is shorthand for chaining multiple ``eq(_:value:)`` calls with AND logic.
  ///
  /// ```swift
  /// // Rows where done is false AND priority is 1
  /// .match(["done": false, "priority": 1])
  /// ```
  ///
  /// - Parameter query: A dictionary mapping column names to filter values.
  /// - Returns: The same builder instance so calls can be chained.
  public func match(
    _ query: [String: any PostgrestFilterValue]
  ) -> PostgrestFilterBuilder {
    let query = query.mapValues(\.rawValue)
    mutableState.withValue { mutableState in
      for (key, value) in query {
        mutableState.request.query.append(
          URLQueryItem(
            name: key,
            value: "eq.\(value.rawValue)"
          ))
      }
    }
    return self
  }

  // MARK: - Filter Semantic Improvements

  /// Matches only rows where `column` equals `value`.
  ///
  /// This is a semantic alias for ``eq(_:value:)``.
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func equals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    eq(column, value: value)
  }

  /// Matches only rows where `column` is not equal to `value`.
  ///
  /// This is a semantic alias for ``neq(_:value:)``.
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func notEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    neq(column, value: value)
  }

  /// Matches only rows where `column` is greater than `value`.
  ///
  /// This is a semantic alias for ``gt(_:value:)``.
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func greaterThan(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    gt(column, value: value)
  }

  /// Matches only rows where `column` is greater than or equal to `value`.
  ///
  /// This is a semantic alias for ``gte(_:value:)``.
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func greaterThanOrEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    gte(column, value: value)
  }

  /// Matches only rows where `column` is less than `value`.
  ///
  /// This is a semantic alias for ``lt(_:value:)``.
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func lowerThan(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    lt(column, value: value)
  }

  /// Matches only rows where `column` is less than or equal to `value`.
  ///
  /// This is a semantic alias for ``lte(_:value:)``.
  ///
  /// - Parameters:
  ///   - column: The column to filter on.
  ///   - value: The value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func lowerThanOrEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    lte(column, value: value)
  }

  /// Matches only rows where `column` is strictly less than `range`.
  ///
  /// This is a semantic alias for ``rangeLt(_:range:)``.
  ///
  /// - Parameters:
  ///   - column: The range column to filter on.
  ///   - range: The range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func rangeLowerThan(
    _ column: String,
    range: String
  ) -> PostgrestFilterBuilder {
    rangeLt(column, range: range)
  }

  /// Matches only rows where `column` is strictly greater than `value`.
  ///
  /// This is a semantic alias for ``rangeGt(_:range:)``.
  ///
  /// - Parameters:
  ///   - column: The range column to filter on.
  ///   - value: The range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func rangeGreaterThan(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    rangeGt(column, range: value)
  }

  /// Matches only rows where `column` does not extend to the left of `value`.
  ///
  /// This is a semantic alias for ``rangeGte(_:range:)``.
  ///
  /// - Parameters:
  ///   - column: The range column to filter on.
  ///   - value: The range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func rangeGreaterThanOrEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    rangeGte(column, range: value)
  }

  /// Matches only rows where `column` does not extend to the right of `value`.
  ///
  /// This is a semantic alias for ``rangeLte(_:range:)``.
  ///
  /// - Parameters:
  ///   - column: The range column to filter on.
  ///   - value: The range value to compare against.
  /// - Returns: The same builder instance so calls can be chained.
  public func rangeLowerThanOrEquals(
    _ column: String,
    value: String
  ) -> PostgrestFilterBuilder {
    rangeLte(column, range: value)
  }

  /// Matches only rows where `column` matches the full-text search `query` using `to_tsquery`.
  ///
  /// This is a semantic alias for ``fts(_:query:config:)``.
  ///
  /// - Parameters:
  ///   - column: The `text` or `tsvector` column to search.
  ///   - query: The search query text.
  ///   - config: The text search configuration name. Defaults to `nil`.
  /// - Returns: The same builder instance so calls can be chained.
  public func fullTextSearch(
    _ column: String,
    query: String,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    fts(column, query: query, config: config)
  }

  /// Matches only rows where `column` matches the full-text search `query` using `plainto_tsquery`.
  ///
  /// This is a semantic alias for ``textSearch(_:query:config:type:)`` with ``TextSearchType/plain``.
  ///
  /// - Parameters:
  ///   - column: The `text` or `tsvector` column to search.
  ///   - query: The search query text.
  ///   - config: The text search configuration name. Defaults to `nil`.
  /// - Returns: The same builder instance so calls can be chained.
  public func plainToFullTextSearch(
    _ column: String,
    query: String,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    textSearch(column, query: query, config: config, type: .plain)
  }

  /// Matches only rows where `column` matches the full-text search `query` using `phraseto_tsquery`.
  ///
  /// This is a semantic alias for ``textSearch(_:query:config:type:)`` with ``TextSearchType/phrase``.
  ///
  /// - Parameters:
  ///   - column: The `text` or `tsvector` column to search.
  ///   - query: The search query text.
  ///   - config: The text search configuration name. Defaults to `nil`.
  /// - Returns: The same builder instance so calls can be chained.
  public func phraseToFullTextSearch(
    _ column: String,
    query: String,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    textSearch(column, query: query, config: config, type: .phrase)
  }

  /// Matches only rows where `column` matches the full-text search `query` using `websearch_to_tsquery`.
  ///
  /// This is a semantic alias for ``textSearch(_:query:config:type:)`` with ``TextSearchType/websearch``.
  ///
  /// - Parameters:
  ///   - column: The `text` or `tsvector` column to search.
  ///   - query: The search query text.
  ///   - config: The text search configuration name. Defaults to `nil`.
  /// - Returns: The same builder instance so calls can be chained.
  public func webFullTextSearch(
    _ column: String,
    query: String,
    config: String? = nil
  ) -> PostgrestFilterBuilder {
    textSearch(column, query: query, config: config, type: .websearch)
  }
}
