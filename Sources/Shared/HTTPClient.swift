import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum HTTPMethod: String, Sendable {
  case get = "GET"
  case head = "HEAD"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
}

/// A client for making HTTP requests.
package final class HTTPClient: Sendable {

  /// The host of the API.
  let host: URL

  /// The session to use for the API.
  package let session: URLSession

  /// The token provider for authentication.
  let tokenProvider: @Sendable () async throws -> String?

  /// A shared JSON decoder with consistent configuration.
  let jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  package init(
    host: URL,
    session: URLSession = .shared,
    tokenProvider: @escaping @Sendable () async throws -> String? = { nil }
  ) {
    var host = host
    if !host.path.hasSuffix("/") {
      host = host.appendingPathComponent("/")
    }
    self.host = host
    self.session = session
    self.tokenProvider = tokenProvider
  }

  package func fetchData(
    _ request: URLRequest
  ) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    let httpResponse = try validateResponse(response, data: data)
    return (data, httpResponse)
  }

  package func fetchData(
    _ method: HTTPMethod,
    _ path: String,
    query: [String: Value]? = nil,
    body: Data? = nil,
    headers: [String: String]? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    let request = try await createRequest(
      method, path, query: query, body: body, headers: headers)
    return try await fetchData(request)
  }

  package func fetch<T: Decodable>(
    _ request: URLRequest,
    decoder: JSONDecoder? = nil
  ) async throws -> (T, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    let httpResponse = try validateResponse(response, data: data)
    if T.self == Bool.self {
      // If T is Bool, we return true for succesful response.
      return (true as! T, httpResponse)
    } else if T.self == Void.self {
      // If T is Void, we return () for succesful response.
      return (() as! T, httpResponse)
    } else if data.isEmpty {
      throw HTTPClientError.responseError(
        response: httpResponse, payload: ["message": "Empty response body"])
    } else {
      do {
        return (try (decoder ?? jsonDecoder).decode(T.self, from: data), httpResponse)
      } catch {
        throw HTTPClientError.decodingError(
          response: httpResponse,
          detail: "Error decoding response: \(error.localizedDescription)")
      }
    }
  }

  package func fetch<T: Decodable>(
    _ method: HTTPMethod,
    _ path: String,
    query: [String: Value]? = nil,
    body: Data? = nil,
    headers: [String: String]? = nil,
    decoder: JSONDecoder? = nil
  ) async throws -> (T, HTTPURLResponse) {
    let request = try await createRequest(
      method, path, query: query, body: body, headers: headers)
    return try await fetch(request, decoder: decoder)
  }

  @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
  package func fetchStream(
    _ request: URLRequest,
    chunkSize: Int = 1024 * 1024  // 1MB
  ) -> AsyncThrowingStream<Data, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let (bytes, response) = try await session.bytes(for: request)
          let httpResponse = try validateResponse(response)

          guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
              errorData.append(byte)
            }
            // validateResponse will throw the appropriate error
            _ = try validateResponse(response, data: errorData)
            return  // This line will never be reached, but satisfies the compiler.
          }

          var buffer = Data(capacity: chunkSize)
          for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
              continuation.yield(buffer)
              buffer.removeAll(keepingCapacity: true)
            }
          }
          if !buffer.isEmpty {
            continuation.yield(buffer)
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

  @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
  package func fetchStream(
    _ method: HTTPMethod,
    _ path: String,
    query: [String: Value]? = nil,
    body: Data? = nil,
    headers: [String: String]? = nil,
    chunkSize: Int = 1024 * 1024  // 1MB
  ) async throws -> AsyncThrowingStream<Data, any Error> {
    let request = try await createRequest(
      method, path, query: query, body: body, headers: headers)
    return fetchStream(request, chunkSize: chunkSize)
  }

  package func createRequest(
    _ method: HTTPMethod,
    _ path: String,
    query: [String: Value]? = nil,
    body: Data? = nil,
    headers: [String: String]? = nil,
  ) async throws -> URLRequest {
    var urlComponents = URLComponents(url: host, resolvingAgainstBaseURL: true)
    urlComponents?.path = path
    if let query, !query.isEmpty {
      urlComponents?.queryItems = query.map {
        URLQueryItem(name: $0.key, value: $0.value.description)
      }
    }

    var httpBody: Data?
    switch method {
    case .get, .head:
      if let body, !body.isEmpty {
        fatalError("Body is not supported for GET or HEAD requests")
      }

    case .post, .put, .delete, .patch:
      httpBody = body
    }

    guard let url = urlComponents?.url else {
      throw HTTPClientError.requestError(
        #"Unable to construct URL with host: "\#(host)" and path "\#(path)""#)
    }
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue

    if request.value(forHTTPHeaderField: "Accept") == nil {
      request.addValue("application/json", forHTTPHeaderField: "Accept")
    }

    if request.value(forHTTPHeaderField: "Authorization") == nil,
      let token = try await tokenProvider()
    {
      request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    if let httpBody {
      request.httpBody = httpBody
      if request.value(forHTTPHeaderField: "Content-Type") == nil {
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
      }
    }

    if let headers {
      for (key, value) in headers {
        request.addValue(value, forHTTPHeaderField: key)
      }
    }

    return request
  }

  package func validateResponse(_ response: URLResponse, data: Data? = nil) throws
    -> HTTPURLResponse
  {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw HTTPClientError.unexpectedError("Invalid response from server: \(response)")
    }

    if let data, !(200..<300).contains(httpResponse.statusCode) {
      if let payload = try? jsonDecoder.decode([String: Value].self, from: data) {
        throw HTTPClientError.responseError(response: httpResponse, payload: payload)
      }

      if let string = String(data: data, encoding: .utf8) {
        throw HTTPClientError.responseError(
          response: httpResponse, payload: ["message": .string(string)])
      }

      throw HTTPClientError.responseError(response: httpResponse, payload: [:])
    }

    return httpResponse
  }
}

/// Represents errors that can occur during API operations.
package enum HTTPClientError: Error, Hashable, Sendable, CustomStringConvertible {
  /// An error encountered while constructing the request.
  case requestError(String)

  /// An error encountered while validating the response.
  case responseError(response: HTTPURLResponse, payload: [String: Value])

  /// An error encountered while decoding the response.
  case decodingError(response: HTTPURLResponse, detail: String)

  /// An unexpected error occurred.
  case unexpectedError(String)

  package var description: String {
    switch self {
    case .requestError(let message):
      return "Request error: \(message)"

    case .responseError(let response, let payload):
      return "Response error (Status \(response.statusCode)): \(payload.description)"

    case .decodingError(let response, let detail):
      return "Decoding error (Status \(response.statusCode)): \(detail)"

    case .unexpectedError(let message):
      return "Unexpected error: \(message)"
    }
  }
}
