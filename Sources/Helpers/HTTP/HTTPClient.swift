//
//  HTTPClient.swift
//
//
//  Created by Guilherme Souza on 30/04/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package protocol HTTPClientType: Sendable {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

package actor HTTPClient: HTTPClientType {
  let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)
  let interceptors: [any HTTPClientInterceptor]

  package init(
    fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
    interceptors: [any HTTPClientInterceptor]
  ) {
    self.fetch = fetch
    self.interceptors = interceptors
  }

  package func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    var next: @Sendable (HTTPRequest) async throws -> HTTPResponse = { _request in
      let urlRequest = _request.urlRequest
      let (data, response) = try await self.fetch(urlRequest)
      guard let httpURLResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      return HTTPResponse(data: data, response: httpURLResponse)
    }

    for interceptor in interceptors.reversed() {
      let tmp = next
      next = {
        try await interceptor.intercept($0, next: tmp)
      }
    }

    return try await next(request)
  }
}

package protocol HTTPClientInterceptor: Sendable {
  func intercept(
    _ request: HTTPRequest,
    next: @Sendable (HTTPRequest) async throws -> HTTPResponse
  ) async throws -> HTTPResponse
}

package final class HTTP: Sendable {
  package enum Method: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
  }

  /// The base URL for requests.
  let baseURL: URL

  /// The underlying session for requests.
  let session: URLSession

  /// The access token for requests.
  let accessToken: (@Sendable () async throws -> String?)?

  package init(
    baseURL: URL,
    session: URLSession = .shared,
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) {
    var baseURL = baseURL
    if baseURL.path.hasSuffix("/") {
      baseURL = baseURL.appendingPathComponent("/")
    }

    self.baseURL = baseURL
    self.session = session
    self.accessToken = accessToken
  }

  /// Fetches data from the server.
  /// - Parameters:
  ///   - method: The HTTP method to use.
  ///   - path: The path to the resource.
  ///   - additionalQuery: Additional query parameters to add to the request.
  ///   - headers: Additional headers to add to the request.
  ///   - params: The parameters to add to the request.
  ///   - progress: The progress callback to receive the download progress.
  /// - Returns: The data from the server.
  ///
  /// - Note:
  ///   - `params` are method dependent, GET and HEAD requests use query parameters, POST, PUT, PATCH and DELETE requests use the body.
  ///   - Use `additionalQuery` to add query parameters to non GET and HEAD requests.
  package func fetchData(
    _ method: Method = .get,
    path: String,
    additionalQuery: [String: String] = [:],
    headers: [String: String] = [:],
    params: [String: Value] = [:],
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> Data {
    let urlRequest = try await prepareRequest(
      method, path: path, additionalQuery: additionalQuery, headers: headers, params: params)
    return try await performFetchData(request: urlRequest)
  }

  /// Fetches a stream of data from the server.
  /// - Parameters:
  ///   - method: The HTTP method to use.
  ///   - path: The path to the resource.
  ///   - additionalQuery: Additional query parameters to add to the request.
  ///   - headers: Additional headers to add to the request.
  ///   - params: The parameters to add to the request.
  ///   - chunkSize: The size of the chunks to fetch.
  ///   - progress: The progress callback to receive the download progress.
  /// - Returns: A stream of data from the server.
  ///
  /// - Note:
  ///   - `params` are method dependent, GET and HEAD requests use query parameters, POST, PUT, PATCH and DELETE requests use the body.
  ///   - Use `additionalQuery` to add query parameters to non GET and HEAD requests.
  package func fetchStream(
    _ method: Method,
    path: String,
    additionalQuery: [String: String] = [:],
    headers: [String: String] = [:],
    params: [String: Value] = [:],
    chunkSize: Int = 1024 * 1024,
    progress: (@Sendable (Double) -> Void)? = nil
  ) -> AsyncThrowingStream<Data, any Error> {
    performFetchStream(
      method,
      chunkSize: chunkSize,
      progress: progress,
      requestBuilder: { [self] in
        try await prepareRequest(
          method, path: path, additionalQuery: additionalQuery, headers: headers, params: params)
      }
    )
  }

  private func performFetchStream(
    _ method: Method,
    chunkSize: Int,
    progress: (@Sendable (Double) -> Void)?,
    requestBuilder: @escaping @Sendable () async throws -> URLRequest
  ) -> AsyncThrowingStream<Data, any Error> {
    AsyncThrowingStream<Data, any Error> { @Sendable continuation in
      let task = Task {
        let urlRequest = try await requestBuilder()
        let (bytes, response) = try await session.bytes(
          for: urlRequest, delegate: progress.map { DownloadProgressDelegate(progress: $0) })

        let httpResponse = try validateResponse(response: response, data: nil)

        guard (200..<300).contains(httpResponse.statusCode) else {
          var errorData = Data()
          for try await byte in bytes {
            errorData.append(byte)
          }

          // validateResponse will throw the appropriate error.
          try validateResponse(response: response, data: errorData)
          return  // This line will never be reached but satisfies the compiler.
        }

        do {
          var chunk = Data(capacity: chunkSize)
          for try await byte in bytes {
            chunk.append(byte)
            if chunk.count >= chunkSize {
              continuation.yield(chunk)
              chunk.removeAll(keepingCapacity: true)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func performFetchData(request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    try validateResponse(response: response, data: data)
    return data
  }

  package func prepareRequest(
    _ method: Method,
    path: String,
    additionalQuery: [String: String] = [:],
    headers: [String: String] = [:],
    params: [String: Value]? = nil
  ) async throws -> URLRequest {
    let url = baseURL.appendingPathComponent(path)
    return try await prepareRequest(
      method, url: url, additionalQuery: additionalQuery, headers: headers, params: params)
  }

  package func prepareRequest(
    _ method: Method,
    url: URL,
    additionalQuery: [String: String] = [:],
    headers: [String: String] = [:],
    params: [String: Value]? = nil
  ) async throws -> URLRequest {
    let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)
    return try await prepareRequest(
      method, urlComponents: urlComponents, additionalQuery: additionalQuery, headers: headers,
      params: params)
  }

  private func prepareRequest(
    _ method: Method,
    urlComponents: URLComponents?,
    additionalQuery: [String: String] = [:],
    headers: [String: String] = [:],
    params: [String: Value]? = nil
  ) async throws -> URLRequest {
    var urlComponents = urlComponents

    var httpBody: Data?
    switch method {
    case .get, .head:
      if let params {
        urlComponents?.queryItems = params.map {
          URLQueryItem(name: $0.key, value: $0.value.description)
        }
      }

    case .post, .put, .patch, .delete:
      if let params {
        let encoder = JSONEncoder()
        // Special-case: allow sending a top-level JSON value (e.g., array)
        // by passing a single empty-string key.
        // This is used for endpoints that require an array body instead of an object.
        if params.count == 1, let sole = params.first, sole.key == "" {
          httpBody = try encoder.encode(sole.value)
        } else {
          httpBody = try encoder.encode(params)
        }
      }
    }

    guard let url = urlComponents?.url else {
      throw HTTPError.requestError(
        "Unable to construct URL from components \(String(describing: urlComponents))")
    }

    var urlRequest = URLRequest(url: url)

    urlRequest.httpMethod = method.rawValue

    headers.forEach { key, value in
      urlRequest.addValue(value, forHTTPHeaderField: key)
    }

    if urlRequest.value(forHTTPHeaderField: "Accept") == nil {
      urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")
    }

    if let httpBody {
      urlRequest.httpBody = httpBody
      if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
      }
    }

    if urlRequest.value(forHTTPHeaderField: "Authorization") == nil,
      let accessToken = try await self.accessToken?()
    {
      urlRequest.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    return urlRequest
  }

  @discardableResult
  private func validateResponse(
    response: URLResponse,
    data: Data?
  ) throws -> HTTPURLResponse {
    guard let httpURLResponse = response as? HTTPURLResponse else {
      throw HTTPError.unexpectedError("Invalid response from server: \(response)")
    }

    if let data, !(200..<300).contains(httpURLResponse.statusCode) {
      if let json = try? JSONDecoder().decode([String: AnyJSON].self, from: data) {
        throw HTTPError.unacceptedStatusCode(
          statusCode: httpURLResponse.statusCode,
          body: json)
      }

      if let string = String(data: data, encoding: .utf8) {
        throw HTTPError.unacceptedStatusCode(
          statusCode: httpURLResponse.statusCode,
          body: ["message": AnyJSON.string(string)])
      }

      throw HTTPError.unacceptedStatusCode(
        statusCode: httpURLResponse.statusCode,
        body: ["message": AnyJSON.string("Unknown error")])
    }
    return httpURLResponse
  }

  package enum HTTPError: Swift.Error, Sendable {
    case requestError(String)
    case invalidURL
    case unacceptedStatusCode(statusCode: Int, body: [String: AnyJSON])
    case invalidResponse(response: URLResponse)
    case unexpectedError(String)
  }
}

final class DownloadProgressDelegate: NSObject, URLSessionDataDelegate, Sendable {
  let progress: @Sendable (Double) -> Void

  init(progress: @escaping @Sendable (Double) -> Void) {
    self.progress = progress
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    progress(Double(data.count) / Double(dataTask.countOfBytesExpectedToReceive))
  }
}

extension HTTP {
  package enum Value: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([Value])
    case object([String: Value])

    /// Create a `Value` from a `Codable` value.
    /// - Parameter value: The codable value
    /// - Returns: A value
    package init<T: Codable>(_ value: T) throws {
      if let valueAsValue = value as? Value {
        self = valueAsValue
      } else {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(Value.self, from: data)
      }
    }

    /// Returns whether the value is `null`.
    package var isNull: Bool {
      return self == .null
    }

    /// Returns the `Bool` value if the value is a `bool`,
    /// otherwise returns `nil`.
    package var boolValue: Bool? {
      guard case .bool(let value) = self else { return nil }
      return value
    }

    /// Returns the `Int` value if the value is an `integer`,
    /// otherwise returns `nil`.
    package var intValue: Int? {
      guard case .int(let value) = self else { return nil }
      return value
    }

    /// Returns the `Double` value if the value is a `double`,
    /// otherwise returns `nil`.
    package var doubleValue: Double? {
      switch self {
      case .double(let value):
        return value
      case .int(let value):
        return Double(value)
      default:
        return nil
      }
    }

    /// Returns the `String` value if the value is a `string`,
    /// otherwise returns `nil`.
    package var stringValue: String? {
      guard case .string(let value) = self else { return nil }
      return value
    }

    /// Returns the `[Value]` value if the value is an `array`,
    /// otherwise returns `nil`.
    package var arrayValue: [Value]? {
      guard case .array(let value) = self else { return nil }
      return value
    }

    /// Returns the `[String: Value]` value if the value is an `object`,
    /// otherwise returns `nil`.
    package var objectValue: [String: Value]? {
      guard case .object(let value) = self else { return nil }
      return value
    }
  }
}

// MARK: - Codable

extension HTTP.Value: Codable {
  package init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([HTTP.Value].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: HTTP.Value].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Value type not found"
      )
    }
  }

  package func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .int(let value):
      try container.encode(value)
    case .double(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }
}

extension HTTP.Value: CustomStringConvertible {
  package var description: String {
    switch self {
    case .null:
      return ""
    case .bool(let value):
      return value.description
    case .int(let value):
      return value.description
    case .double(let value):
      return value.description
    case .string(let value):
      return value.description
    case .array(let value):
      return value.description
    case .object(let value):
      return value.description
    }
  }
}

// MARK: - ExpressibleByNilLiteral

extension HTTP.Value: ExpressibleByNilLiteral {
  package init(nilLiteral: ()) {
    self = .null
  }
}

// MARK: - ExpressibleByBooleanLiteral

extension HTTP.Value: ExpressibleByBooleanLiteral {
  package init(booleanLiteral value: Bool) {
    self = .bool(value)
  }
}

// MARK: - ExpressibleByIntegerLiteral

extension HTTP.Value: ExpressibleByIntegerLiteral {
  package init(integerLiteral value: Int) {
    self = .int(value)
  }
}

// MARK: - ExpressibleByFloatLiteral

extension HTTP.Value: ExpressibleByFloatLiteral {
  package init(floatLiteral value: Double) {
    self = .double(value)
  }
}

// MARK: - ExpressibleByStringLiteral

extension HTTP.Value: ExpressibleByStringLiteral {
  package init(stringLiteral value: String) {
    self = .string(value)
  }
}

// MARK: - ExpressibleByArrayLiteral

extension HTTP.Value: ExpressibleByArrayLiteral {
  package init(arrayLiteral elements: HTTP.Value...) {
    self = .array(elements)
  }
}

// MARK: - ExpressibleByDictionaryLiteral

extension HTTP.Value: ExpressibleByDictionaryLiteral {
  package init(dictionaryLiteral elements: (String, HTTP.Value)...) {
    var dictionary: [String: HTTP.Value] = [:]
    for (key, value) in elements {
      dictionary[key] = value
    }
    self = .object(dictionary)
  }
}

// MARK: - ExpressibleByStringInterpolation

extension HTTP.Value: ExpressibleByStringInterpolation {
  package struct StringInterpolation: StringInterpolationProtocol {
    var stringValue: String

    package init(literalCapacity: Int, interpolationCount: Int) {
      self.stringValue = ""
      self.stringValue.reserveCapacity(literalCapacity + interpolationCount)
    }

    package mutating func appendLiteral(_ literal: String) {
      self.stringValue.append(literal)
    }

    package mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) {
      self.stringValue.append(value.description)
    }
  }

  package init(stringInterpolation: StringInterpolation) {
    self = .string(stringInterpolation.stringValue)
  }
}
