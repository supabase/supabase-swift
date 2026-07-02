import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

/// An actor representing a client for invoking functions.
public final class FunctionsClient: Sendable {
  /// Fetch handler used to make requests.
  public typealias FetchHandler =
    @Sendable (_ request: URLRequest) async throws -> (
      Data, URLResponse
    )

  /// Request idle timeout: 150s (If an Edge Function doesn't send a response before the timeout, 504 Gateway Timeout will be returned)
  ///
  /// See more: https://supabase.com/docs/guides/functions/limits
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: String?

  /// The JSON decoder to use for decoding response bodies.
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

  /// Initializes a new instance of `FunctionsClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions.
  ///   - headers: Headers to be included in the requests. (Default: empty dictionary)
  ///   - region: The Region to invoke the functions in.
  ///   - logger: SupabaseLogger instance to use.
  ///   - fetch: The fetch handler used to make requests. (Default: URLSession.shared.data(for:))
  ///   - decoder: The JSON decoder to use for decoding response bodies. (Default: `JSONDecoder()`)
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

  /// Initializes a new instance of `FunctionsClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions.
  ///   - headers: Headers to be included in the requests. (Default: empty dictionary)
  ///   - region: The Region to invoke the functions in.
  ///   - logger: SupabaseLogger instance to use.
  ///   - fetch: The fetch handler used to make requests. (Default: URLSession.shared.data(for:))
  ///   - decoder: The JSON decoder to use for decoding response bodies. (Default: `JSONDecoder()`)
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

  /// Updates the authorization header.
  ///
  /// - Parameter token: The new JWT token sent in the authorization header.
  public func setAuth(token: String?) {
    mutableState.withValue {
      if let token {
        $0.headers[.authorization] = "Bearer \(token)"
      } else {
        $0.headers[.authorization] = nil
      }
    }
  }

  // MARK: - New builder-style API

  /// Invokes a function and returns the raw response data and HTTP response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - applyOptions: A closure to configure the invocation options.
  /// - Returns: The raw response data and HTTP response.
  @discardableResult
  public func invoke(
    _ functionName: String,
    options applyOptions: (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (Data, HTTPURLResponse) {
    var options = FunctionInvokeOptions()
    applyOptions(&options)
    let response = try await rawInvoke(functionName: functionName, invokeOptions: options)
    return (response.data, response.underlyingResponse)
  }

  /// Invokes a function and decodes the response as a specific type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - type: The type to decode the response as.
  ///   - decoder: The JSON decoder to use. If `nil`, uses the client's decoder.
  ///   - applyOptions: A closure to configure the invocation options.
  /// - Returns: The decoded value and HTTP response.
  public func invokeDecodable<T: Decodable>(
    _ functionName: String,
    as _: T.Type = T.self,
    decoder: JSONDecoder? = nil,
    options applyOptions: (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (T, HTTPURLResponse) {
    let (data, response) = try await invoke(functionName, options: applyOptions)
    let value = try (decoder ?? self.decoder).decode(T.self, from: data)
    return (value, response)
  }

  /// Invokes a function with a streamed response.
  ///
  /// The invoked function must return a `text/event-stream` content type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - applyOptions: A closure to configure the invocation options.
  /// - Returns: A stream of `Data` chunks from the response.
  public func invokeStream(
    _ functionName: String,
    options applyOptions: (inout FunctionInvokeOptions) -> Void = { _ in }
  ) -> AsyncThrowingStream<Data, any Error> {
    var opts = FunctionInvokeOptions()
    applyOptions(&opts)
    return makeStreamedResponse(functionName: functionName, options: opts)
  }

  // MARK: - Deprecated API

  /// Invokes a function and decodes the response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function.
  ///   - decode: A closure to decode the response data and HTTPURLResponse into a `Response` object.
  /// - Returns: The decoded `Response` object.
  @available(*, deprecated, message: "Use invoke(_:options:) with a closure instead.")
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws -> Response {
    let response = try await rawInvoke(functionName: functionName, invokeOptions: options)
    return try decode(response.data, response.underlyingResponse)
  }

  /// Invokes a function and decodes the response as a specific type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function.
  ///   - decoder: The JSON decoder to use for decoding the response. If `nil`, uses the client's decoder.
  /// - Returns: The decoded object of type `T`.
  @available(*, deprecated, message: "Use invokeDecodable(_:as:decoder:options:) instead.")
  public func invoke<T: Decodable>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decoder: JSONDecoder? = nil
  ) async throws -> T {
    let decoder = decoder ?? self.decoder
    let response = try await rawInvoke(functionName: functionName, invokeOptions: options)
    return try decoder.decode(T.self, from: response.data)
  }

  /// Invokes a function without expecting a response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function.
  @_disfavoredOverload
  @available(*, deprecated, message: "Use invoke(_:options:) with a closure instead.")
  public func invoke(
    _ functionName: String,
    options: FunctionInvokeOptions = .init()
  ) async throws {
    _ = try await rawInvoke(functionName: functionName, invokeOptions: options)
  }

  /// Invokes a function with streamed response.
  ///
  /// Function MUST return a `text/event-stream` content type for this method to work.
  ///
  /// - Warning: Deprecated. Use ``invokeStream(_:options:)`` instead.
  @available(*, deprecated, renamed: "invokeStream(_:options:)")
  public func _invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) -> AsyncThrowingStream<Data, any Error> {
    makeStreamedResponse(functionName: functionName, options: invokeOptions)
  }

  // MARK: - Private

  private func rawInvoke(
    functionName: String,
    invokeOptions: FunctionInvokeOptions
  ) async throws -> Helpers.HTTPResponse {
    let request = buildRequest(functionName: functionName, options: invokeOptions)
    let response = try await http.send(request)

    guard 200..<300 ~= response.statusCode else {
      throw FunctionsError.httpError(code: response.statusCode, data: response.data)
    }

    let isRelayError = response.headers[.xRelayError] == "true"
    if isRelayError {
      throw FunctionsError.relayError
    }

    return response
  }

  private func makeStreamedResponse(
    functionName: String, options: FunctionInvokeOptions
  ) -> AsyncThrowingStream<Data, any Error> {
    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    let delegate = StreamResponseDelegate(continuation: continuation)

    let session = URLSession(
      configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)

    let urlRequest = buildRequest(functionName: functionName, options: options).urlRequest

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
    var query = options.query.map { URLQueryItem(name: $0.key, value: $0.value) }
    var request = HTTPRequest(
      url: url.appendingPathComponent(functionName),
      method: FunctionInvokeOptions.httpMethod(options.method) ?? .post,
      query: query,
      headers: mutableState.headers.merging(with: HTTPFields(options.headers)),
      body: options.body,
      timeoutInterval: FunctionsClient.requestIdleTimeout
    )

    let regionString = options.region?.rawValue ?? region
    if let regionString {
      request.headers[.xRegion] = regionString
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: regionString))
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

    guard 200..<300 ~= httpResponse.statusCode else {
      let error = FunctionsError.httpError(
        code: httpResponse.statusCode,
        data: Data()
      )
      continuation.finish(throwing: error)
      return
    }

    let isRelayError = httpResponse.value(forHTTPHeaderField: "x-relay-error") == "true"
    if isRelayError {
      continuation.finish(throwing: FunctionsError.relayError)
    }
  }
}
