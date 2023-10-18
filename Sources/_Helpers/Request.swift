import Foundation

@_spi(Internal)
public struct Request {
  public var path: String
  public var method: String
  public var query: [URLQueryItem]
  public var headers: [String: String]
  public var body: Data?

  public init(
    path: String, method: String, query: [URLQueryItem] = [], headers: [String: String] = [:],
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

      components.queryItems = query

      if let newURL = components.url {
        url = newURL
      } else {
        throw URLError(.badURL)
      }
    }

    var request = URLRequest(url: url)
    request.httpMethod = method

    if body != nil, headers["Content-Type"] == nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    for (name, value) in headers {
      request.setValue(value, forHTTPHeaderField: name)
    }

    request.httpBody = body

    return request
  }
}

@_spi(Internal)
public struct Response {
  public let data: Data
  public let response: HTTPURLResponse

  public init(data: Data, response: HTTPURLResponse) {
    self.data = data
    self.response = response
  }

  public func decoded<T: Decodable>(as _: T.Type = T.self, decoder: JSONDecoder) throws -> T {
    try decoder.decode(T.self, from: data)
  }
}
