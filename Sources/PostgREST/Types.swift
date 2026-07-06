import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The response returned by a PostgREST query, containing the raw data, HTTP response, row count, and decoded value.
///
/// ``PostgrestResponse`` wraps the raw network response from PostgREST and provides decoded access
/// to the returned rows alongside metadata such as the total row count (when requested via
/// ``CountOption``) and the HTTP status code.
///
/// ```swift
/// let response: PostgrestResponse<[Todo]> = try await client
///   .from("todos")
///   .select()
///   .execute()
///
/// print(response.value)  // [Todo]
/// print(response.count)  // optional total count
/// print(response.status) // HTTP status code
/// ```
///
/// ## Topics
///
/// ### Response Data
///
/// - ``data``
/// - ``value``
/// - ``count``
/// - ``status``
/// - ``response``
///
/// ### Converting the Response
///
/// - ``string(encoding:)``
public struct PostgrestResponse<T> {
  /// The raw response body as `Data`.
  public let data: Data

  /// The underlying HTTP URL response.
  public let response: HTTPURLResponse

  /// The total number of rows matching the query, or `nil` if no count was requested.
  ///
  /// This value is populated from the `Content-Range` response header when a ``CountOption`` is
  /// passed to the query. It respects any applied filters but ignores modifiers such as `limit`
  /// and `range`.
  public let count: Int?

  /// The decoded response value.
  public let value: T

  /// The HTTP status code of the response.
  public var status: Int {
    response.statusCode
  }

  /// Creates a ``PostgrestResponse`` from raw response data.
  ///
  /// - Parameters:
  ///   - data: The raw response body.
  ///   - response: The HTTP URL response.
  ///   - value: The decoded value.
  public init(
    data: Data,
    response: HTTPURLResponse,
    value: T
  ) {
    var count: Int?

    if let contentRange = response.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/")
      .last
    {
      count = contentRange == "*" ? nil : Int(contentRange)
    }

    self.data = data
    self.response = response
    self.count = count
    self.value = value
  }

  /// Returns the response body as a string using the specified encoding.
  ///
  /// - Parameter encoding: The string encoding to use. Defaults to `.utf8`.
  /// - Returns: A `String` decoded from ``data``, or `nil` if the data cannot be decoded with the given encoding.
  public func string(encoding: String.Encoding = .utf8) -> String? {
    String(data: data, encoding: encoding)
  }
}

/// The algorithm PostgREST uses to count the total number of rows matching a query.
///
/// Pass a ``CountOption`` to query methods such as ``PostgrestQueryBuilder/select(_:head:count:)``
/// or ``PostgrestClient/rpc(_:params:head:get:count:)`` to include a row count in the response.
///
/// The chosen algorithm determines the accuracy vs. performance trade-off:
///
/// | Option | Accuracy | Speed |
/// |--------|----------|-------|
/// | ``exact`` | Exact | Slow |
/// | ``planned`` | Approximate | Fast |
/// | ``estimated`` | Adaptive | Moderate |
public enum CountOption: String, Sendable {
  /// Performs a `COUNT(*)` under the hood for an exact row count.
  ///
  /// Use this when you need a precise total. It can be slow on large tables.
  case exact

  /// Uses PostgreSQL statistics for a fast but approximate row count.
  ///
  /// The estimate is derived from `pg_class.reltuples` and may be inaccurate  // cspell:ignore reltuples
  /// if the table statistics are stale.
  case planned

  /// Uses exact count for low numbers and planned count for high numbers.
  ///
  /// PostgREST switches to the approximate algorithm automatically when the
  /// estimated count exceeds a threshold, trading accuracy for performance
  /// on large result sets.
  case estimated
}

/// Controls which rows PostgREST returns after a write operation.
///
/// Pass a ``PostgrestReturningOptions`` value to ``PostgrestQueryBuilder/insert(_:returning:count:)``,
/// ``PostgrestQueryBuilder/update(_:returning:count:)``, ``PostgrestQueryBuilder/upsert(_:onConflict:returning:count:ignoreDuplicates:)``,
/// or ``PostgrestQueryBuilder/delete(returning:count:)`` to specify what the server sends back.
///
/// See the [PostgREST documentation](https://postgrest.org/en/v9.0/api.html?highlight=PREFER#insertions-updates)
/// for more detail.
public enum PostgrestReturningOptions: String, Sendable {
  /// Returns nothing from the server after the write.
  ///
  /// Use this option when you do not need the affected rows, as it avoids
  /// the overhead of serializing and transmitting them.
  case minimal

