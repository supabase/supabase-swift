import ConcurrencyExtras
public import Foundation
import HTTPTypes
public import Helpers

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

let version = Helpers.version

/// A client for invoking Supabase Edge Functions.
///
/// Obtain an instance from ``SupabaseClient/functions`` rather than creating one directly.
///
/// ```swift
/// // Invoke and decode a response
/// let order: Order = try await supabase.functions.invoke("get-order")
///
/// // Invoke with a body and no return value
/// try await supabase.functions.invoke(
///   "send-email",
///   options: FunctionInvokeOptions(body: ["to": "user@example.com"])
/// )
/// ```
///
/// ## Topics
///
/// ### Creating a Client
/// - ``init(url:headers:region:logger:fetch:decoder:)``
/// - ``FetchHandler``
///
/// ### Invoking Functions
/// - ``invoke(_:options:decode:)``
/// - ``invoke(_:options:decoder:)``
/// - ``invoke(_:options:)``
/// - ``_invokeWithStreamedResponse(_:options:)``
///
/// ### Configuration
/// - ``decoder``
/// - ``requestIdleTimeout``
/// - ``setAuth(token:)``
public final class FunctionsClient: Sendable {
  /// A handler that performs the underlying HTTP request for a function invocation.
  public typealias FetchHandler =
    @Sendable (_ request: URLRequest) async throws -> (
      Data, URLResponse
    )

  /// The maximum time an Edge Function may run before the gateway returns a 504 error (150 seconds).
  ///
  /// Can be overridden per-invocation via ``FunctionInvokeOptions/timeoutInterval``.
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: String?

  /// The JSON decoder used to decode function response bodies.
  public let decoder: JSONDecoder

  struct MutableState {
    /// Headers to be included in the requests.
    var headers = HTTPFields()
  }

  private let http: any HTTPClientType
  private let mutableState = LockIsolated(MutableState())
  private let sessionConfiguration: URLSessionConfiguration

