import ConcurrencyExtras
import Foundation
import HTTPClient
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

/// An actor representing a client for invoking functions.
public actor FunctionsClient {
  /// Request idle timeout: 150s (If an Edge Function doesn't send a response before the timeout, 504 Gateway Timeout will be returned)
  ///
  /// See more: https://supabase.com/docs/guides/functions/limits
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: FunctionRegion?

  private let http: any HTTPClientType

  private(set) var headers = HTTPFields()

  /// Initializes a new instance of `FunctionsClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions.
  ///   - headers: Headers to be included in the requests. (Default: empty dictionary)
  ///   - region: The Region to invoke the functions in.
  ///   - logger: SupabaseLogger instance to use.
  ///   - fetch: The fetch handler used to make requests. (Default: URLSession.shared.data(for:))
  public init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: (any SupabaseLogger)? = nil,
    transport: any ClientTransport = URLSessionTransport()
  ) {
    var interceptors: [any HTTPClientInterceptor] = []
    if let logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    self.url = url
    self.region = region

    // TODO: apply interceptors to Client.
    self.http = Client(serverURL: url, transport: transport)

    self.headers = HTTPFields(headers)
    if self.headers[.xClientInfo] == nil {
      self.headers[.xClientInfo] = "functions-swift/\(version)"
    }
  }

  /// Updates the authorization header.
  ///
  /// - Parameter token: The new JWT token sent in the authorization header.
  public func setAuth(token: String?) {
    if let token {
      headers[.authorization] = "Bearer \(token)"
    } else {
      headers[.authorization] = nil
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
      functionName: functionName,
      invokeOptions: options
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
  public func invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) -> (HTTPTypes.HTTPResponse, HTTPBody) {
    fatalError("Implement.")
  }

  private func buildRequest(functionName: String, options: FunctionInvokeOptions)
    -> Helpers.HTTPRequest
  {
    var query = options.query
    var request = HTTPRequest(
      url: url.appendingPathComponent(functionName),
      method: options.method ?? .post,
      query: query,
      headers: headers.merging(with: options.headers),
      body: options.body,
      timeoutInterval: FunctionsClient.requestIdleTimeout
    )

    if let region = options.region ?? region {
      request.headers[.xRegion] = region.rawValue
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region.rawValue))
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
    _: URLSession,
    dataTask _: URLSessionDataTask,
    didReceive response: URLResponse,
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
