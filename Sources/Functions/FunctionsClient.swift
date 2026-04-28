import ConcurrencyExtras
import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

/// A client for invoking Supabase Edge Functions.
///
/// `FunctionsClient` provides methods for calling Edge Functions deployed on your Supabase project.
/// It handles authentication token injection, region routing, and response decoding.
///
/// ## Basic usage
///
/// ```swift
/// let client = FunctionsClient(
///   url: URL(string: "https://<project-ref>.supabase.co/functions/v1")!,
///   headers: ["Authorization": "Bearer <anon-key>"]
/// )
///
/// // Invoke a function and decode the JSON response
/// let (result, _): (MyResponse, _) = try await client.invokeDecodable("my-function")
///
/// // Invoke a function and handle raw data
/// let (data, response) = try await client.invoke("my-function") {
///   $0.method = .post
///   $0.body = try! JSONEncoder().encode(myPayload)
///   $0.headers["Content-Type"] = "application/json"
/// }
/// ```
///
/// When used via ``SupabaseClient``, authentication tokens are automatically refreshed and injected
/// into every request. You do not need to manage ``setAuth(token:)`` manually in that case.
public actor FunctionsClient {
  /// The maximum time an Edge Function may be idle before the gateway returns a 504.
  ///
  /// Supabase enforces a 150-second request idle timeout for Edge Functions. The client
  /// configures the underlying `URLSession` with this value so local timeouts align with
  /// the server-side limit.
  ///
  /// See: https://supabase.com/docs/guides/functions/limits
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL used to build per-function request URLs.
  ///
  /// Individual function URLs are formed by appending the function name to this URL,
  /// e.g. `https://<project-ref>.supabase.co/functions/v1/my-function`.
  public let url: URL

  /// The default region in which functions are invoked.
  ///
  /// Per-invocation overrides via ``FunctionInvokeOptions/region`` take
  /// precedence over this value. Pass `nil` to let Supabase route to the nearest region
  /// automatically.
  public let region: FunctionRegion?

  /// The JSON decoder used to decode response bodies in ``invokeDecodable(_:decoder:options:)``.
  ///
  /// Per-call override is also available via the `decoder`
  /// parameter of ``invokeDecodable(_:decoder:options:)``.
  public let decoder: JSONDecoder

  /// The HTTP headers sent with every request.
  ///
  /// Per-invocation headers supplied via ``FunctionInvokeOptions/headers`` are merged on
  /// top of these values, with the per-invocation values winning on collision.
  public private(set) var headers: [String: String] = [:]

  private let http: _HTTPClient

  /// Creates a `FunctionsClient` for standalone use (without a ``SupabaseClient``).
  ///
  /// Use this initialiser when you want to call Edge Functions independently, without the
  /// broader Supabase client stack. For most apps you should create a ``SupabaseClient`` and
  /// access its `functions` property instead.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions endpoint,
  ///     e.g. `https://<project-ref>.supabase.co/functions/v1`.
  ///   - headers: Additional headers included in every request. Defaults to an empty dictionary.
  ///     An `X-Client-Info` header is always added automatically.
  ///   - region: The default region to invoke functions in. Defaults to `nil` (automatic routing).
  ///   - session: The `URLSession` used to perform HTTP requests. Defaults to a new session with
  ///     ``requestIdleTimeout`` applied to `timeoutIntervalForRequest`.
  ///   - decoder: The `JSONDecoder` used by ``invokeDecodable(_:decoder:options:)``.
  ///     Defaults to `JSONDecoder()`.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let functions = FunctionsClient(
  ///   url: URL(string: "https://<project-ref>.supabase.co/functions/v1")!,
  ///   headers: ["apikey": "<publishable-or-secret-key>", "Authorization": "Bearer <authorization-token>"]
  /// )
  /// ```
  public init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    session: URLSession = URLSession(configuration: .default),
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region,
      session: session,
      decoder: decoder,
      tokenProvider: nil
    )
  }

  package init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    session: URLSession = URLSession(configuration: .default),
    decoder: JSONDecoder = JSONDecoder(),
    tokenProvider: TokenProvider?
  ) {
    self.url = url
    self.region = region
    self.decoder = decoder
    session.configuration.timeoutIntervalForRequest = Self.requestIdleTimeout
    self.http = _HTTPClient(
      host: url,
      session: session,
      tokenProvider: tokenProvider
    )
    self.headers = headers
    if self.headers["X-Client-Info"] == nil {
      self.headers["X-Client-Info"] = "functions-swift/\(version)"
    }
  }

  /// Updates the `Authorization` header used for subsequent requests.
  ///
  /// Pass a JWT to attach a `Bearer` token, or `nil` to remove the header entirely (e.g. for
  /// public functions that don't require authentication).
  ///
  /// When using ``SupabaseClient``, this method is called automatically whenever the
  /// authenticated session changes — you do not need to call it yourself.
  ///
  /// - Parameter token: A JWT access token, or `nil` to clear the authorization header.
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Attach a token before invoking a protected function
  /// await functions.setAuth(token: session.accessToken)
  /// let (data, _) = try await functions.invoke("protected-function")
  ///
  /// // Remove the token for a public function call
  /// await functions.setAuth(token: nil)
  /// ```
  public func setAuth(token: String?) {
    if let token {
      headers["Authorization"] = "Bearer \(token)"
    } else {
      headers.removeValue(forKey: "Authorization")
    }
  }

  /// Invokes a function and decodes the JSON response body into the inferred `Decodable` type.
  ///
  /// The response body is decoded using the `decoder` parameter if provided, otherwise the
  /// instance-level ``decoder`` is used.
  ///
  /// - Parameters:
  ///   - functionName: The name of the Edge Function to invoke.
  ///   - decoder: An optional `JSONDecoder` to use for this call. When `nil`, falls back to the
  ///     instance ``decoder``. Defaults to `nil`.
  ///   - options: A closure that configures ``FunctionInvokeOptions`` before the request is sent.
  ///     Defaults to a no-op closure.
  /// - Returns: A tuple of the decoded value and the raw `HTTPURLResponse`.
  /// - Throws: ``FunctionsError`` on relay or HTTP errors, or a decoding error if the response
  ///   body cannot be decoded into `T`.
  ///
  /// ## Example
  ///
  /// ```swift
  /// struct HelloResponse: Decodable {
  ///   let message: String
  /// }
  ///
  /// let (response, _): (HelloResponse, _) = try await functions.invokeDecodable("hello") {
  ///   $0.method = .get
  ///   $0.query = ["name": "world"]
  /// }
  /// print(response.message) // "Hello, world!"
  /// ```
  public func invokeDecodable<T: Decodable>(
    _ functionName: String,
    decoder: JSONDecoder? = nil,
    options applyOptions: (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (T, HTTPURLResponse) {
    let (data, response) = try await invoke(functionName, options: applyOptions)
    return (
      try (decoder ?? self.decoder).decode(T.self, from: data),
      response
    )
  }

  /// Invokes a function and returns the raw response body and `HTTPURLResponse`.
  ///
  /// Use this method when you need full control over response handling — for example, when the
  /// function returns non-JSON data, or when you want to inspect status codes and headers directly.
  ///
  /// - Parameters:
  ///   - functionName: The name of the Edge Function to invoke.
  ///   - options: A closure that configures ``FunctionInvokeOptions`` before the request is sent.
  ///     Defaults to a no-op closure.
  /// - Returns: A tuple of the raw `Data` body and the `HTTPURLResponse`.
  /// - Throws: ``FunctionsError/relayError`` if the relay reports an error,
  ///   ``FunctionsError/httpError(code:data:)`` for non-2xx responses, or a transport-level error.
  ///
  /// ## Example
  ///
  /// ```swift
  /// struct RequestBody: Encodable {
  ///   let userId: String
  /// }
  ///
  /// let (data, response) = try await functions.invoke("process-user") {
  ///   $0.method = .post
  ///   $0.body = try! JSONEncoder().encode(RequestBody(userId: "abc123"))
  ///   $0.headers["Content-Type"] = "application/json"
  /// }
  /// print(response.statusCode) // 200
  /// ```
  @discardableResult
  public func invoke(
    _ functionName: String,
    options applyOptions: (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (Data, HTTPURLResponse) {
    var options = FunctionInvokeOptions()
    applyOptions(&options)
    let (functionURL, method, query, allHeaders, body) = requestComponents(
      functionName: functionName,
      options: options
    )

    do {
      let (data, response) = try await http.fetchData(
        method,
        url: functionURL,
        query: query.isEmpty ? nil : query,
        body: body,
        headers: allHeaders.isEmpty ? nil : allHeaders
      )

      if response.value(forHTTPHeaderField: "x-relay-error") == "true" {
        throw FunctionsError.relayError
      }

      return (data, response)
    } catch let error as HTTPClientError {
      if case .responseError(let response, let data) = error {
        throw FunctionsError.httpError(code: response.statusCode, data: data)
      }
      throw error
    }
  }

  /// Invokes a function and returns an async byte stream for the response body.
  ///
  /// Use this method for functions that return large payloads or use server-sent events /
  /// chunked transfer encoding. The stream yields individual `UInt8` bytes as they arrive.
  ///
  /// - Parameters:
  ///   - functionName: The name of the Edge Function to invoke.
  ///   - options: A closure that configures ``FunctionInvokeOptions`` before the request is sent.
  ///     Defaults to a no-op closure.
  /// - Returns: A tuple of an `AsyncThrowingStream<UInt8, Error>` and the initial
  ///   `HTTPURLResponse`.
  /// - Throws: ``FunctionsError/relayError`` if the relay reports an error,
  ///   ``FunctionsError/httpError(code:data:)`` for non-2xx responses, or a transport-level error.
  ///
  /// ## Example
  ///
  /// ```swift
  /// let (stream, _) = try await functions.invokeStream("stream-data")
  ///
  /// var buffer = Data()
  /// for try await byte in stream {
  ///   buffer.append(byte)
  /// }
  /// print(String(data: buffer, encoding: .utf8) ?? "")
  /// ```
  @available(macOS 12.0, *)
  public func invokeStream(
    _ functionName: String,
    options applyOptions: (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (AsyncThrowingStream<UInt8, any Error>, HTTPURLResponse) {
    var options = FunctionInvokeOptions()
    applyOptions(&options)
    let (functionURL, method, query, allHeaders, body) = requestComponents(
      functionName: functionName,
      options: options
    )

    do {
      let (bytes, response) = try await http.fetchStream(
        method,
        url: functionURL,
        query: query.isEmpty ? nil : query,
        body: body,
        headers: allHeaders.isEmpty ? nil : allHeaders
      )

      if response.value(forHTTPHeaderField: "x-relay-error") == "true" {
        throw FunctionsError.relayError
      }

      return (bytes, response)
    } catch let error as HTTPClientError {
      if case .responseError(let response, let data) = error {
        throw FunctionsError.httpError(code: response.statusCode, data: data)
      }
      throw error
    }
  }

  private func requestComponents(
    functionName: String,
    options: FunctionInvokeOptions
  ) -> (
    url: URL,
    method: HTTPMethod,
    query: [String: String],
    headers: [String: String],
    body: RequestBody?
  ) {
    let method =
      options.method.flatMap { HTTPMethod(rawValue: $0.rawValue) } ?? .post
    var query = options.query
    var allHeaders = headers.merging(options.headers) { _, new in new }

    if let region = (options.region ?? region)?.rawValue {
      allHeaders["x-region"] = region
      query["forceFunctionRegion"] = region
    }

    let body: RequestBody? = options.body.map { .data($0) }
    return (
      url.appendingPathComponent(functionName), method, query, allHeaders, body
    )
  }
}
