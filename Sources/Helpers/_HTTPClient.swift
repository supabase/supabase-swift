//
//  _HTTPClient.swift
//  Supabase
//
//  Created by Guilherme Souza on 12/03/26.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// HTTP methods supported by ``_HTTPClient``.
package enum HTTPMethod: String {
  case get = "GET"
  case head = "HEAD"
  case post = "POST"
  case patch = "PATCH"
  case put = "PUT"
  case delete = "DELETE"
}

package enum RequestBody {
  case encodable(
    @autoclosure @Sendable () -> any Encodable,
    encoder: JSONEncoder = JSONEncoder.supabase()
  )
  case json(@autoclosure @Sendable () -> [String: Any])
  case data(Data)
}

package typealias TokenProvider = @Sendable () async throws -> String?

/// HTTP client for making all Supabase API requests.
///
/// Builds `URLRequest` values from a base `host` URL and dispatches them via `URLSession`.
/// Responses are validated for 2xx status codes before being returned.
package final class _HTTPClient: Sendable {

  /// The base URL for the API. This will be used as the base for all requests made by this client.
  package let host: URL

  /// The URLSession used to perform network requests.
  package let session: URLSession

  let tokenProvider: TokenProvider?

  /// The JSONDecoder used to decode responses from the server.
  let jsonDecoder = JSONDecoder.supabase()

  package init(
    host: URL, session: URLSession = URLSession(configuration: .default),
    tokenProvider: TokenProvider? = nil
  ) {
    self.host = host
    self.session = session
    self.tokenProvider = tokenProvider
  }

  /// Performs a request relative to ``host``, decoding the response body as `T`.
  ///
  /// Uses ``jsonDecoder`` (a `JSONDecoder` with Supabase defaults) to decode the response.
  /// If you need custom decoding, use ``fetchData(_:_:query:body:headers:)`` and decode at the call site.
  package func fetch<T: Decodable>(
    _ method: HTTPMethod, _ path: String, query: [String: String]? = nil,
    body: RequestBody? = nil, headers: [String: String]? = nil
  ) async throws -> (T, HTTPURLResponse) {
    let request = try await createRequest(method, path, query: query, body: body, headers: headers)
    return try await performFetch(request: request)
  }

  /// Performs a request to an absolute `url`, decoding the response body as `T`.
  ///
  /// Uses ``jsonDecoder`` (a `JSONDecoder` with Supabase defaults) to decode the response.
  /// If you need custom decoding, use ``fetchData(_:url:query:body:headers:)`` and decode at the call site.
  package func fetch<T: Decodable>(
    _ method: HTTPMethod, url: URL, query: [String: String]? = nil, body: RequestBody? = nil,
    headers: [String: String]? = nil
  ) async throws -> (T, HTTPURLResponse) {
    let request = try await createRequest(
      method, url: url, query: query, body: body, headers: headers)
    return try await performFetch(request: request)
  }

  private func performFetch<T: Decodable>(
    request: URLRequest
  ) async throws -> (T, HTTPURLResponse) {
    let (data, response) = try await performFetch(request: request)

    do {
      let value = try jsonDecoder.decode(T.self, from: data)
      return (value, response)
    } catch {
      throw HTTPClientError.decodingError(response, detail: error.localizedDescription)
    }
  }

  #if canImport(Darwin)
    /// Streams the response body byte-by-byte via an `AsyncThrowingStream`.
    ///
    /// Cancelling the stream cancels the underlying `URLSession` task. Non-2xx responses
    /// buffer the full error body and throw ``HTTPClientError/responseError(_:data:)``.
    ///
    /// - Note: Only available on Apple platforms. `URLSession.bytes(for:)` is not available on Linux.
    @available(macOS 12.0, *)
    package func fetchStream(
      _ method: HTTPMethod, _ path: String, query: [String: String]? = nil,
      body: RequestBody? = nil, headers: [String: String]? = nil
    ) -> AsyncThrowingStream<UInt8, any Error> {
      performFetchStream(
        method,
        requestBuilder: { [self] in
          try await self.createRequest(method, path, query: query, body: body, headers: headers)
        }
      )
    }

    /// Streams the response body from an absolute `url` byte-by-byte.
    ///
    /// - Note: Only available on Apple platforms. `URLSession.bytes(for:)` is not available on Linux.
    @available(macOS 12.0, *)
    package func fetchStream(
      _ method: HTTPMethod, url: URL, query: [String: String]? = nil, body: RequestBody? = nil,
      headers: [String: String]? = nil
    ) -> AsyncThrowingStream<UInt8, any Error> {
      performFetchStream(
        method,
        requestBuilder: { [self] in
          try await self.createRequest(method, url: url, query: query, body: body, headers: headers)
        }
      )
    }

    @available(macOS 12.0, *)
    private func performFetchStream(
      _ method: HTTPMethod, requestBuilder: @escaping @Sendable () async throws -> URLRequest
    ) -> AsyncThrowingStream<UInt8, any Error> {
      AsyncThrowingStream { continuation in
        let task = Task {
          do {
            let request = try await requestBuilder()

            let (bytes, response) = try await session.bytes(for: request)
            let httpResponse = try validateResponse(response)

            guard (200..<300).contains(httpResponse.statusCode) else {
              var errorData = Data()
              for try await byte in bytes {
                errorData.append(byte)
              }
              // validateResponse will throw the appropriate error
              _ = try validateResponse(response, data: errorData)
              return  // This line will never be reached, but satisfies the compiler
            }

            for try await byte in bytes {
              continuation.yield(byte)
            }

            continuation.finish()
          }
        }

        continuation.onTermination = { _ in
          task.cancel()
        }
      }
    }
  #endif

  /// Performs a request relative to ``host``, returning the raw response body.
  package func fetchData(
    _ method: HTTPMethod, _ path: String, query: [String: String]? = nil,
    body: RequestBody? = nil, headers: [String: String]? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    let request = try await createRequest(method, path, query: query, body: body, headers: headers)
    return try await performFetch(request: request)
  }

  /// Performs a request to an absolute `url`, returning the raw response body.
  package func fetchData(
    _ method: HTTPMethod, url: URL, query: [String: String]? = nil, body: RequestBody? = nil,
    headers: [String: String]? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    let request = try await createRequest(
      method, url: url, query: query, body: body, headers: headers)
    return try await performFetch(request: request)
  }

  private func performFetch(
    request: URLRequest
  ) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    let httpResponse = try validateResponse(response)
    return (data, httpResponse)
  }

  /// Builds a `URLRequest` by appending `path` to ``host``.
  ///
  /// - Parameters:
  ///   - method: The HTTP method.
  ///   - path: The path component to append to ``host``.
  ///   - query: Optional query parameters. Always encoded as URL query items.
  ///   - body: Optional request body. Encoded according to the ``RequestBody`` case.
  ///   - headers: Optional additional headers. `Accept: application/json` is added by default.
  package func createRequest(
    _ method: HTTPMethod, _ path: String, query: [String: String]? = nil,
    body: RequestBody? = nil, headers: [String: String]? = nil
  ) async throws -> URLRequest {
    var urlComponents = URLComponents(url: host, resolvingAgainstBaseURL: true)
    urlComponents?.path = path

    return try await createRequest(
      method, urlComponents: urlComponents, query: query, body: body, headers: headers)
  }

  /// Builds a `URLRequest` from an absolute `url`.
  package func createRequest(
    _ method: HTTPMethod, url: URL, query: [String: String]? = nil, body: RequestBody? = nil,
    headers: [String: String]? = nil
  ) async throws -> URLRequest {
    let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)

    return try await createRequest(
      method, urlComponents: urlComponents, query: query, body: body, headers: headers)
  }

  private func createRequest(
    _ method: HTTPMethod, urlComponents: URLComponents?, query: [String: String]? = nil,
    body: RequestBody? = nil, headers: [String: String]? = nil
  ) async throws -> URLRequest {
    var urlComponents = urlComponents

    if let query {
      var queryItems = urlComponents?.queryItems ?? []
      for (key, value) in query {
        queryItems.append(URLQueryItem(name: key, value: value))
      }
      urlComponents?.queryItems = queryItems
    }

    guard let url = urlComponents?.url else {
      throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue

    if let headers {
      for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }

    if let tokenProvider,
      request.value(forHTTPHeaderField: "Authorization") == nil,
      let token = try await tokenProvider()
    {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    if request.value(forHTTPHeaderField: "Accept") == nil {
      request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    if let body {
      switch body {
      case .encodable(let value, let encoder):
        request.httpBody = try encoder.encode(value())
      case .json(let dict):
        request.httpBody = try JSONSerialization.data(withJSONObject: dict())
      case .data(let data):
        request.httpBody = data
      }
      if request.value(forHTTPHeaderField: "Content-Type") == nil {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }
    }

    return request
  }

  /// Casts `response` to `HTTPURLResponse` and throws if the status code is outside 2xx.
  ///
  /// - Parameters:
  ///   - response: The raw `URLResponse` to validate.
  ///   - data: When provided, included in ``HTTPClientError/responseError(_:data:)`` on failure.
  @discardableResult
  package func validateResponse(_ response: URLResponse, data: Data? = nil) throws -> HTTPURLResponse {
    guard let response = response as? HTTPURLResponse else {
      throw HTTPClientError.unexpectedError(
        "Invalid response from server: \(response)"
      )
    }

    if let data, !(200..<300).contains(response.statusCode) {
      throw HTTPClientError.responseError(response, data: data)
    }

    return response
  }
}

/// Errors thrown by ``_HTTPClient``.
package enum HTTPClientError: Error {
  /// The server returned a non-2xx status code. The raw response body is included in `data`.
  case responseError(HTTPURLResponse, data: Data)
  /// The response body could not be decoded into the expected type.
  case decodingError(HTTPURLResponse, detail: String)
  /// An unexpected error occurred (e.g. the response was not an `HTTPURLResponse`).
  case unexpectedError(String)
}
