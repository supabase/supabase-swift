import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct PostgrestResponse<T: Sendable>: Sendable {
  public let data: Data
  public let response: HTTPURLResponse
  public let count: Int?
  public let value: T

  public var status: Int {
    response.statusCode
  }

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
  
  /// Returns the response converting the returned Data into Unicode characters using a given encoding.
  public func string(encoding: String.Encoding = .utf8) -> String? {
    String(data: data, encoding: encoding)
  }
}

/// Returns count as part of the response when specified.
public enum CountOption: String, Sendable {
  /// Exact but slow count algorithm. Performs a `COUNT(*)` under the hood.
  case exact
  /// Approximated but fast count algorithm. Uses the Postgres statistics under the hood.
  case planned
  /// Uses exact count for low numbers and planned count for high numbers.
  case estimated
}

/// Enum of options representing the ways PostgREST can return values from the server.
///
/// https://postgrest.org/en/v9.0/api.html?highlight=PREFER#insertions-updates
public enum PostgrestReturningOptions: String, Sendable {
  /// Returns nothing from the server
  case minimal
  /// Returns a copy of the updated data.
  case representation
}

/// The type of tsquery conversion to use on query.
public enum TextSearchType: String, Sendable {
  /// Uses PostgreSQL's plainto_tsquery function.
  case plain = "pl"
  /// Uses PostgreSQL's phraseto_tsquery function.
  case phrase = "ph"
  /// Uses PostgreSQL's websearch_to_tsquery function.
  /// This function will never raise syntax errors, which makes it possible to use raw user-supplied
  /// input for search, and can be used with advanced operators.
  case websearch = "w"
}

/// Options for querying Supabase.
public struct FetchOptions: Sendable {
  /// Set head to true if you only want the count value and not the underlying data.
  public let head: Bool

  /// count options can be used to retrieve the total number of rows that satisfies the
  /// query. The value for count respects any filters (e.g. eq, gt), but ignores
  /// modifiers (e.g. limit, range).
  public let count: CountOption?

  public init(head: Bool = false, count: CountOption? = nil) {
    self.head = head
    self.count = count
  }
}
