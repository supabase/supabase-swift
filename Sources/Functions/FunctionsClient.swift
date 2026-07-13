import ConcurrencyExtras
public import Foundation
package import HTTPRuntime
public import Helpers
import IssueReporting

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

let version = Helpers.version

/// Options for configuring a ``FunctionsClient``.
public struct FunctionsClientOptions: Sendable {
  /// Additional headers to include in every request.
  public var headers: [String: String]
  /// The region string to invoke functions in.
  public var region: String?
  /// A logger for request and response diagnostics.
  public var logger: (any SupabaseLogger)?
  /// The JSON decoder used to decode function response bodies.
  public var decoder: JSONDecoder
  /// The `URLSession` used to perform requests.
  public var session: URLSession

  /// Creates options for configuring a ``FunctionsClient``.
  /// - Parameters:
  ///   - headers: Additional headers to include in every request.
  ///   - region: The region string to invoke functions in.
  ///   - logger: A logger for request and response diagnostics.
  ///   - decoder: The JSON decoder used to decode function response bodies.
  ///   - session: The `URLSession` used to perform requests.
  public init(
    headers: [String: String] = [:],
    region: String? = nil,
    logger: (any SupabaseLogger)? = nil,
    decoder: JSONDecoder = JSONDecoder(),
    session: URLSession = URLSession(configuration: .default)
  ) {
    self.headers = headers
    self.region = region
    self.logger = logger
    self.decoder = decoder
    self.session = session
  }
}

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
/// - ``init(url:options:)``
/// - ``FunctionsClientOptions``
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
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: String?

  /// The JSON decoder used to decode function response bodies.
  public let decoder: JSONDecoder

  struct MutableState {
    /// Headers to be included in the requests.
    var headers: [String: String] = [:]
  }

  private let mutableState = LockIsolated(MutableState())

  private let transport: any HTTPTransport

  var headers: [String: String] {
    mutableState.headers
  }

  /// Creates a new Functions client.
  /// - Parameters:
  ///   - url: The base URL of the Functions endpoint.
  ///   - options: Options for configuring the client.
  public convenience init(
    url: URL,
    options: FunctionsClientOptions = FunctionsClientOptions()
  ) {
    self.init(
      url: url,
      options: options,
      transport: URLSessionTransport(session: options.session)
    )
  }

  /// Internal initializer, used for testing and by SupabaseClient.
  package init(
    url: URL,
    options: FunctionsClientOptions,
    transport: any HTTPTransport
  ) {
    self.url = url
    self.region = options.region
    self.decoder = options.decoder
    self.transport = transport

    mutableState.withValue {
      $0.headers = options.headers
      // HTTP header names are case-insensitive: don't clobber a caller-provided
      // "x-client-info" (in any casing) with the default value.
      let hasClientInfo = $0.headers.keys.contains {
        $0.caseInsensitiveCompare("X-Client-Info") == .orderedSame
      }
      if !hasClientInfo {
        $0.headers["X-Client-Info"] = "functions-swift/\(version)"
      }
    }
  }

  /// Sets or clears the JWT used in the Authorization header for subsequent requests.
  /// - Parameter token: The JWT to send, or `nil` to remove the Authorization header.
  public func setAuth(token: String?) {
    mutableState.withValue {
      if let token {
        $0.headers["Authorization"] = "Bearer \(token)"
      } else {
        $0.headers["Authorization"] = nil
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
    let (data, response) = try await rawInvoke(
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
  ) async throws -> (data: Data, response: HTTPURLResponse) {
    let request = buildRequest(functionName: functionName, options: invokeOptions)

    let response: HTTPRuntime.HTTPResponse
    do {
      response = try await transport.send(request)
    } catch HTTPRuntime.HTTPError.transport(let underlying) {
      throw underlying
    }

    guard
      let httpResponse = response.head._underlyingHTTPResponse
        ?? HTTPURLResponse(
          url: request.url, statusCode: response.head.status, httpVersion: nil,
          headerFields: response.head.headers)
    else {
      throw URLError(.badServerResponse)
    }

    guard response.head.isSuccess else {
      if response.head.header("x-relay-error") == "true" {
        throw FunctionsError.relayError
      }

      throw FunctionsError.httpError(code: response.head.status, data: response.body)
    }

    return (response.body, httpResponse)
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
  ) async throws -> AsyncThrowingStream<Data, any Error> {
    let request = buildRequest(functionName: functionName, options: invokeOptions)
    let response: HTTPResponseStream

    do {
      response = try await transport.stream(request)
    } catch HTTPRuntime.HTTPError.transport(let underlying) {
      throw underlying
    } catch {
      throw error
    }

    guard response.head.isSuccess else {
      if response.head.header("x-relay-error") == "true" {
        throw FunctionsError.relayError
      }

      let data = try await response.body.collect()
      throw FunctionsError.httpError(code: response.head.status, data: data)
    }

    return response.body
  }

  private func buildRequest(
    functionName: String,
    options: FunctionInvokeOptions
  ) -> HTTPRuntime.HTTPRequest {
    var query = options.query
    var requestHeaders = mutableState.headers.merging(options.headers) { $1 }

    if let region = options.region ?? region {
      requestHeaders["x-region"] = region
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region))
    }

    let requestURL = url.appendingPathComponent(functionName).appendingQueryItems(query)

    return HTTPRuntime.HTTPRequest(
      method: FunctionInvokeOptions.httpMethod(options.method) ?? .post,
      url: requestURL,
      headers: requestHeaders,
      body: options.body.map { HTTPBody.data($0) }
    )
  }

  /// Adapts the stored `fetch:` closure to `HTTPTransport`, for clients built via the
  /// deprecated `fetch:`-closure initializers. The `fetch:` closure is inherently buffered
  /// (it returns a complete `(Data, URLResponse)`), so it can't back real streaming —
  /// `stream(_:)` falls back to a plain `URLSessionTransport` instead, independent of the
  /// custom `fetch:` closure.
  struct FetchHandlerTransport: HTTPTransport {
    let fetch: FunctionsClient.FetchHandler

    func send(
      _ request: HTTPRuntime.HTTPRequest,
      uploadProgress: ProgressHandler?
    ) async throws -> HTTPRuntime.HTTPResponse {
      if uploadProgress != nil {
        reportIssue(
          "Upload progress is not supported with a custom fetch handler."
        )
      }
      let urlRequest = Self.makeURLRequest(request)
      let (data, response) = try await fetch(urlRequest)

      return HTTPRuntime.HTTPResponse(
        head: URLSessionTransport.makeHead(response), body: data)
    }

    func stream(_ request: HTTPRuntime.HTTPRequest) async throws -> HTTPResponseStream {
      try await URLSessionTransport().stream(request)
    }

    static func makeURLRequest(_ request: HTTPRuntime.HTTPRequest) -> URLRequest {
      var urlRequest = URLSessionTransport.makeURLRequest(request)
      urlRequest.timeoutInterval = FunctionsClient.requestIdleTimeout
      return urlRequest
    }
  }
}
