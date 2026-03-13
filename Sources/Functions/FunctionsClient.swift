//
//  FunctionsClient.swift
//  Supabase
//
//  Created by Guilherme Souza on 22/12/22.
//

import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

/// An actor representing a client for invoking functions.
public final class FunctionsClient: Sendable {
  /// Request idle timeout: 150s (If an Edge Function doesn't send a response before the timeout, 504 Gateway Timeout will be returned)
  ///
  /// See more: https://supabase.com/docs/guides/functions/limits
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: String?

  struct MutableState {
    var headers: [String: String] = [:]
  }

  private let http: _HTTPClient
  private let mutableState = LockIsolated(MutableState())

  var headers: [String: String] {
    mutableState.headers
  }

  /// Initializes a new instance of `FunctionsClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions.
  ///   - headers: Headers to be included in all requests.
  ///   - region: The Region to invoke the functions in.
  ///   - session: The `URLSession` used to perform requests. Defaults to a new session.
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    session: URLSession = URLSession(configuration: .default)
  ) {
    self.init(url: url, headers: headers, region: region?.rawValue, session: session)
  }

  package init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    session: URLSession = URLSession(configuration: .default),
    tokenProvider: TokenProvider? = nil
  ) {
    self.url = url
    self.region = region
    self.http = _HTTPClient(host: url, session: session, tokenProvider: tokenProvider)

    mutableState.withValue {
      $0.headers = headers
      if $0.headers["X-Client-Info"] == nil {
        $0.headers["X-Client-Info"] = "functions-swift/\(version)"
      }
    }
  }

  /// Updates the authorization header.
  ///
  /// - Parameter token: The new JWT token sent in the authorization header.
  public func setAuth(token: String?) {
    mutableState.withValue {
      if let token {
        $0.headers["Authorization"] = "Bearer \(token)"
      } else {
        $0.headers.removeValue(forKey: "Authorization")
      }
    }
  }

  /// Invokes a function and decodes the response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function.
  ///   - decode: A closure to decode the response data and `HTTPURLResponse` into a `Response` object.
  /// - Returns: The decoded `Response` object.
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws -> Response {
    let (data, response) = try await rawInvoke(functionName: functionName, invokeOptions: options)
    return try decode(data, response)
  }

  /// Invokes a function and decodes the response as a specific type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function.
  ///   - decoder: The JSON decoder to use. Defaults to `JSONDecoder()`.
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
  ///   - options: Options for invoking the function.
  public func invoke(
    _ functionName: String,
    options: FunctionInvokeOptions = .init()
  ) async throws {
    try await invoke(functionName, options: options) { _, _ in () }
  }

  private func rawInvoke(
    functionName: String,
    invokeOptions: FunctionInvokeOptions
  ) async throws -> (Data, HTTPURLResponse) {
    let (functionURL, method, query, allHeaders, body) = requestComponents(
      functionName: functionName, options: invokeOptions)

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

  /// Invokes a function with streamed response.
  ///
  /// Function MUST return a `text/event-stream` content type for this method to work.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function.
  /// - Returns: A stream of `Data` chunks as they arrive.
  ///
  /// - Warning: Experimental method.
  public func _invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) async throws -> AsyncThrowingStream<Data, any Error> {
    let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    let delegate = StreamResponseDelegate(continuation: continuation)

    let (functionURL, method, query, allHeaders, body) = requestComponents(
      functionName: functionName, options: invokeOptions)
    var urlRequest = try await http.createRequest(
      method,
      url: functionURL,
      query: query.isEmpty ? nil : query,
      body: body,
      headers: allHeaders.isEmpty ? nil : allHeaders
    )
    urlRequest.timeoutInterval = FunctionsClient.requestIdleTimeout

    let session = URLSession(
      configuration: http.session.configuration,
      delegate: delegate,
      delegateQueue: nil
    )
    let task = session.dataTask(with: urlRequest)

    continuation.onTermination = { _ in
      task.cancel()
      _ = delegate
    }

    task.resume()
    return stream
  }

  private func requestComponents(
    functionName: String, options: FunctionInvokeOptions
  ) -> (url: URL, method: HTTPMethod, query: [String: String], headers: [String: String], body:
    RequestBody?)
  {
    let method = options.method.flatMap { HTTPMethod(rawValue: $0.rawValue) } ?? .post
    var query = options.query
    var allHeaders = mutableState.headers.merging(options.headers) { _, new in new }

    if let region = options.region ?? region {
      allHeaders["x-region"] = region
      query["forceFunctionRegion"] = region
    }

    let body: RequestBody? = options.body.map { .data($0) }
    return (url.appendingPathComponent(functionName), method, query, allHeaders, body)
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
      continuation.finish(
        throwing: FunctionsError.httpError(code: httpResponse.statusCode, data: Data()))
      return
    }

    if httpResponse.value(forHTTPHeaderField: "x-relay-error") == "true" {
      continuation.finish(throwing: FunctionsError.relayError)
    }
  }
}
