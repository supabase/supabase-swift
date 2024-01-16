import Foundation

#if os(Linux) || os(Windows)
  import FoundationNetworking
#endif

struct HTTPClient: Sendable {
  typealias FetchHandler = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  let fetchHandler: FetchHandler

  func fetch(_ request: Request, baseURL: URL) async throws -> Response {
    let urlRequest = try request.urlRequest(withBaseURL: baseURL)
    let (data, response) = try await fetchHandler(urlRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    return Response(data: data, response: httpResponse)
  }
}

struct Request: Sendable {
  var path: String
  var method: Method
  var query: [URLQueryItem] = []
  var headers: [String: String] = [:]
  var body: Data?

  enum Method: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
  }

  func urlRequest(withBaseURL baseURL: URL) throws -> URLRequest {
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
