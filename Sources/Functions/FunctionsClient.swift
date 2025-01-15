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
  public typealias FetchHandler = @Sendable (_ request: URLRequest) async throws -> (
    Data, URLResponse
  )

  public typealias _RequestAdapter = @Sendable (URLRequest) async throws -> URLRequest

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: String?

  struct MutableState {
    /// Headers to be included in the requests.
    var headers = HTTPFields()
  }

  private let http: any HTTPClientType
  private let mutableState = LockIsolated(MutableState())
  private let _requestAdapter: _RequestAdapter?

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
  @_disfavoredOverload
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    _requestAdapter: _RequestAdapter? = nil
  ) {
    var interceptors: [any HTTPClientInterceptor] = []

    if let logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    let http = HTTPClient(fetch: fetch, interceptors: interceptors)

    self.init(
      url: url, headers: headers, region: region, http: http, _requestAdapter: _requestAdapter)
  }

  init(
    url: URL,
    headers: [String: String],
    region: String?,
    http: any HTTPClientType,
    _requestAdapter: _RequestAdapter?
  ) {
    self.url = url
    self.region = region
    self.http = http
    self._requestAdapter = _requestAdapter

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
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    _requestAdapter: _RequestAdapter? = nil
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region?.rawValue,
      logger: logger,
      fetch: fetch,
      _requestAdapter: _requestAdapter
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

  /// Invokes a function and decodes the response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
  ///   - decode: A closure to decode the response data and HTTPURLResponse into a `Response`
  /// object.
  /// - Returns: The decoded `Response` object.
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

  /// Invokes a function and decodes the response as a specific type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
  ///   - decoder: The JSON decoder to use for decoding the response. (Default: `JSONDecoder()`)
  /// - Returns: The decoded object of type `T`.
  public func invoke<T: Decodable>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decoder: JSONDecoder = JSONDecoder()
  ) async throws -> T {
    try await invoke(functionName, options: options) { data, _ in
      try decoder.decode(T.self, from: data)
    }
  }

  /// Invokes a function without expecting a response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
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

    guard 200..<300 ~= response.statusCode else {
      throw FunctionsError.httpError(code: response.statusCode, data: response.data)
    }

    let isRelayError = response.headers[.xRelayError] == "true"
    if isRelayError {
      throw FunctionsError.relayError
    }

    return response
  }

  /// Invokes a function with streamed response.
  ///
  /// Function MUST return a `text/event-stream` content type for this method to work.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - invokeOptions: Options for invoking the function.
  /// - Returns: A stream of Data.
  ///
  /// - Warning: Experimental method.
  /// - Note: This method doesn't use the same underlying `URLSession` as the remaining methods in the library.
  public func _invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) -> AsyncThrowingStream<Data, any Error> {
    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    let delegate = StreamResponseDelegate(continuation: continuation)

    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

    let urlRequest = buildRequest(functionName: functionName, options: invokeOptions).urlRequest

    Task {
      let adaptedRequest: URLRequest

      if let _requestAdapter {
        do {
          adaptedRequest = try await _requestAdapter(urlRequest)
        } catch {
          continuation.finish(throwing: error)
          return
        }
      } else {
        adaptedRequest = urlRequest
      }

      let task = session.dataTask(with: adaptedRequest)
      task.resume()

      continuation.onTermination = { _ in
        task.cancel()

        // Hold a strong reference to delegate until continuation terminates.
        _ = delegate
      }
    }

    return stream
  }

  private func buildRequest(functionName: String, options: FunctionInvokeOptions)
    -> Helpers.HTTPRequest
  {
    var request = HTTPRequest(
      url: url.appendingPathComponent(functionName),
      method: options.httpMethod ?? .post,
      query: options.query,
      headers: mutableState.headers.merging(with: options.headers),
      body: options.body
    )

    if let region = options.region ?? region {
      request.headers[.xRegion] = region
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
    guard let httpResponse = response as? HTTPURLResponse else {
      continuation.finish(throwing: URLError(.badServerResponse))
      return
    }

    guard 200..<300 ~= httpResponse.statusCode else {
      let error = FunctionsError.httpError(code: httpResponse.statusCode, data: Data())
      continuation.finish(throwing: error)
      return
    }

    let isRelayError = httpResponse.value(forHTTPHeaderField: "x-relay-error") == "true"
    if isRelayError {
      continuation.finish(throwing: FunctionsError.relayError)
    }
    completionHandler(.allow)
  }
}