  var headers: HTTPFields {
    mutableState.headers
  }

  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region string to invoke functions in.
  ///   - logger: A logger for request and response diagnostics.
  ///   - fetch: A custom fetch handler. Defaults to `URLSession.shared`.
  ///   - decoder: The JSON decoder used to decode response bodies.
  @_disfavoredOverload
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region,
      logger: logger,
      fetch: fetch,
      decoder: decoder,
      sessionConfiguration: .default
    )
  }

  convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    decoder: JSONDecoder = JSONDecoder(),
    sessionConfiguration: URLSessionConfiguration
  ) {
    var interceptors: [any HTTPClientInterceptor] = []
    if let logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    let http = HTTPClient(fetch: fetch, interceptors: interceptors)

    self.init(
      url: url,
      headers: headers,
      region: region,
      decoder: decoder,
      http: http,
      sessionConfiguration: sessionConfiguration
    )
  }

  init(
    url: URL,
    headers: [String: String],
    region: String?,
    decoder: JSONDecoder = JSONDecoder(),
    http: any HTTPClientType,
    sessionConfiguration: URLSessionConfiguration = .default
  ) {
    self.url = url
    self.region = region
    self.decoder = decoder
    self.http = http
    self.sessionConfiguration = sessionConfiguration

    mutableState.withValue {
      $0.headers = HTTPFields(headers)
      if $0.headers[.xClientInfo] == nil {
        $0.headers[.xClientInfo] = "functions-swift/\(version)"
      }
    }
  }

  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region to invoke functions in.
  ///   - logger: A logger for request and response diagnostics.
  ///   - fetch: A custom fetch handler. Defaults to `URLSession.shared`.
  ///   - decoder: The JSON decoder used to decode response bodies.
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region?.rawValue,
      logger: logger,
      fetch: fetch,
      decoder: decoder
    )
  }

  /// Sets or clears the JWT used in the Authorization header for subsequent requests.
  /// - Parameter token: The JWT to send, or `nil` to remove the Authorization header.
  public func setAuth(token: String?) {
    mutableState.withValue {
      if let token {
        $0.headers[.authorization] = "Bearer \(token)"
      } else {
        $0.headers[.authorization] = nil
      }
    }
  }

  /// Invokes a function and decodes the response with a custom closure.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for the invocation.
  ///   - decode: A closure that receives the raw response data and HTTP response, and returns the
  ///     decoded value.
  /// - Returns: The value returned by `decode`.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status or a relay error.
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws -> Response {
    let response = try await rawInvoke(
      functionName: functionName, invokeOptions: options
    )
    return try decode(response.data, response.underlyingResponse)
  }

  /// Invokes a function and JSON-decodes the response body into `T`.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for the invocation.
  ///   - decoder: The JSON decoder to use. Defaults to the client's ``decoder`` when `nil`.
  /// - Returns: The decoded `T`.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status or a relay error, or
  ///   a decoding error if the response body cannot be decoded as `T`.
  public func invoke<T: Decodable>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decoder: JSONDecoder? = nil
  ) async throws -> T {
    let decoder = decoder ?? self.decoder
    return try await invoke(functionName, options: options) { data, _ in
      try decoder.decode(T.self, from: data)
    }
  }

  /// Invokes a function and discards any response body.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for the invocation.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status or a relay error.
  public func invoke(
    _ functionName: String,
    options: FunctionInvokeOptions = .init()
  ) async throws {
    try await invoke(functionName, options: options) { _, _ in () }
  }

  private func rawInvoke(
    functionName: String,
    invokeOptions: FunctionInvokeOptions
  ) async throws -> Helpers.HTTPResponse {
    let request = buildRequest(functionName: functionName, options: invokeOptions)
    let response = try await http.send(request)

    let isRelayError = response.headers[.xRelayError] == "true"
    if isRelayError {
      throw FunctionsError.relayError
    }

    guard 200..<300 ~= response.statusCode else {
      throw FunctionsError.httpError(code: response.statusCode, data: response.data)
    }

    return response
  }

  /// Invokes a function and returns its response as a stream of raw `Data` chunks.
  ///
  /// The function must return a `text/event-stream` content type for this to work correctly.
  ///
  /// > Warning: Experimental — the API may change without a major version bump.
  ///
  /// > Note: This method uses a separate `URLSession` from the rest of the client.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for the invocation.
  /// - Returns: An `AsyncThrowingStream` that yields response data chunks as they arrive.
  public func _invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) -> AsyncThrowingStream<Data, any Error> {
    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    let delegate = StreamResponseDelegate(continuation: continuation)

    let session = URLSession(
      configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)

    let urlRequest = buildRequest(functionName: functionName, options: invokeOptions).urlRequest

    let task = session.dataTask(with: urlRequest)
    task.resume()

    continuation.onTermination = { _ in
      task.cancel()

      // Hold a strong reference to delegate until continuation terminates.
      _ = delegate
    }

    return stream
  }

  private func buildRequest(functionName: String, options: FunctionInvokeOptions)
    -> Helpers.HTTPRequest
  {
    var query = options.query
    var request = HTTPRequest(
      url: url.appendingPathComponent(functionName),
      method: FunctionInvokeOptions.httpMethod(options.method) ?? .post,
      query: query,
      headers: mutableState.headers.merging(with: options.headers),
      body: options.body,
      timeoutInterval: options.timeoutInterval ?? FunctionsClient.requestIdleTimeout
    )

    if let region = options.region ?? region {
      request.headers[.xRegion] = region
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region))
      request.query = query
    }

    return request
  }
}

final class StreamResponseDelegate: NSObject, URLSessionDataDelegate, Sendable {
  let continuation: AsyncThrowingStream<Data, any Error>.Continuation

  init(continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
    self.continuation = continuation
  }

  func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
    continuation.yield(data)
  }

  func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
    continuation.finish(throwing: error)
  }

  func urlSession(
    _: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    defer {
      completionHandler(.allow)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      continuation.finish(throwing: URLError(.badServerResponse))
      return
    }

    let isRelayError = httpResponse.value(forHTTPHeaderField: "x-relay-error") == "true"
    if isRelayError {
      continuation.finish(throwing: FunctionsError.relayError)
      return
    }

    guard 200..<300 ~= httpResponse.statusCode else {
      let error = FunctionsError.httpError(
        code: httpResponse.statusCode,
        data: Data()
      )
      continuation.finish(throwing: error)
      return
    }
  }
}
