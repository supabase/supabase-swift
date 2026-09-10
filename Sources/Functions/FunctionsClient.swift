public import Foundation
import HTTPTypes
public import Helpers
public import Logging

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

let version = Helpers.version

/// A client for invoking Supabase Edge Functions.
///
/// Obtain an instance from `SupabaseClient.functions` rather than creating one directly.
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
/// - ``init(url:headers:region:logger:transport:middlewares:decoder:accessToken:)-(_,_,FunctionRegion?,_,_,_,_,_)``
///
/// ### Invoking Functions
/// - ``invoke(_:options:decode:)``
/// - ``invoke(_:options:decoder:)``
/// - ``invoke(_:options:)``
///
/// ### Configuration
/// - ``decoder``
/// - ``requestIdleTimeout``
public struct FunctionsClient: Sendable {
  /// The maximum time an Edge Function may run before the gateway returns a 504 error (150 seconds).
  ///
  /// Can be overridden per-invocation via ``FunctionInvokeOptions/init(method:headers:region:timeoutInterval:)``.
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: String?

  /// The JSON decoder used to decode function response bodies.
  ///
  /// Individual calls to ``invoke(_:options:decoder:)`` can override this per call — a
  /// client-wide default with a per-call override, the same pattern PostgREST's
  /// `PostgrestClient.Configuration.decoder` uses. ``FunctionsError/httpError(code:data:)``
  /// carries the response body as raw `Data` rather than decoding it, so this setting never
  /// affects error handling.
  public let decoder: JSONDecoder

  let headers: HTTPFields

  private let http: any HTTPClientType
  private let accessToken: (@Sendable () async throws -> String?)?

  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region string to invoke functions in.
  ///   - logger: A logger for request and response diagnostics. Defaults to a build-config-aware logger.
  ///   - transport: The transport every request goes through. Defaults to ``URLSessionTransport``.
  ///   - middlewares: Middlewares run, in order, before the request reaches `transport`.
  ///   - decoder: The JSON decoder used to decode response bodies.
  ///   - accessToken: An async closure returning the current access token, resolved fresh for
  ///     every request and sent as `Authorization: Bearer <token>`. `nil` (the default) sends no
  ///     bearer token; a per-invocation header set via ``FunctionInvokeOptions`` still takes
  ///     precedence over it.
  @_disfavoredOverload
  public init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.functions"),
    transport: any ClientTransport = URLSessionTransport(),
    middlewares: [any ClientMiddleware] = [],
    decoder: JSONDecoder = JSONDecoder(),
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) {
    var logger = logger
    logger[metadataKey: "system"] = "functions"
    let http = HTTPClient(
      transport: transport, middlewares: middlewares + [LoggerInterceptor(logger: logger)])

    self.init(
      url: url,
      headers: headers,
      region: region,
      decoder: decoder,
      http: http,
      accessToken: accessToken
    )
  }

  init(
    url: URL,
    headers: [String: String],
    region: String?,
    decoder: JSONDecoder = JSONDecoder(),
    http: any HTTPClientType,
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) {
    self.url = url
    self.region = region
    self.decoder = decoder
    self.http = http
    self.accessToken = accessToken

    var headers = HTTPFields(headers)
    if headers[.xClientInfo] == nil {
      headers[.xClientInfo] = "functions-swift/\(version)"
    }
    self.headers = headers
  }

  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region to invoke functions in.
  ///   - logger: A logger for request and response diagnostics. Defaults to a build-config-aware logger.
  ///   - transport: The transport every request goes through. Defaults to ``URLSessionTransport``.
  ///   - middlewares: Middlewares run, in order, before the request reaches `transport`.
  ///   - decoder: The JSON decoder used to decode response bodies.
  ///   - accessToken: An async closure returning the current access token, resolved fresh for
  ///     every request and sent as `Authorization: Bearer <token>`. `nil` (the default) sends no
  ///     bearer token; a per-invocation header set via ``FunctionInvokeOptions`` still takes
  ///     precedence over it.
  public init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.functions"),
    transport: any ClientTransport = URLSessionTransport(),
    middlewares: [any ClientMiddleware] = [],
    decoder: JSONDecoder = JSONDecoder(),
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region?.rawValue,
      logger: logger,
      transport: transport,
      middlewares: middlewares,
      decoder: decoder,
      accessToken: accessToken
    )
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
    let request = try await buildRequest(functionName: functionName, options: invokeOptions)
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
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for the invocation.
  /// - Returns: An `AsyncThrowingStream` that yields response data chunks as they arrive.
  public func _invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) -> AsyncThrowingStream<Data, any Error> {
    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    let task = Task {
      do {
        let request = try await buildRequest(functionName: functionName, options: invokeOptions)
        let (head, body) = try await http.stream(request)

        if head.headerFields[.xRelayError] == "true" {
          throw FunctionsError.relayError
        }
        guard head.status.kind == .successful else {
          var data = Data()
          if let body { data = try await Data(collecting: body, upTo: .max) }
          throw FunctionsError.httpError(code: head.status.code, data: data)
        }
        if let body {
          for try await chunk in body {
            continuation.yield(Data(chunk))
          }
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }

  private func buildRequest(functionName: String, options: FunctionInvokeOptions)
    async throws -> Helpers.HTTPRequest
  {
    var headers = headers
    if let token = try await accessToken?() {
      headers[.authorization] = "Bearer \(token)"
    }
    headers = headers.merging(with: options.headers)

    var query = options.query
    var request = HTTPRequest(
      url: url.appendingPathComponent(functionName),
      method: FunctionInvokeOptions.httpMethod(options.method) ?? .post,
      query: query,
      headers: headers,
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
