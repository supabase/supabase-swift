import Foundation

// MARK: - FunctionsResponseInterceptor

/// A `ResponseInterceptor` that validates Edge Function responses and converts non-successful
/// outcomes into `FunctionsClientV2.FunctionsError` values.
///
/// Two failure conditions are detected:
/// 1. The HTTP status code is outside the `200..<300` range.
/// 2. The response carries the `X-Relay-Error: true` header, which signals that the
///    Supabase relay layer itself failed before the function could execute.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct FunctionsResponseInterceptor: ResponseInterceptor {
  /// Inspects the response status and relay-error header, throwing a ``FunctionsClientV2/FunctionsError``
  /// when either condition is detected.
  ///
  /// - Parameters:
  ///   - body: The ``ResponseBody`` received from the server.
  ///   - response: The `HTTPURLResponse` received from the server.
  /// - Returns: The unmodified `(body, response)` tuple when the response is successful.
  /// - Throws: ``FunctionsClientV2/FunctionsError`` on a non-2xx status code or a relay error.
  func intercept(
    body: ResponseBody,
    response: HTTPURLResponse
  ) async throws -> (ResponseBody, HTTPURLResponse) {
    guard 200..<300 ~= response.statusCode else {
      let data = try await body.collect()
      let functionName = response.url?.lastPathComponent ?? "<unknown>"
      throw FunctionsClientV2.FunctionsError(
        "Failed to invoke function '\(functionName)'. Status code: \(response.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "<non-UTF8 response>")"
      )
    }

    if response.value(forHTTPHeaderField: "X-Relay-Error") == "true" {
      let data = try await body.collect()
      let functionName = response.url?.lastPathComponent ?? "<unknown>"
      throw FunctionsClientV2.FunctionsError(
        "Function '\(functionName)' invocation failed with a relay error. Response: \(String(data: data, encoding: .utf8) ?? "<non-UTF8 response>")"
      )
    }

    return (body, response)
  }
}

// MARK: - FunctionsClientV2

