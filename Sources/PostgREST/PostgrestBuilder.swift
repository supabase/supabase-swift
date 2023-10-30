import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The builder class for creating and executing requests to a PostgREST server.
public class PostgrestBuilder {
  /// The configuration for the PostgREST client.
  let configuration: PostgrestClient.Configuration
  /// The URL for the request.
  let url: URL
  /// The query parameters for the request.
  var queryParams: [(name: String, value: String?)]
  /// The headers for the request.
  var headers: [String: String]
  /// The HTTP method for the request.
  var method: String
  /// The body data for the request.
  var body: Data?

  /// The options for fetching data from the PostgREST server.
  var fetchOptions = FetchOptions()

  init(
    configuration: PostgrestClient.Configuration,
    url: URL,
    queryParams: [(name: String, value: String?)],
    headers: [String: String],
    method: String,
    body: Data?
  ) {
    self.configuration = configuration
    self.url = url
    self.queryParams = queryParams
    self.headers = headers
    self.method = method
    self.body = body
  }

  convenience init(_ other: PostgrestBuilder) {
    self.init(
      configuration: other.configuration,
      url: other.url,
      queryParams: other.queryParams,
      headers: other.headers,
      method: other.method,
      body: other.body
    )
  }

  /// Executes the request and returns a response of type Void.
  /// - Parameters:
  ///   - options: Options for querying Supabase.
  /// - Returns: A `PostgrestResponse<Void>` instance representing the response.
  @discardableResult
  public func execute(
    options: FetchOptions = FetchOptions()
  ) async throws -> PostgrestResponse<Void> {
    fetchOptions = options
    return try await execute { _ in () }
  }

  /// Executes the request and returns a response of the specified type.
  /// - Parameters:
  ///   - options: Options for querying Supabase.
  /// - Returns: A `PostgrestResponse<T>` instance representing the response.
  @discardableResult
  public func execute<T: Decodable>(
    options: FetchOptions = FetchOptions()
  ) async throws -> PostgrestResponse<T> {
    fetchOptions = options
    return try await execute { [configuration] data in
      try configuration.decoder.decode(T.self, from: data)
    }
  }

  func appendSearchParams(name: String, value: String) {
    queryParams.append((name, value))
  }

  private func execute<T>(decode: (Data) throws -> T) async throws -> PostgrestResponse<T> {
    if fetchOptions.head {
      method = "HEAD"
    }

    if let count = fetchOptions.count {
      if let prefer = headers["Prefer"] {
        headers["Prefer"] = "\(prefer),count=\(count.rawValue)"
      } else {
        headers["Prefer"] = "count=\(count.rawValue)"
      }
    }

    if headers["Accept"] == nil {
      headers["Accept"] = "application/json"
    }
    headers["Content-Type"] = "application/json"

    if let schema = configuration.schema {
      if method == "GET" || method == "HEAD" {
        headers["Accept-Profile"] = schema
      } else {
        headers["Content-Profile"] = schema
      }
    }

    let urlRequest = try makeURLRequest()

    let (data, response) = try await configuration.fetch(urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    guard 200 ..< 300 ~= httpResponse.statusCode else {
      let error = try configuration.decoder.decode(PostgrestError.self, from: data)
      throw error
    }

    let value = try decode(data)
    return PostgrestResponse(data: data, response: httpResponse, value: value)
  }

  private func makeURLRequest() throws -> URLRequest {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw URLError(.badURL)
    }

    if !queryParams.isEmpty {
      let percentEncodedQuery =
        (components.percentEncodedQuery.map { $0 + "&" } ?? "") + query(queryParams)
      components.percentEncodedQuery = percentEncodedQuery
    }

    guard let url = components.url else {
      throw URLError(.badURL)
    }

    var urlRequest = URLRequest(url: url)

    for (key, value) in headers {
      urlRequest.setValue(value, forHTTPHeaderField: key)
    }

    urlRequest.httpMethod = method

    if let body {
      urlRequest.httpBody = body
    }

    return urlRequest
  }

  private func escape(_ string: String) -> String {
    string.addingPercentEncoding(withAllowedCharacters: .postgrestURLQueryAllowed) ?? string
  }

  private func query(_ parameters: [(String, String?)]) -> String {
    parameters.compactMap { key, value in
      if let value {
        return (key, value)
      }
      return nil
    }
    .map { key, value -> String in
      let escapedKey = escape(key)
      let escapedValue = escape(value)
      return "\(escapedKey)=\(escapedValue)"
    }
    .joined(separator: "&")
  }
}

extension CharacterSet {
  /// Creates a CharacterSet from RFC 3986 allowed characters.
  ///
  /// RFC 3986 states that the following characters are "reserved" characters.
  ///
  /// - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
  /// - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="
  ///
  /// In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to
  /// allow
  /// query strings to include a URL. Therefore, all "reserved" characters with the exception of "?"
  /// and "/"
  /// should be percent-escaped in the query string.
  static let postgrestURLQueryAllowed: CharacterSet = {
    let generalDelimitersToEncode =
      ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
    let subDelimitersToEncode = "!$&'()*+,;="
    let encodableDelimiters =
      CharacterSet(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")

    return CharacterSet.urlQueryAllowed.subtracting(encodableDelimiters)
  }()
}
