import ConcurrencyExtras
public import Foundation
import HTTPRuntime
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

  private let fetch: FetchHandler
  private let mutableState = LockIsolated(MutableState())
  private let sessionConfiguration: URLSessionConfiguration

  var headers: [String: String] {
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
      decoder: decoder,
      fetch: fetch
    )
  }

  init(
    url: URL,
    headers: [String: String],
    region: String?,
    decoder: JSONDecoder = JSONDecoder(),
    fetch: @escaping FetchHandler,
    sessionConfiguration: URLSessionConfiguration = .default
  ) {
    self.url = url
    self.region = region
    self.decoder = decoder
    self.fetch = fetch
    self.sessionConfiguration = sessionConfiguration

    mutableState.withValue {
      $0.headers = headers
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
      fetch: fetch,
      decoder: decoder
    )
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
    let transport = FetchHandlerTransport(fetch: fetch)

    let response: HTTPRuntime.HTTPResponse
    do {
      response = try await transport.send(request)
    } catch HTTPRuntime.HTTPError.transport(let underlying) {
      throw underlying
    }

    guard
      let httpResponse = HTTPURLResponse(
        url: request.url, statusCode: response.head.status, httpVersion: nil,
        headerFields: response.head.headers)
    else {
      throw URLError(.badServerResponse)
    }

    guard 200..<300 ~= response.head.status else {
      throw FunctionsError.httpError(code: response.head.status, data: response.body)
    }

    if response.head.header("x-relay-error") == "true" {
      throw FunctionsError.relayError
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
  ) -> AsyncThrowingStream<Data, any Error> {
    let request = buildRequest(functionName: functionName, options: invokeOptions)
    let transport = URLSessionTransport(configuration: sessionConfiguration)

    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()

    let task = Task {
      do {
        let responseStream = try await transport.stream(request)

        guard 200..<300 ~= responseStream.head.status else {
          throw FunctionsError.httpError(code: responseStream.head.status, data: Data())
        }
        if responseStream.head.header("x-relay-error") == "true" {
          throw FunctionsError.relayError
        }

        for try await chunk in responseStream.body {
          continuation.yield(chunk)
        }
        continuation.finish()
      } catch HTTPRuntime.HTTPError.transport(let underlying) {
        continuation.finish(throwing: underlying)
      } catch {
        continuation.finish(throwing: error)
      }
    }

    continuation.onTermination = { _ in task.cancel() }

    return stream
  }

  private func buildRequest(functionName: String, options: FunctionInvokeOptions)
    -> HTTPRuntime.HTTPRequest
  {
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

  /// Adapts the stored `fetch:` closure to `HTTPTransport` for the buffered `invoke*` path.
  /// Only `send(_:uploadProgress:)` is used — streaming always goes through
  /// `URLSessionTransport` directly (see `_invokeWithStreamedResponse`), never through the
  /// public `fetch:` closure, so `stream(_:)` here is unreachable.
  private struct FetchHandlerTransport: HTTPTransport {
    let fetch: FunctionsClient.FetchHandler

    func send(_ request: HTTPRuntime.HTTPRequest, uploadProgress: ProgressHandler?)
      async throws(HTTPRuntime.HTTPError)
      -> HTTPRuntime.HTTPResponse
    {
      let urlRequest = Self.makeURLRequest(request)
      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await fetch(urlRequest)
      } catch {
        throw HTTPRuntime.HTTPError.transport(error)
      }
      guard let http = response as? HTTPURLResponse else {
        throw HTTPRuntime.HTTPError.transport(URLError(.badServerResponse))
      }
      var headers: [String: String] = [:]
      for (key, value) in http.allHeaderFields {
        if let key = key as? String, let value = value as? String {
          headers[key] = value
        }
      }
      return HTTPRuntime.HTTPResponse(
        head: HTTPResponseHead(status: http.statusCode, headers: headers), body: data)
    }

    func stream(_ request: HTTPRuntime.HTTPRequest) async throws(HTTPRuntime.HTTPError)
      -> HTTPResponseStream
    {
      fatalError(
        "FetchHandlerTransport does not support streaming; use URLSessionTransport instead")
    }

    static func makeURLRequest(_ request: HTTPRuntime.HTTPRequest) -> URLRequest {
      var urlRequest = URLRequest(
        url: request.url, timeoutInterval: FunctionsClient.requestIdleTimeout)
      urlRequest.httpMethod = request.method.rawValue
      for (name, value) in request.headers {
        urlRequest.setValue(value, forHTTPHeaderField: name)
      }
      if case .data(let payload) = request.body {
        urlRequest.httpBody = payload
      }
      return urlRequest
    }
  }
}
