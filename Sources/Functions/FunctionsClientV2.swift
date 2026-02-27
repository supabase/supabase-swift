import Foundation

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct FunctionsResponseInterceptor: ResponseInterceptor {
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

@available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
public actor FunctionsClientV2 {
  public var url: URL { session.baseURL }
  public var headers: [String: String]

  private let region: FunctionRegion?
  private let session: HTTPSession

  package init(
    baseURL: URL,
    sessionConfiguration: URLSessionConfiguration = .default,
    requestAdapter: (any RequestAdapter)? = nil,
    responseInterceptor: (any ResponseInterceptor)? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
  ) {
    self.session = HTTPSession(
      baseURL: baseURL,
      configuration: sessionConfiguration,
      requestAdapter: requestAdapter,
      responseInterceptor: responseInterceptor != nil
        ? Interceptors([responseInterceptor!, FunctionsResponseInterceptor()]) : nil
    )
    self.headers = headers
    self.region = region
    if self.headers["X-Client-Info"] == nil {
      self.headers["X-Client-Info"] = "functions-swift/\(version)"
    }
  }

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

  /// Sets the Authorization header for all subsequent function invocations.
  /// - Parameter token: The bearer token to use for authentication. If `nil`, the Authorization header will be removed.
  public func setAuth(_ token: String?) {
    headers["Authorization"] = token.map { "Bearer \($0)" }
  }

  public struct FunctionsError: Error, LocalizedError {
    public let message: String

    init(_ message: String) {
      self.message = message
    }

    public var errorDescription: String? { message }

  }

  /// Invokes a function and returns the raw response data and HTTPURLResponse.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure that allows you to configure the invocation options such as HTTP method, body, headers, and query parameters.
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

  /// Invokes a function, decodes the response, and returns both the decoded response and the HTTPURLResponse.
  ///
  /// - Parameters:
  ///   - as: The type to decode the response into.
  ///   - decoder: The JSONDecoder to use for decoding the response (default: JSONDecoder()).
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure that allows you to configure the invocation options such as HTTP method, body, headers, and query parameters.
  public func invoke<Response: Decodable>(
    as: Response.Type,
    decoder: JSONDecoder = JSONDecoder(),
    _ functionName: String,
    options: (inout InvokeOptions) -> Void = { _ in }
  ) async throws -> (Response, HTTPURLResponse) {
    let (data, response) = try await invoke(
      functionName, options: options)
    let decoded = try decoder.decode(Response.self, from: data)
    return (decoded, response)
  }

  /// Invokes a function and returns an async byte stream for the response body.
  //
  /// This is useful for functions that return large responses or stream data.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure that allows you to configure the invocation options such as HTTP method, body, headers, and query parameters.
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

  public struct InvokeOptions: Sendable {
    public var method: String = "POST"
    public var body: Data? = nil
    public var headers: [String: String] = [:]
    public var query: [String: String] = [:]
  }
}
