import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - ResponseBody

/// Represents the body of an HTTP response.
///
/// A response body can be delivered in two forms depending on how the request was made:
/// - ``data(_:)``: The body has been fully buffered into memory as `Data`.
/// - ``bytes(_:)``: The body is streamed lazily as an asynchronous byte sequence.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
package enum ResponseBody: Sendable {
  /// The response body fully collected and available as `Data`.
  case data(Data)

  /// The response body available as an asynchronous byte stream.
  case bytes(URLSession.AsyncBytes)

  /// Collects the entire response body into a `Data` value.
  ///
  /// - If the body is already ``data(_:)``, the value is returned immediately.
  /// - If the body is ``bytes(_:)``, bytes are read from the stream and accumulated
  ///   until the stream is exhausted or `maxSize` is exceeded.
  ///
  /// - Parameter maxSize: The maximum number of bytes to collect. Defaults to `Int.max`
  ///   (effectively unlimited). If the collected size exceeds this limit a
  ///   `URLError(.dataLengthExceedsMaximum)` is thrown.
  /// - Returns: The fully collected response body as `Data`.
  /// - Throws: `URLError(.dataLengthExceedsMaximum)` when the body exceeds `maxSize`,
  ///   or any error thrown by the underlying async byte stream.
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

// MARK: - RequestAdapter

/// A type that can inspect and mutate outgoing `URLRequest` values before they are sent.
///
/// Adopt `RequestAdapter` to inject headers, sign requests, add query parameters, or
/// perform any other pre-flight mutation on a request.
package protocol RequestAdapter: Sendable {
  /// Returns a (potentially modified) copy of the given request.
  ///
  /// - Parameter request: The original `URLRequest` to adapt.
  /// - Returns: The adapted `URLRequest`.
  /// - Throws: Any error that prevents the request from being adapted.
  func adapt(_ request: URLRequest) async throws -> URLRequest
}

// MARK: - Adapters

/// A composite `RequestAdapter` that applies a sequence of adapters in order.
///
/// Each adapter in the chain receives the output of the previous one, allowing
/// multiple independent mutations to be composed together cleanly.
package struct Adapters: RequestAdapter {
  /// The ordered list of adapters applied to each request.
  let adapters: [any RequestAdapter]

  /// Creates an `Adapters` instance with the given list of adapters.
  ///
  /// - Parameter adapters: The adapters to apply, in the order they will be executed.
  package init(_ adapters: [any RequestAdapter]) {
    self.adapters = adapters
  }

  /// Applies each adapter in sequence, passing the output of one as the input to the next.
  ///
  /// - Parameter request: The original `URLRequest` to adapt.
  /// - Returns: The request after all adapters have been applied.
  /// - Throws: The first error thrown by any adapter in the chain.
  package func adapt(_ request: URLRequest) async throws -> URLRequest {
    var adaptedRequest = request
    for adapter in adapters {
      adaptedRequest = try await adapter.adapt(adaptedRequest)
    }
    return adaptedRequest
  }
}

// MARK: - ResponseInterceptor

/// A type that can inspect and transform an HTTP response before it is returned to the caller.
///
/// Adopt `ResponseInterceptor` to validate status codes, decode error payloads, refresh
/// tokens, or apply any other post-flight transformation to a response.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
package protocol ResponseInterceptor: Sendable {
  /// Returns a (potentially modified) response body and HTTP response.
  ///
  /// - Parameters:
  ///   - body: The original ``ResponseBody`` received from the server.
  ///   - response: The original `HTTPURLResponse` received from the server.
  /// - Returns: A tuple of the (possibly transformed) body and response.
  /// - Throws: Any error that should be propagated to the caller.
  func intercept(body: ResponseBody, response: HTTPURLResponse) async throws -> (
    ResponseBody, HTTPURLResponse
  )
}

// MARK: - Interceptors

/// A composite `ResponseInterceptor` that applies a sequence of interceptors in order.
///
/// Each interceptor in the chain receives the output of the previous one, allowing
/// multiple independent response transformations to be composed together cleanly.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
package struct Interceptors: ResponseInterceptor {
  /// The ordered list of interceptors applied to each response.
  let interceptors: [any ResponseInterceptor]

  /// Creates an `Interceptors` instance with the given list of interceptors.
  ///
  /// - Parameter interceptors: The interceptors to apply, in the order they will be executed.
  package init(_ interceptors: [any ResponseInterceptor]) {
    self.interceptors = interceptors
  }

  /// Applies each interceptor in sequence, passing the output of one as the input to the next.
  ///
  /// - Parameters:
  ///   - body: The original ``ResponseBody`` received from the server.
  ///   - response: The original `HTTPURLResponse` received from the server.
  /// - Returns: A tuple of the body and response after all interceptors have been applied.
  /// - Throws: The first error thrown by any interceptor in the chain.
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

// MARK: - HTTPSession

/// A configurable HTTP session that builds and executes URL requests relative to a base URL.
///
/// `HTTPSession` wraps `URLSession` and adds:
/// - **Base URL composition** – all request paths are resolved relative to ``baseURL``.
/// - **Request adaptation** – an optional ``RequestAdapter`` (or ``Adapters`` chain) is
///   applied to every outgoing request, making it straightforward to inject auth headers,
///   sign requests, etc.
/// - **Response interception** – an optional ``ResponseInterceptor`` (or ``Interceptors``
///   chain) is applied to every response, enabling centralised error handling, token
///   refresh logic, and more.
///
/// ## Default headers
/// Unless explicitly overridden by the caller, `HTTPSession` sets the following headers:
/// - `Accept: application/json` on every request.
/// - `Content-Type: application/json` on requests that carry a body.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
package class HTTPSession: @unchecked Sendable {

  // MARK: Properties

  /// The base URL against which all request paths are resolved.
  package let baseURL: URL

  /// The `URLSessionConfiguration` used to create the underlying `URLSession`.
  package let configuration: URLSessionConfiguration

  /// An optional adapter applied to every outgoing request before it is sent.
  let requestAdapter: (any RequestAdapter)?

  /// An optional interceptor applied to every response before it is returned to the caller.
  let responseInterceptor: (any ResponseInterceptor)?

  /// The underlying `URLSession` used to perform network requests.
  let session: URLSession

  // MARK: Initializer

  /// Creates a new `HTTPSession`.
  ///
  /// - Parameters:
  ///   - baseURL: The base URL against which all request paths are resolved.
  ///   - configuration: The `URLSessionConfiguration` for the underlying session.
  ///   - requestAdapter: An optional adapter applied to every outgoing request.
  ///   - responseInterceptor: An optional interceptor applied to every response.
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

  // MARK: Request Execution

  /// Performs an HTTP request and returns the fully buffered response body.
  ///
  /// The request is first adapted by the ``requestAdapter`` (if any), then executed using
  /// `URLSession.data(for:)`, and finally passed through the ``responseInterceptor`` (if any)
  /// before being returned.
  ///
  /// - Parameters:
  ///   - method: The HTTP method (e.g. `"GET"`, `"POST"`).
  ///   - path: The path appended to ``baseURL``.
  ///   - headers: Additional HTTP headers to include in the request.
  ///   - query: URL query parameters to append to the request URL.
  ///   - body: An optional HTTP body payload.
  /// - Returns: A tuple of the response `Data` and the `HTTPURLResponse`.
  /// - Throws: `URLError(.badURL)` if the URL cannot be constructed,
  ///   `URLError(.badServerResponse)` if the response is not an `HTTPURLResponse`,
  ///   or any error thrown by the adapter, session, or interceptor.
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

  /// Performs an HTTP request and returns the response body as an asynchronous byte stream.
  ///
  /// The request is first adapted by the ``requestAdapter`` (if any), then executed using
  /// `URLSession.bytes(for:)`, and finally passed through the ``responseInterceptor`` (if any)
  /// before being returned. Bytes are delivered lazily and are not buffered in memory.
  ///
  /// - Parameters:
  ///   - method: The HTTP method (e.g. `"GET"`, `"POST"`).
  ///   - path: The path appended to ``baseURL``.
  ///   - headers: Additional HTTP headers to include in the request.
  ///   - query: URL query parameters to append to the request URL.
  ///   - body: An optional HTTP body payload.
  /// - Returns: A tuple of `URLSession.AsyncBytes` and the `HTTPURLResponse`.
  /// - Throws: `URLError(.badURL)` if the URL cannot be constructed,
  ///   `URLError(.badServerResponse)` if the response is not an `HTTPURLResponse`,
  ///   or any error thrown by the adapter, session, or interceptor.
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

  /// Performs an HTTP request by uploading `Data` and returns the fully buffered response body.
  ///
  /// Unlike ``data(_:path:headers:query:body:)``, the payload is provided separately and
  /// sent via `URLSession.upload(for:from:)`, which is better suited for large uploads.
  ///
  /// - Parameters:
  ///   - method: The HTTP method (e.g. `"PUT"`, `"POST"`).
  ///   - path: The path appended to ``baseURL``.
  ///   - headers: Additional HTTP headers to include in the request.
  ///   - query: URL query parameters to append to the request URL.
  ///   - body: The data to upload as the HTTP body.
  /// - Returns: A tuple of the response `Data` and the `HTTPURLResponse`.
  /// - Throws: `URLError(.badURL)` if the URL cannot be constructed,
  ///   `URLError(.badServerResponse)` if the response is not an `HTTPURLResponse`,
  ///   or any error thrown by the adapter, session, or interceptor.
  func upload(
    _ method: String,
    path: String,
    headers: [String: String] = [:],
    query: [String: String] = [:],
    from body: Data
  ) async throws -> (Data, HTTPURLResponse) {
    let baseRequest = try makeRequest(method, path: path, headers: headers, query: query, body: nil)
    let finalRequest = try await requestAdapter?.adapt(baseRequest) ?? baseRequest
    let (data, response) = try await session.upload(for: finalRequest, from: body)
    guard let httpURLResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }
    return try await applyResponseInterceptor(data: data, response: httpURLResponse)
  }

  /// Performs an HTTP request by uploading a file and returns the fully buffered response body.
  ///
  /// The file at `fileURL` is streamed directly to the server via
  /// `URLSession.upload(for:fromFile:)`, which avoids loading the entire file into memory.
  ///
  /// - Parameters:
  ///   - method: The HTTP method (e.g. `"PUT"`, `"POST"`).
  ///   - path: The path appended to ``baseURL``.
  ///   - headers: Additional HTTP headers to include in the request.
  ///   - query: URL query parameters to append to the request URL.
  ///   - fileURL: The local file URL whose contents will be uploaded as the HTTP body.
  /// - Returns: A tuple of the response `Data` and the `HTTPURLResponse`.
  /// - Throws: `URLError(.badURL)` if the URL cannot be constructed,
  ///   `URLError(.badServerResponse)` if the response is not an `HTTPURLResponse`,
  ///   or any error thrown by the adapter, session, or interceptor.
  func upload(
    _ method: String,
    path: String,
    headers: [String: String] = [:],
    query: [String: String] = [:],
    from fileURL: URL
  ) async throws -> (Data, HTTPURLResponse) {
    let baseRequest = try makeRequest(method, path: path, headers: headers, query: query, body: nil)
    let finalRequest = try await requestAdapter?.adapt(baseRequest) ?? baseRequest
    let (data, response) = try await session.upload(for: finalRequest, fromFile: fileURL)
    guard let httpURLResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }
    return try await applyResponseInterceptor(data: data, response: httpURLResponse)
  }

  // MARK: Private Helpers

  /// Constructs a `URLRequest` resolved against ``baseURL`` with the supplied parameters.
  ///
  /// Default headers applied when not already present:
  /// - `Accept: application/json`
  /// - `Content-Type: application/json` (only when a `body` is provided)
  ///
  /// - Parameters:
  ///   - method: The HTTP method string.
  ///   - path: The path component to resolve against ``baseURL``.
  ///   - headers: Key-value pairs added as HTTP header fields.
  ///   - query: Key-value pairs appended as URL query items.
  ///   - body: Optional data to set as the request's `httpBody`.
  /// - Returns: A fully configured `URLRequest`.
  /// - Throws: `URLError(.badURL)` if the URL or its components cannot be constructed.
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
    guard let resolvedURL = components.url else {
      throw URLError(.badURL)
    }

    var request = URLRequest(url: resolvedURL)
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

  /// Passes a buffered response through the ``responseInterceptor``, if one is configured.
  ///
  /// - Parameters:
  ///   - data: The fully buffered response body.
  ///   - response: The associated `HTTPURLResponse`.
  /// - Returns: The (possibly transformed) data and response.
  /// - Throws: Any error thrown by the interceptor, or a `fatalError` if the interceptor
  ///   unexpectedly converts a buffered body into a byte stream.
  private func applyResponseInterceptor(
    data: Data, response: HTTPURLResponse
  ) async throws -> (Data, HTTPURLResponse) {
    guard let interceptor = responseInterceptor else {
      return (data, response)
    }
    let (body, interceptedResponse) = try await interceptor.intercept(
      body: .data(data), response: response)
    switch body {
    case .data(let interceptedData):
      return (interceptedData, interceptedResponse)
    case .bytes:
      fatalError(
        "ResponseInterceptor returned .bytes, but data() was called. This is not supported.")
    }
  }

  /// Passes a streaming response through the ``responseInterceptor``, if one is configured.
  ///
  /// - Parameters:
  ///   - bytes: The asynchronous byte stream for the response body.
  ///   - response: The associated `HTTPURLResponse`.
  /// - Returns: The (possibly transformed) byte stream and response.
  /// - Throws: Any error thrown by the interceptor, or a `fatalError` if the interceptor
  ///   unexpectedly converts a byte stream into a buffered body.
  private func applyResponseInterceptor(
    bytes: URLSession.AsyncBytes, response: HTTPURLResponse
  ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
    guard let interceptor = responseInterceptor else {
      return (bytes, response)
    }
    let (body, interceptedResponse) = try await interceptor.intercept(
      body: .bytes(bytes), response: response)
    switch body {
    case .data:
      fatalError(
        "ResponseInterceptor returned .data, but bytes() was called. This is not supported.")
    case .bytes(let interceptedBytes):
      return (interceptedBytes, interceptedResponse)
    }
  }
}
