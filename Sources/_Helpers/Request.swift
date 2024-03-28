import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@_spi(Internal)
public struct HTTPClient: Sendable {
  public typealias FetchHandler = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  let logger: (any SupabaseLogger)?
  let fetchHandler: FetchHandler

  public init(logger: (any SupabaseLogger)?, fetchHandler: @escaping FetchHandler) {
    self.logger = logger
    self.fetchHandler = fetchHandler
  }

  public func fetch(_ request: Request, baseURL: URL) async throws -> Response {
    try await rawFetch(request.urlRequest(withBaseURL: baseURL))
  }

  public func rawFetch(_ request: URLRequest) async throws -> Response {
    let id = UUID().uuidString
    logger?
      .verbose(
        """
        Request [\(id)]: \(request.httpMethod ?? "") \(request.url?.absoluteString
          .removingPercentEncoding ?? "")
        Body: \(stringfy(request.httpBody))
        """
      )

    do {
      let (data, response) = try await fetchHandler(request)

      guard let httpResponse = response as? HTTPURLResponse else {
        logger?
          .error(
            "Response [\(id)]: Expected a \(HTTPURLResponse.self) instance, but got a \(type(of: response))."
          )
        throw URLError(.badServerResponse)
      }

      logger?
        .verbose(
          """
          Response [\(id)]: Status code: \(httpResponse.statusCode) Content-Length: \(
            httpResponse
              .expectedContentLength
          )
          Body: \(stringfy(data))
          """
        )

      return Response(data: data, response: httpResponse)
    } catch {
      logger?.error("Response [\(id)]: Failure \(error)")
      throw error
    }
  }

  private func stringfy(_ data: Data?) -> String {
    guard let data else {
      return "<none>"
    }

    do {
      let object = try JSONSerialization.jsonObject(with: data, options: [])
      let prettyData = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
      )
      return String(data: prettyData, encoding: .utf8) ?? "<failed>"
    } catch {
      return String(data: data, encoding: .utf8) ?? "<failed>"
    }
  }
}

@_spi(Internal)
public struct Request: Sendable {
  public var path: String
  public var method: Method
  public var query: [URLQueryItem]
  public var headers: [String: String]
  public var body: Data?

  public enum Method: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
  }

  public init(
    path: String,
    method: Method,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    body: Data? = nil
  ) {
    self.path = path
    self.method = method
    self.query = query
    self.headers = headers
    self.body = body
  }

  public func urlRequest(withBaseURL baseURL: URL) throws -> URLRequest {
    var url = baseURL.appendingPathComponent(path)
    if !query.isEmpty {
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw URLError(.badURL)
      }

      let currentQueryItems = components.queryItems ?? []
      components.percentEncodedQuery = percentEncodedQuery(currentQueryItems + query)

      if let newURL = components.url {
        url = newURL
      } else {
        throw URLError(.badURL)
      }
    }

    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue

    if body != nil, headers["Content-Type"] == nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    for (name, value) in headers {
      request.setValue(value, forHTTPHeaderField: name)
    }

    request.httpBody = body

    return request
  }

  private func percentEncodedQuery(_ query: [URLQueryItem]) -> String {
    query.compactMap { query in
      if let value = query.value {
        return (query.name, value)
      }
      return nil
    }
    .map { name, value -> String in
      let escapedName = name
        .addingPercentEncoding(withAllowedCharacters: .postgrestURLQueryAllowed) ?? name
      let escapedValue = value
        .addingPercentEncoding(withAllowedCharacters: .postgrestURLQueryAllowed) ?? value
      return "\(escapedName)=\(escapedValue)"
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

@_spi(Internal)
public struct Response: Sendable {
  public let data: Data
  public let response: HTTPURLResponse

  public var statusCode: Int {
    response.statusCode
  }

  public init(data: Data, response: HTTPURLResponse) {
    self.data = data
    self.response = response
  }

  public func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder) throws -> T {
    try decoder.decode(T.self, from: data)
  }
}
