import ConcurrencyExtras
public import Foundation
public import HTTPTypes
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

  /// Invokes a function and returns the buffered response.
  /// - Parameters:
  ///   - name: The name of the function to invoke.
  ///   - body: The request body, or `nil` to send none.
  ///   - options: Options for the invocation.
  /// - Returns: The status, headers and body of the response.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status or a relay error.
  @discardableResult
  public func invoke(
    _ name: String,
    body: FunctionBody? = nil,
    options: FunctionInvokeOptions = .init()
  ) async throws -> FunctionResponse {
    let response = try await rawInvoke(functionName: name, body: body, invokeOptions: options)
    return FunctionResponse(
      status: HTTPTypes.HTTPResponse.Status(code: response.statusCode),
      headers: response.headers,
      body: response.data,
      decoder: decoder
    )
  }

  /// Invokes a function and JSON-decodes the response body into `T`.
  /// - Parameters:
  ///   - name: The name of the function to invoke.
  ///   - body: The request body, or `nil` to send none.
  ///   - options: Options for the invocation.
  ///   - type: The type to decode. Inferred from the call site when omitted.
  ///   - decoder: The JSON decoder to use. Defaults to the client's ``decoder`` when `nil`.
  /// - Returns: The decoded `T`.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status or a relay error, or
  ///   a decoding error if the response body cannot be decoded as `T`.
  public func invoke<T: Decodable>(
    _ name: String,
    body: FunctionBody? = nil,
    options: FunctionInvokeOptions = .init(),
    as type: T.Type = T.self,
    decoder: JSONDecoder? = nil
  ) async throws -> T {
    try await invoke(name, body: body, options: options).decode(as: type, decoder: decoder)
  }

  /// Invokes a function and decodes the response with a custom closure.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for the invocation.
  ///   - decode: A closure that receives the raw response data and HTTP response, and returns the
  ///     decoded value.
  /// - Returns: The value returned by `decode`.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status or a relay error.
  @available(
    *, deprecated,
    message:
      "Use invoke(_:body:options:) and read FunctionResponse.body or FunctionResponse.decode(as:)."
  )
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws -> Response {
    let response = try await rawInvoke(
      functionName: functionName, body: nil, invokeOptions: options
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
  @available(*, deprecated, message: "Use invoke(_:body:options:as:decoder:) instead.")
  @_disfavoredOverload
  public func invoke<T: Decodable>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decoder: JSONDecoder? = nil
  ) async throws -> T {
    try await invoke(functionName, body: nil, options: options, decoder: decoder)
  }

  /// Invokes a function and discards any response body.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for the invocation.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status or a relay error.
  @available(*, deprecated, message: "Use invoke(_:body:options:) instead.")
  @_disfavoredOverload
  public func invoke(
    _ functionName: String,
    options: FunctionInvokeOptions = .init()
  ) async throws {
    try await invoke(functionName, body: nil, options: options)
  }

  private func rawInvoke(
    functionName: String,
    body: FunctionBody?,
    invokeOptions: FunctionInvokeOptions
  ) async throws -> Helpers.HTTPResponse {
    let request = buildRequest(functionName: functionName, body: body, options: invokeOptions)
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

  /// Invokes a function and returns once the response head arrives, with the body still streaming.
  ///
  /// The function must return a `text/event-stream` content type for this to work correctly.
  ///
  /// > Note: This method uses a separate `URLSession` from the rest of the client.
  /// - Parameters:
  ///   - name: The name of the function to invoke.
  ///   - body: The request body, or `nil` to send none.
  ///   - options: Options for the invocation.
  /// - Returns: The response head and the body as an asynchronous stream of `Data` chunks.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status or a relay error, or
  ///   a `URLError` if the connection fails before the response head arrives.
  public func stream(
    _ name: String,
    body: FunctionBody? = nil,
    options: FunctionInvokeOptions = .init()
  ) async throws -> FunctionStreamResponse {
    let (stream, delegate) = streamResponse(name, body: body, options: options)

    var head: HTTPURLResponse?
    for try await response in delegate.head {
      head = response
      break
    }
    guard let head else { throw URLError(.badServerResponse) }

    return FunctionStreamResponse(
      status: HTTPTypes.HTTPResponse.Status(code: head.statusCode),
      headers: HTTPFields(head.allHeaderFields as? [String: String] ?? [:]),
      body: stream
    )
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
  @available(*, deprecated, message: "Use stream(_:body:options:) instead.")
  public func _invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) -> AsyncThrowingStream<Data, any Error> {
    streamResponse(functionName, body: nil, options: invokeOptions).stream
  }

  func streamResponse(
    _ functionName: String,
    body: FunctionBody? = nil,
    options invokeOptions: FunctionInvokeOptions
  ) -> (stream: AsyncThrowingStream<Data, any Error>, delegate: StreamResponseDelegate) {
    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    let delegate = StreamResponseDelegate(continuation: continuation)

    let session = URLSession(
      configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)

    let urlRequest = buildRequest(functionName: functionName, body: body, options: invokeOptions)
      .urlRequest

    let task = session.dataTask(with: urlRequest)
    task.resume()

    continuation.onTermination = { _ in
      session.invalidateAndCancel()
    }

    return (stream, delegate)
  }

  private func buildRequest(
    functionName: String, body: FunctionBody?, options: FunctionInvokeOptions
  ) -> Helpers.HTTPRequest {
    var query = options.query
    var headers = mutableState.headers
    if let body {
      headers[.contentType] = body.contentType
    }
    headers.merge(with: options.headers)

    var request = Helpers.HTTPRequest(
      url: url.appendingPathComponent(functionName),
      method: options.method,
      query: query,
      headers: headers,
      body: body?.data ?? options.body,
      timeoutInterval: options.timeout?.timeInterval ?? FunctionsClient.requestIdleTimeout
    )

    if let region = options.region?.rawValue ?? region {
      request.headers[.xRegion] = region
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region))
      request.query = query
    }

    return request
  }
}
