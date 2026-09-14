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
/// - ``init(url:headers:region:logger:http:decoder:retryPolicy:accessToken:)-(_,_,FunctionRegion?,_,_,_,_,_)``
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
  /// `PostgrestClient.Configuration.decoder` uses. ``FunctionsError/response`` carries the
  /// response body as raw `Data` rather than decoding it, so this setting never affects error
  /// handling.
  public let decoder: JSONDecoder

  let headers: HTTPFields

  private let http: HTTPClient
  private let accessToken: (@Sendable () async throws -> String?)?

  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region string to invoke functions in.
  ///   - logger: A logger for request and response diagnostics. Defaults to a build-config-aware logger.
  ///   - http: The transport and middleware chain every request goes through.
  ///   - decoder: The JSON decoder used to decode response bodies.
  ///   - retryPolicy: How transient failures are retried. Defaults to ``RetryPolicy/default``,
  ///     which only replays idempotent methods, so a plain `POST` invocation is never retried.
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
    http: HTTPClientConfiguration = .init(),
    decoder: JSONDecoder = JSONDecoder(),
    retryPolicy: RetryPolicy = .default,
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) {
    var logger = logger
    logger[metadataKey: "system"] = "functions"
    let httpClient = HTTPClient(
      configuration: http,
      appending: [
        RetryRequestInterceptor(policy: retryPolicy),
        LoggerInterceptor(logger: logger),
      ])

    self.init(
      url: url,
      headers: headers,
      region: region,
      decoder: decoder,
      http: httpClient,
      accessToken: accessToken
    )
  }

  init(
    url: URL,
    headers: [String: String],
    region: String?,
    decoder: JSONDecoder = JSONDecoder(),
    http: HTTPClient,
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
  ///   - http: The transport and middleware chain every request goes through.
  ///   - decoder: The JSON decoder used to decode response bodies.
  ///   - retryPolicy: How transient failures are retried. Defaults to ``RetryPolicy/default``,
  ///     which only replays idempotent methods, so a plain `POST` invocation is never retried.
  ///   - accessToken: An async closure returning the current access token, resolved fresh for
  ///     every request and sent as `Authorization: Bearer <token>`. `nil` (the default) sends no
  ///     bearer token; a per-invocation header set via ``FunctionInvokeOptions`` still takes
  ///     precedence over it.
  public init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: Logging.Logger = supabaseDefaultLogger(label: "io.supabase.functions"),
    http: HTTPClientConfiguration = .init(),
    decoder: JSONDecoder = JSONDecoder(),
    retryPolicy: RetryPolicy = .default,
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region?.rawValue,
      logger: logger,
      http: http,
      decoder: decoder,
      retryPolicy: retryPolicy,
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
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status, a relay error occurs,
  ///   or the request fails.
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (Data, HTTPResponse) throws -> Response
  ) async throws -> Response {
    let (response, data) = try await rawInvoke(
      functionName: functionName, invokeOptions: options
    )
    return try decode(data, response)
  }

  /// Invokes a function and JSON-decodes the response body into `T`.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for the invocation.
  ///   - decoder: The JSON decoder to use. Defaults to the client's ``decoder`` when `nil`.
  /// - Returns: The decoded `T`.
  /// - Throws: ``FunctionsError`` with kind ``FunctionsError/Kind-swift.struct/decoding`` if the
  ///   response body cannot be decoded as `T`, or another kind for relay, HTTP and transport
  ///   failures.
  public func invoke<T: Decodable>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decoder: JSONDecoder? = nil
  ) async throws -> T {
    let decoder = decoder ?? self.decoder
    return try await invoke(functionName, options: options) { data, _ in
      do {
        return try decoder.decode(T.self, from: data)
      } catch {
        throw FunctionsError(
          kind: .decoding,
          message: "Failed to decode the Edge Function response as \(T.self).",
          underlyingError: error
        )
      }
    }
  }

  /// Invokes a function and discards any response body.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for the invocation.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status, a relay error occurs,
  ///   or the request fails.
  public func invoke(
    _ functionName: String,
    options: FunctionInvokeOptions = .init()
  ) async throws {
    try await invoke(functionName, options: options) { _, _ in () }
  }

  private func rawInvoke(
    functionName: String,
    invokeOptions: FunctionInvokeOptions
  ) async throws -> (HTTPResponse, Data) {
    let (request, body) = try await buildRequest(functionName: functionName, options: invokeOptions)

    let response: HTTPResponse
    let data: Data
    do {
      (response, data) = try await http.send(
        request, body: body, timeout: Self.timeout(for: invokeOptions))
    } catch {
      // Only the network layer's own failures are relabelled. `CancellationError`, and anything
      // thrown by user code that runs inside `send` (a custom `ClientTransport` or middleware, an `accessToken` closure),
      // propagate as themselves.
      guard let urlError = error as? URLError else { throw error }
      throw FunctionsError(
        kind: .transport, message: urlError.localizedDescription, underlyingError: urlError)
    }

    if response.headerFields[.xRelayError] == "true" {
      throw FunctionsError(
        kind: .relay,
        message: "Relay Error invoking the Edge Function",
        response: HTTPErrorResponse(response, body: data)
      )
    }

    guard response.status.kind == .successful else {
      throw FunctionsError(
        kind: .http,
        message: "Edge Function returned a non-2xx status code: \(response.status.code)",
        response: HTTPErrorResponse(response, body: data)
      )
    }

    return (response, data)
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
      // Built outside the catch below: an error from the `accessToken` closure is the caller's
      // own and must propagate unchanged, even when it happens to be a `URLError`.
      let request: HTTPRequest
      let requestBody: Data?
      do {
        (request, requestBody) = try await buildRequest(
          functionName: functionName, options: invokeOptions)
      } catch {
        continuation.finish(throwing: error)
        return
      }

      do {
        let (head, body) = try await http.stream(
          request, body: requestBody.map { HTTPBody($0) }, timeout: Self.timeout(for: invokeOptions)
        )

        if head.headerFields[.xRelayError] == "true" {
          var data = Data()
          if let body { data = try await Data(collecting: body, upTo: .max) }
          throw FunctionsError(
            kind: .relay,
            message: "Relay Error invoking the Edge Function",
            response: HTTPErrorResponse(head, body: data)
          )
        }
        guard head.status.kind == .successful else {
          var data = Data()
          if let body { data = try await Data(collecting: body, upTo: .max) }
          throw FunctionsError(
            kind: .http,
            message: "Edge Function returned a non-2xx status code: \(head.status.code)",
            response: HTTPErrorResponse(head, body: data)
          )
        }
        if let body {
          for try await chunk in body {
            continuation.yield(Data(chunk))
          }
        }
        continuation.finish()
      } catch let urlError as URLError {
        // Only the network layer's own failures are relabelled. `CancellationError`, a
        // `FunctionsError` thrown above and errors from a user's `accessToken` closure propagate
        // as themselves.
        continuation.finish(
          throwing: FunctionsError(
            kind: .transport, message: urlError.localizedDescription, underlyingError: urlError))
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }

  private static func timeout(for options: FunctionInvokeOptions) -> TimeInterval {
    options.timeoutInterval ?? requestIdleTimeout
  }

  private func buildRequest(functionName: String, options: FunctionInvokeOptions)
    async throws -> (HTTPRequest, Data?)
  {
    var headers = headers
    if let token = try await accessToken?() {
      headers[.authorization] = "Bearer \(token)"
    }
    headers = headers.merging(with: options.headers)

    var query = options.query
    if let region = options.region ?? region {
      headers[.xRegion] = region
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region))
    }

    let request = HTTPRequest(
      method: FunctionInvokeOptions.httpMethod(options.method) ?? .post,
      url: url.appendingPathComponent(functionName),
      query: query,
      headerFields: headers
    )
    return (request, options.body)
  }
}