/// A client for invoking Supabase Edge Functions over HTTP.
///
/// `FunctionsClientV2` is an `actor` that manages the full lifecycle of Edge Function calls:
/// authentication, request building, response validation, and optional decoding.
///
/// ## Basic usage
///
/// ```swift
/// let client = FunctionsClientV2(url: functionsURL, headers: ["Authorization": "Bearer \(token)"])
///
/// // Fire-and-forget style – receive raw Data
/// let (data, _) = try await client.invoke("my-function")
///
/// // Typed decoding
/// let (result, _): (MyResponse, _) = try await client.invoke(as: MyResponse.self, "my-function")
///
/// // Streaming
/// let (bytes, _) = try await client.streamInvoke("my-function")
/// for try await byte in bytes { … }
/// ```
///
/// ## Authentication
///
/// Call ``setAuth(_:)`` to update the `Authorization` header used for all subsequent invocations.
/// Pass `nil` to remove the header entirely.
@available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
public actor FunctionsClientV2 {

  // MARK: Properties

  /// The base URL of the Edge Functions endpoint.
  public var url: URL { session.baseURL }

  /// HTTP headers sent with every function invocation.
  ///
  /// Headers provided in ``InvokeOptions`` are merged on top of these at call time,
  /// with per-invocation values taking precedence.
  public var headers: [String: String]

  /// The optional geographic region in which functions are invoked.
  private let region: FunctionRegion?

  /// The underlying HTTP session used to build and execute requests.
  private let session: HTTPSession

  // MARK: Nested Types

  /// An error thrown when an Edge Function invocation fails.
  public struct FunctionsError: Error, LocalizedError {
    /// A human-readable description of the failure, including the function name,
    /// HTTP status code, and the raw response body where available.
    public let message: String

    init(_ message: String) {
      self.message = message
    }

    /// Returns ``message`` as the localised error description.
    public var errorDescription: String? { message }
  }

  /// Configuration options for a single function invocation.
  public struct InvokeOptions: Sendable {
    /// The HTTP method to use. Defaults to `"POST"`.
    public var method: String = "POST"

    /// An optional HTTP body payload to send with the request.
    public var body: Data? = nil

    /// Additional HTTP headers merged on top of the client-level ``FunctionsClientV2/headers``.
    /// Per-invocation values take precedence over client-level values.
    public var headers: [String: String] = [:]

    /// URL query parameters appended to the function's URL.
    public var query: [String: String] = [:]
  }

  // MARK: Initializers

  /// Creates a `FunctionsClientV2` with full control over the underlying session.
  ///
  /// This initializer is intended for use by the Supabase SDK internals (e.g. `SupabaseClient`),
  /// which need to inject a shared `URLSessionConfiguration`, request adapters, and response
  /// interceptors.
  ///
  /// The provided `responseInterceptor` (if any) is composed with
  /// ``FunctionsResponseInterceptor`` so that Edge Function error validation always runs last.
  ///
  /// - Parameters:
  ///   - baseURL: The base URL of the Edge Functions endpoint.
  ///   - sessionConfiguration: The `URLSessionConfiguration` for the underlying session.
  ///     Defaults to `.default`.
  ///   - requestAdapter: An optional adapter applied to every outgoing request (e.g. for
  ///     signing or injecting auth headers).
  ///   - responseInterceptor: An optional interceptor applied to every response before
  ///     ``FunctionsResponseInterceptor`` validates it.
  ///   - headers: HTTP headers sent with every invocation. Defaults to empty.
  ///   - region: The geographic region in which to invoke functions. Defaults to `nil`
  ///     (uses the project's default region).
  package init(
    baseURL: URL,
    sessionConfiguration: URLSessionConfiguration = .default,
    requestAdapter: (any RequestAdapter)? = nil,
    responseInterceptor: (any ResponseInterceptor)? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil
  ) {
    self.session = HTTPSession(
      baseURL: baseURL,
      configuration: sessionConfiguration,
      requestAdapter: requestAdapter,
      responseInterceptor: responseInterceptor != nil
        ? Interceptors([responseInterceptor!, FunctionsResponseInterceptor()])
        : FunctionsResponseInterceptor()
    )
    self.headers = headers
    self.region = region
    if self.headers["X-Client-Info"] == nil {
      self.headers["X-Client-Info"] = "functions-swift/\(version)"
    }
  }

  /// Creates a `FunctionsClientV2` with a URL and optional headers and region.
  ///
  /// Use this initializer when you are working with the client standalone, outside of
  /// the main `SupabaseClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL of the Edge Functions endpoint.
  ///   - headers: HTTP headers sent with every invocation. Defaults to empty.
  ///   - region: The geographic region in which to invoke functions. Defaults to `nil`
  ///     (uses the project's default region).
  public init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil
  ) {
    self.init(
      baseURL: url,
      sessionConfiguration: .default,
      headers: headers,
      region: region
    )
  }

  // MARK: Authentication

  /// Updates the `Authorization` header used for all subsequent function invocations.
  ///
  /// - Parameter token: The bearer token to use. Pass `nil` to remove the
  ///   `Authorization` header entirely.
  public func setAuth(_ token: String?) {
    headers["Authorization"] = token.map { "Bearer \($0)" }
  }

  // MARK: Invocation

  /// Invokes a function and returns the raw response body and the `HTTPURLResponse`.
  ///
  /// The request is built by merging ``headers`` with any headers in `options`, then
  /// delegated to the underlying ``HTTPSession``. The response is validated by
  /// ``FunctionsResponseInterceptor`` before being returned.
  ///
  /// - Parameters:
  ///   - functionName: The name of the Edge Function to invoke.
  ///   - options: A closure used to configure the invocation. Receives an
  ///     `inout` ``InvokeOptions`` value so individual fields can be set selectively.
  ///     Defaults to a no-op closure.
  /// - Returns: A tuple of the raw `Data` response body and the `HTTPURLResponse`.
  /// - Throws: ``FunctionsError`` if the function returns a non-2xx status or a relay error,
  ///   or any network-level error thrown by the underlying session.
  public func invoke(
    _ functionName: String,
    options: (inout InvokeOptions) -> Void = { _ in }
  ) async throws -> (Data, HTTPURLResponse) {
    var opt = InvokeOptions()
    options(&opt)

    let path = "/\(functionName)"
    let allHeaders = self.headers.merging(opt.headers) { _, new in new }
    let (data, response) = try await session.data(
      opt.method, path: path, headers: allHeaders, query: opt.query, body: opt.body)
    return (data, response)
  }

  /// Invokes a function, decodes the response body, and returns both the decoded value
  /// and the `HTTPURLResponse`.
  ///
  /// This is a convenience wrapper around ``invoke(_:options:)`` that feeds the raw
  /// response `Data` through a `JSONDecoder` before returning.
  ///
  /// - Parameters:
  ///   - as: The `Decodable` type to decode the response body into.
  ///   - decoder: The `JSONDecoder` to use. Defaults to `JSONDecoder()`.
  ///   - functionName: The name of the Edge Function to invoke.
  ///   - options: A closure used to configure the invocation. Defaults to a no-op closure.
  /// - Returns: A tuple of the decoded `Response` value and the `HTTPURLResponse`.
  /// - Throws: ``FunctionsError`` on invocation failure, `DecodingError` if the response
  ///   body cannot be decoded into `Response`, or any network-level error.
  public func invoke<Response: Decodable>(
    as: Response.Type,
    decoder: JSONDecoder = JSONDecoder(),
    _ functionName: String,
    options: (inout InvokeOptions) -> Void = { _ in }
  ) async throws -> (Response, HTTPURLResponse) {
    let (data, response) = try await invoke(functionName, options: options)
    let decoded = try decoder.decode(Response.self, from: data)
    return (decoded, response)
  }

  /// Invokes a function and returns the response body as an asynchronous byte stream.
  ///
  /// Bytes are delivered lazily without buffering the entire response in memory, making
  /// this method well-suited for large or continuously streamed responses (e.g. server-sent
  /// events or chunked JSON).
  ///
  /// - Parameters:
  ///   - functionName: The name of the Edge Function to invoke.
  ///   - options: A closure used to configure the invocation. Defaults to a no-op closure.
  /// - Returns: A tuple of `URLSession.AsyncBytes` and the `HTTPURLResponse`.
  /// - Throws: ``FunctionsError`` on invocation failure, or any network-level error thrown
  ///   by the underlying session.
  public func streamInvoke(
    _ functionName: String,
    options: (inout InvokeOptions) -> Void = { _ in }
  ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
    var opt = InvokeOptions()
    options(&opt)

    let path = "/\(functionName)"
    let allHeaders = self.headers.merging(opt.headers) { _, new in new }
    let (bytes, response) = try await session.bytes(
      opt.method, path: path, headers: allHeaders, query: opt.query, body: opt.body)
    return (bytes, response)
  }
}
