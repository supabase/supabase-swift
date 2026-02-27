import Foundation

/// Represents the body of an HTTP response. It can be either fully collected as `Data` or streamed as `URLSession.AsyncBytes`.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
package enum ResponseBody: Sendable {
  /// The response body is fully collected and available as `Data`.
  case data(Data)

  /// The response body is available as an asynchronous byte stream (`URLSession.AsyncBytes`).
  case bytes(URLSession.AsyncBytes)

  /// Collects the response body into a `Data` object. If the body is already available as `Data`, it returns it directly. If the body is an asynchronous byte stream, it reads all bytes and appends them to a `Data` object until the stream is exhausted or the optional `maxSize` limit is exceeded.
  package func collect(upTo maxSize: Int = .max) async throws -> Data {
    switch self {
    case .data(let data):
      return data
    case .bytes(let asyncBytes):
      var collectedData = Data()
      for try await byte in asyncBytes {
        collectedData.append(byte)
        if collectedData.count > maxSize {
          throw URLError(.dataLengthExceedsMaximum)
        }
      }
      return collectedData
    }
  }
}

package protocol RequestAdapter: Sendable {
  func adapt(_ request: URLRequest) async throws -> URLRequest
}

package struct Adapters: RequestAdapter {
  let adapters: [any RequestAdapter]

  package init(_ adapters: [any RequestAdapter]) {
    self.adapters = adapters
  }

  package func adapt(_ request: URLRequest) async throws -> URLRequest {
    var adaptedRequest = request
    for adapter in adapters {
      adaptedRequest = try await adapter.adapt(adaptedRequest)
    }
    return adaptedRequest
  }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
package struct Interceptors: ResponseInterceptor {
  let interceptors: [any ResponseInterceptor]

  package init(_ interceptors: [any ResponseInterceptor]) {
    self.interceptors = interceptors
  }

  package func intercept(body: ResponseBody, response: HTTPURLResponse) async throws -> (
    ResponseBody, HTTPURLResponse
  ) {
    var interceptedBody = body
    var interceptedResponse = response
    for interceptor in interceptors {
      (interceptedBody, interceptedResponse) = try await interceptor.intercept(
        body: interceptedBody, response: interceptedResponse)
    }
    return (interceptedBody, interceptedResponse)
  }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
package protocol ResponseInterceptor: Sendable {
  func intercept(body: ResponseBody, response: HTTPURLResponse) async throws -> (
    ResponseBody, HTTPURLResponse
  )
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
package class HTTPSession: @unchecked Sendable {
  package let baseURL: URL
  package let configuration: URLSessionConfiguration

  let requestAdapter: (any RequestAdapter)?
  let responseInterceptor: (any ResponseInterceptor)?
  let session: URLSession

  package init(
    baseURL: URL,
    configuration: URLSessionConfiguration,
    requestAdapter: (any RequestAdapter)? = nil,
    responseInterceptor: (any ResponseInterceptor)? = nil
  ) {
    self.baseURL = baseURL
    self.configuration = configuration
    self.session = URLSession(configuration: configuration)
    self.requestAdapter = requestAdapter
    self.responseInterceptor = responseInterceptor
  }

  package func data(
    _ method: String,
    path: String,
    headers: [String: String] = [:],
    query: [String: String] = [:],
    body: Data? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    let baseRequest = try makeRequest(
      method, path: path, headers: headers, query: query, body: body)
    let finalRequest = try await requestAdapter?.adapt(baseRequest) ?? baseRequest
    let (data, response) = try await session.data(for: finalRequest)
    guard let httpURLResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }
    return try await applyResponseInterceptor(data: data, response: httpURLResponse)
  }

  package func bytes(
    _ method: String,
    path: String,
    headers: [String: String] = [:],
    query: [String: String] = [:],
    body: Data? = nil
  ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
    let baseRequest = try makeRequest(
      method, path: path, headers: headers, query: query, body: body)
    let finalRequest = try await requestAdapter?.adapt(baseRequest) ?? baseRequest
    let (bytes, response) = try await session.bytes(for: finalRequest)
    guard let httpURLResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }
    return try await applyResponseInterceptor(bytes: bytes, response: httpURLResponse)
  }

  func upload(
    _ method: String,
    path: String,
    headers: [String: String] = [:],
    query: [String: String] = [:],
    from body: Data
  ) async throws -> (Data, HTTPURLResponse) {
    let baseRequest = try makeRequest(
      method, path: path, headers: headers, query: query, body: nil)
    let finalRequest = try await requestAdapter?.adapt(baseRequest) ?? baseRequest
    let (data, response) = try await session.upload(for: finalRequest, from: body)
    guard let httpURLResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }
    return try await applyResponseInterceptor(data: data, response: httpURLResponse)
  }

  func upload(
    _ method: String,
    path: String,
    headers: [String: String] = [:],
    query: [String: String] = [:],
    from fileURL: URL
  ) async throws -> (Data, HTTPURLResponse) {
    let baseRequest = try makeRequest(
      method, path: path, headers: headers, query: query, body: nil)
    let finalRequest = try await requestAdapter?.adapt(baseRequest) ?? baseRequest
    let (data, response) = try await session.upload(for: finalRequest, fromFile: fileURL)
    guard let httpURLResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }
    return try await applyResponseInterceptor(data: data, response: httpURLResponse)
  }

  /// Constructs a URLRequest with the given parameters, relative to the session's baseURL.
  private func makeRequest(
    _ method: String,
    path: String,
    headers: [String: String] = [:],
    query: [String: String] = [:],
    body: Data? = nil
  ) throws -> URLRequest {
    guard let url = URL(string: path, relativeTo: baseURL) else {
      throw URLError(.badURL)
    }
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
      throw URLError(.badURL)
    }
    if !query.isEmpty {
      components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    guard let url = components.url else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: url)
    request.httpMethod = method

    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    if request.value(forHTTPHeaderField: "Accept") == nil {
      request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    if let body {
      request.httpBody = body

      if request.value(forHTTPHeaderField: "Content-Type") == nil {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }
    }

    return request
  }

  private func applyResponseInterceptor(
    data: Data, response: HTTPURLResponse
  ) async throws -> (Data, HTTPURLResponse) {
    if let interceptor = responseInterceptor {
      let (body, response) = try await interceptor.intercept(body: .data(data), response: response)
      switch body {
      case .data(let data):
        return (data, response)
      case .bytes:
        fatalError(
          "ResponseInterceptor returned bytes, but data() was called. This should never happen.")
      }
    } else {
      return (data, response)
    }
  }

  private func applyResponseInterceptor(
    bytes: URLSession.AsyncBytes, response: HTTPURLResponse
  ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
    if let interceptor = responseInterceptor {
      let (body, response) = try await interceptor.intercept(
        body: .bytes(bytes), response: response)
      switch body {
      case .data:
        fatalError(
          "ResponseInterceptor returned data, but bytes() was called. This should never happen.")
      case .bytes(let bytes):
        return (bytes, response)
      }
    } else {
      return (bytes, response)
    }
  }
}