  /// Returns a copy of the written rows.
  ///
  /// Use this option (or chain `.select()` after the call) when you need the
  /// server-generated values such as `id`, `created_at`, or computed columns.
  case representation
}

/// The conversion strategy used to turn a plain-text search query into a `tsquery` expression.
///
/// Pass a ``TextSearchType`` to ``PostgrestFilterBuilder/textSearch(_:query:config:type:)`` to
/// control how user-supplied text is interpreted by PostgreSQL's full-text search engine.
public enum TextSearchType: String, Sendable {
  /// Converts the query using PostgreSQL's `plainto_tsquery` function.
  ///
  /// Words in the query are combined with the `&` (AND) operator. Punctuation
  /// and special characters are ignored.
  case plain = "pl"

  /// Converts the query using PostgreSQL's `phraseto_tsquery` function.
  ///
  /// Words must appear in the specified order, making this suitable for
  /// exact phrase searches.
  case phrase = "ph"

  /// Converts the query using PostgreSQL's `websearch_to_tsquery` function.
  ///
  /// This function accepts a web-search–style syntax (`"exact phrase"`, `-exclude`,
  /// `OR`) and never raises syntax errors, making it safe to use with raw
  /// user-supplied input.
  case websearch = "w"
}

/// The output format of a PostgREST EXPLAIN plan.
///
/// Pass an ``ExplainFormat`` value to ``PostgrestTransformBuilder/explain(analyze:verbose:settings:buffers:wal:format:)``
/// to choose how the query plan is serialized in the response.
///
/// ## Topics
///
/// ### Built-in Formats
///
/// - ``text``
/// - ``json``
///
/// ### Creating a Custom Format
///
/// - ``init(rawValue:)``
public struct ExplainFormat: RawRepresentable, Hashable, Sendable {
  /// The raw PostgREST format string (e.g., `"text"` or `"json"`).
  public let rawValue: String

  /// Creates an ``ExplainFormat`` with a custom raw format string.
  ///
  /// Prefer the static members ``text`` and ``json`` for standard usage.
  ///
  /// - Parameter rawValue: The raw format string accepted by PostgREST.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Human-readable text output (the default).
  ///
  /// Produces the same indented text that `EXPLAIN` prints in `psql`. // cspell:ignore psql
  public static let text = ExplainFormat(rawValue: "text")

  /// Machine-readable JSON output.
  ///
  /// Useful when you want to programmatically inspect or visualize the query plan.
  public static let json = ExplainFormat(rawValue: "json")
}

/// Options for controlling whether the response body is returned and how rows are counted.
///
/// Pass a ``FetchOptions`` value to ``PostgrestBuilder/execute(options:)-96tpd`` (or the typed
/// overload) to request a count without fetching data, or to fetch data and a count simultaneously.
///
/// ```swift
/// // Fetch only the count, no rows
/// let response = try await client
///   .from("todos")
///   .select()
///   .execute(options: FetchOptions(head: true, count: .exact))
///
/// print(response.count) // total rows matching the query
/// ```
///
/// ## Topics
///
/// ### Configuring the Request
///
/// - ``head``
/// - ``count``
///
/// ### Creating Options
///
/// - ``init(head:count:)``
public struct FetchOptions: Sendable {
  /// When `true`, the request uses the HTTP HEAD method and the response body is omitted.
  ///
  /// Combine with ``count`` to retrieve a total row count without fetching data.
  public let head: Bool

  /// The algorithm to use for counting rows, or `nil` to skip counting.
  ///
  /// The returned count respects any applied filters but ignores modifiers
  /// such as `limit` and `range`. See ``CountOption`` for the available algorithms.
  public let count: CountOption?

  /// Creates a ``FetchOptions`` value.
  ///
  /// - Parameters:
  ///   - head: Pass `true` to suppress the response body (HEAD request). Defaults to `false`.
  ///   - count: The row-count algorithm to use, or `nil` to skip counting. Defaults to `nil`.
  public init(head: Bool = false, count: CountOption? = nil) {
    self.head = head
    self.count = count
  }
}
