public import Foundation
public import HTTPTypes
import Helpers

/// The response returned by a PostgREST query: the status, the headers, the raw body, the row
/// count, and the decoded value.
///
/// ```swift
/// let response: PostgrestResponse<[Todo]> = try await client
///   .from("todos")
///   .select(count: .exact)
///   .execute()
///
/// print(response.value)  // [Todo]
/// print(response.count)  // optional total count
/// print(response.status.code) // 200
/// ```
///
/// ## Topics
///
/// ### Response Data
///
/// - ``value``
/// - ``count``
/// - ``status``
/// - ``headers``
/// - ``body``
/// - ``requestID``
///
/// ### Creating a Response
///
/// - ``init(status:headers:body:count:value:)``
///
/// ### Converting the Response
///
/// - ``string(encoding:)``
public struct PostgrestResponse<T> {
  /// The HTTP status PostgREST answered with.
  ///
  /// A ``PostgrestRequestBuilder/maybeSingle()`` request that matches no row reads as `200 OK`
  /// with a `null` ``body``, although PostgREST answers it with `406 Not Acceptable`.
  public var status: HTTPResponse.Status

  /// Every response header. Import `HTTPTypes` to spell header names.
  public var headers: HTTPFields

  /// The raw response body. Empty when PostgREST sent none.
  public var body: Data

  /// The total number of rows matching the query, or `nil` if no count was requested.
  ///
  /// The SDK reads it from the `Content-Range` header when a ``CountOption`` is passed to the
  /// query. It respects any applied filters but ignores modifiers such as `limit` and `range`.
  public var count: Int?

  /// The decoded response value.
  public var value: T

  /// The `sb-request-id` header Supabase attaches to every response through its API gateway.
  ///
  /// Quote this value when contacting Supabase support. `nil` on self-hosted stacks that do not
  /// set the header.
  public var requestID: String? { headers[.sbRequestID] }

  /// Creates a response, for tests and mocks.
  ///
  /// - Parameters:
  ///   - status: The HTTP status.
  ///   - headers: The response headers.
  ///   - body: The raw response body.
  ///   - count: The total row count, or `nil` when no count was requested.
  ///   - value: The decoded value.
  public init(
    status: HTTPResponse.Status,
    headers: HTTPFields,
    body: Data,
    count: Int? = nil,
    value: T
  ) {
    self.status = status
    self.headers = headers
    self.body = body
    self.count = count
    self.value = value
  }

  /// Creates a response from a response head, reading ``count`` from `Content-Range`.
  init(_ response: HTTPResponse, body: Data, value: T) {
    let total = response.headerFields[.contentRange]?.split(separator: "/").last
    self.init(
      status: response.status,
      headers: response.headerFields,
      body: body,
      count: total.flatMap { Int($0) },
      value: value
    )
  }

  /// Returns the response body as a string using the specified encoding.
  ///
  /// - Parameter encoding: The string encoding to use. Defaults to `.utf8`.
  /// - Returns: A `String` decoded from ``body``, or `nil` if the body cannot be decoded with the
  ///   given encoding.
  public func string(encoding: String.Encoding = .utf8) -> String? {
    String(data: body, encoding: encoding)
  }
}

extension PostgrestResponse: Sendable where T: Sendable {}

/// The algorithm PostgREST uses to count the total number of rows matching a query.
///
/// Pass a ``CountOption`` to query methods such as ``PostgrestRequestBuilder/select(_:head:count:)``
/// or ``PostgrestClient/rpc(_:params:head:get:count:)`` to include a row count in the response.
///
/// The chosen algorithm determines the accuracy vs. performance trade-off:
///
/// | Option | Accuracy | Speed |
/// |--------|----------|-------|
/// | ``exact`` | Exact | Slow |
/// | ``planned`` | Approximate | Fast |
/// | ``estimated`` | Adaptive | Moderate |
public struct CountOption: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  /// The value sent in the `count` preference, such as `"exact"`.
  public let rawValue: String

  /// Creates a ``CountOption`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``CountOption`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Performs a `COUNT(*)` under the hood for an exact row count.
  ///
  /// Use this when you need a precise total. It can be slow on large tables.
  public static let exact: CountOption = "exact"

  /// Uses PostgreSQL statistics for a fast but approximate row count.
  ///
  /// The estimate is derived from `pg_class.reltuples` and may be inaccurate  // cspell:ignore reltuples
  /// if the table statistics are stale.
  public static let planned: CountOption = "planned"

  /// Uses exact count for low numbers and planned count for high numbers.
  ///
  /// PostgREST switches to the approximate algorithm automatically when the
  /// estimated count exceeds a threshold, trading accuracy for performance
  /// on large result sets.
  public static let estimated: CountOption = "estimated"
}

