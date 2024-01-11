import Foundation
@_spi(Internal) import _Helpers

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

let version = _Helpers.version

/// An actor representing a client for invoking functions.
public actor FunctionsClient {
  /// Fetch handler used to make requests.
  public typealias FetchHandler = @Sendable (_ request: URLRequest) async throws -> (
    Data, URLResponse
  )

  /// The base URL for the functions.
  let url: URL
  /// Headers to be included in the requests.
  var headers: [String: String]
  /// The fetch handler used to make requests.
  let fetch: FetchHandler

  /// Initializes a new instance of `FunctionsClient`.
  ///
  /// - Parameters:
  ///   - url: The base URL for the functions.
  ///   - headers: Headers to be included in the requests. (Default: empty dictionary)
  ///   - fetch: The fetch handler used to make requests. (Default: URLSession.shared.data(for:))
  public init(
    url: URL,
    headers: [String: String] = [:],
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) }
  ) {
    self.url = url
    self.headers = headers
    if headers["X-Client-Info"] == nil {
      self.headers["X-Client-Info"] = "functions-swift/\(version)"
    }
    self.fetch = fetch
  }

  /// Updates the authorization header.
  ///
  /// - Parameter token: The new JWT token sent in the authorization header.
  public func setAuth(token: String?) {
    if let token {
      headers["Authorization"] = "Bearer \(token)"
    } else {
      headers["Authorization"] = nil
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
    let (data, response) = try await rawInvoke(
      functionName: functionName, invokeOptions: options
    )
    return try decode(data, response)
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
  ) async throws -> (Data, HTTPURLResponse) {
    let url = url.appendingPathComponent(functionName)
    var urlRequest = URLRequest(url: url)
    urlRequest.allHTTPHeaderFields = invokeOptions.headers.merging(headers) { invoke, _ in invoke }
    urlRequest.httpMethod = (invokeOptions.method ?? .post).rawValue
    urlRequest.httpBody = invokeOptions.body

    let (data, response) = try await fetch(urlRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    guard 200 ..< 300 ~= httpResponse.statusCode else {
      throw FunctionsError.httpError(code: httpResponse.statusCode, data: data)
    }

    let isRelayError = httpResponse.value(forHTTPHeaderField: "x-relay-error") == "true"
    if isRelayError {
      throw FunctionsError.relayError
    }

    return (data, httpResponse)
  }
}
