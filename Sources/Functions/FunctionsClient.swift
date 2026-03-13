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
public actor FunctionsClient {
  /// Request idle timeout: 150s (If an Edge Function doesn't send a response before the timeout, 504 Gateway Timeout will be returned)
  ///
  /// See more: https://supabase.com/docs/guides/functions/limits
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: FunctionRegion?

  private let http: _HTTPClient

  var headers: [String: String] = [:]

  /// Initializes a new instance of `FunctionsClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions.
  ///   - headers: Headers to be included in all requests.
  ///   - region: The Region to invoke the functions in.
  ///   - session: The `URLSession` used to perform requests. Defaults to a new session.
  public init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    session: URLSession = URLSession(configuration: .default)
  ) {
    self.url = url
    self.region = region
    session.configuration.timeoutIntervalForRequest = Self.requestIdleTimeout
    self.http = _HTTPClient(host: url, session: session)
    self.headers = headers
    if self.headers["X-Client-Info"] == nil {
      self.headers["X-Client-Info"] = "functions-swift/\(version)"
    }
  }

  package init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    session: URLSession = URLSession(configuration: .default),
    tokenProvider: @escaping TokenProvider
  ) {
    self.url = url
    self.region = region
    session.configuration.timeoutIntervalForRequest = Self.requestIdleTimeout
    self.http = _HTTPClient(host: url, session: session, tokenProvider: tokenProvider)
    self.headers = headers
    if self.headers["X-Client-Info"] == nil {
      self.headers["X-Client-Info"] = "functions-swift/\(version)"
    }
  }

  /// Updates the authorization header.
  ///
  /// - Parameter token: The new JWT token sent in the authorization header.
  public func setAuth(token: String?) {
    if let token {
      headers["Authorization"] = "Bearer \(token)"
    } else {
      headers.removeValue(forKey: "Authorization")
    }
  }

  /// Invokes a function and decodes the response as a specific type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function.
  ///   - decoder: The JSON decoder to use. Defaults to `JSONDecoder()`.
  /// - Returns: A tuple containing the decoded object of type `T` and the `HTTPURLResponse`.
  public func invokeDecodable<T: Decodable>(
    _ functionName: String,
    decoder: JSONDecoder = JSONDecoder(),
    options applyOptions: (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (T, HTTPURLResponse) {
    let (data, response) = try await invoke(functionName, options: applyOptions)
    return (try decoder.decode(T.self, from: data), response)
  }

  /// Invokes a function and returns the raw response data and `HTTPURLResponse`.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function.
  /// - Returns: A tuple containing the raw response data and `HTTPURLResponse`.
  @discardableResult
  public func invoke(
    _ functionName: String,
    options applyOptions: (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (Data, HTTPURLResponse) {
    var options = FunctionInvokeOptions()
    applyOptions(&options)
    let (functionURL, method, query, allHeaders, body) = requestComponents(
      functionName: functionName, options: options)

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
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function.
  /// - Returns: Byte-by-byte stream and the initial `HTTPURLResponse`.
  @available(macOS 12.0, *)
  public func invokeStream(
    _ functionName: String,
    options applyOptions: (inout FunctionInvokeOptions) -> Void = { _ in }
  ) async throws -> (AsyncThrowingStream<UInt8, any Error>, HTTPURLResponse) {
    var options = FunctionInvokeOptions()
    applyOptions(&options)
    let (functionURL, method, query, allHeaders, body) = requestComponents(
      functionName: functionName, options: options)

    do {
      let (bytes, response) = try await http.fetchStream(
        method, url: functionURL, query: query.isEmpty ? nil : query, body: body,
        headers: allHeaders.isEmpty ? nil : allHeaders)

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
    functionName: String, options: FunctionInvokeOptions
  ) -> (
    url: URL,
    method: HTTPMethod,
    query: [String: String],
    headers: [String: String],
    body: RequestBody?
  ) {
    let method = options.method.flatMap { HTTPMethod(rawValue: $0.rawValue) } ?? .post
    var query = options.query
    var allHeaders = headers.merging(options.headers) { _, new in new }

    if let region = (options.region ?? region)?.rawValue {
      allHeaders["x-region"] = region
      query["forceFunctionRegion"] = region
    }

    let body: RequestBody? = options.body.map { .data($0) }
    return (url.appendingPathComponent(functionName), method, query, allHeaders, body)
  }
}