/// Controls which rows PostgREST returns after a write operation.
///
/// Pass a ``PostgrestReturning`` value to ``PostgrestRequestBuilder/insert(_:returning:count:defaultToNull:encoder:)``,
/// ``PostgrestRequestBuilder/update(_:returning:count:encoder:)``, ``PostgrestRequestBuilder/upsert(_:onConflict:returning:count:ignoreDuplicates:defaultToNull:encoder:)``,
/// or ``PostgrestRequestBuilder/delete(returning:count:)`` to specify what the server sends back.
///
/// See the [PostgREST documentation](https://postgrest.org/en/v9.0/api.html?highlight=PREFER#insertions-updates)
/// for more detail.
public struct PostgrestReturning: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The value sent in the `return` preference, such as `"minimal"`.
  public let rawValue: String

  /// Creates a ``PostgrestReturning`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``PostgrestReturning`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Returns nothing from the server after the write.
  ///
  /// Use this option when you do not need the affected rows, as it avoids
  /// the overhead of serializing and transmitting them.
  public static let minimal: PostgrestReturning = "minimal"

  /// Returns a copy of the written rows.
  ///
  /// Use this option (or chain `.select()` after the call) when you need the
  /// server-generated values such as `id`, `created_at`, or computed columns.
  public static let representation: PostgrestReturning = "representation"
}

/// The conversion strategy used to turn a plain-text search query into a `tsquery` expression.
///
/// Pass a ``TextSearchType`` to ``PostgrestRequestBuilder/textSearch(_:query:config:type:)`` to
/// control how user-supplied text is interpreted by PostgreSQL's full-text search engine.
public struct TextSearchType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  /// The prefix PostgREST expects before `fts`, such as `"pl"`.
  public let rawValue: String

  /// Creates a ``TextSearchType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``TextSearchType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Converts the query using PostgreSQL's `plainto_tsquery` function.
  ///
  /// Words in the query are combined with the `&` (AND) operator. Punctuation
  /// and special characters are ignored.
  public static let plain: TextSearchType = "pl"

  /// Converts the query using PostgreSQL's `phraseto_tsquery` function.
  ///
  /// Words must appear in the specified order, making this suitable for
  /// exact phrase searches.
  public static let phrase: TextSearchType = "ph"

  /// Converts the query using PostgreSQL's `websearch_to_tsquery` function.
  ///
  /// This function accepts a web-search–style syntax (`"exact phrase"`, `-exclude`,
  /// `OR`) and never raises syntax errors, making it safe to use with raw
  /// user-supplied input.
  public static let websearch: TextSearchType = "w"
}

/// The output format of a PostgREST EXPLAIN plan.
///
/// Pass an ``ExplainFormat`` value to ``PostgrestRequestBuilder/explain(analyze:verbose:settings:buffers:wal:format:)``
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
/// - ``init(stringLiteral:)``
public struct ExplainFormat: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
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

  /// Creates an ``ExplainFormat`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Human-readable text output (the default).
  ///
  /// Produces the same indented text that `EXPLAIN` prints in `psql`. // cspell:ignore psql
  public static let text: ExplainFormat = "text"

  /// Machine-readable JSON output.
  ///
  /// Useful when you want to programmatically inspect or visualize the query plan.
  public static let json: ExplainFormat = "json"
}

/// Options for controlling whether the response body is returned and how rows are counted.
///
/// Pass a ``FetchOptions`` value to ``PostgrestRequestBuilder/execute(options:)->PostgrestResponse<Void>`` (or the
/// typed overload) to request a count without fetching data, or to fetch data and a count
/// simultaneously.
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
