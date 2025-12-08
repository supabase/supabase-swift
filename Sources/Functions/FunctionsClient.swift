import ConcurrencyExtras
import Foundation
import Shared

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
  let region: FunctionRegion?

  struct MutableState {
    /// Headers to be included in the requests.
    var headers = [String: String]()
  }

  private let http: Shared.HTTPClient
  private let mutableState = LockIsolated(MutableState())

  var headers: [String: String] {
    mutableState.headers
  }

  package init(
    url: URL,
    headers: [String: String],
    region: FunctionRegion?,
    http: Shared.HTTPClient
  ) {
    self.url = url
    self.region = region
    self.http = http

    mutableState.withValue {
      $0.headers = headers
      if $0.headers["X-Client-Info"] == nil {
        $0.headers["X-Client-Info"] = "functions-swift/\(version)"
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
    logger: (any SupabaseLogger)? = nil
  ) {
    self.init(url: url, headers: headers, region: region, http: HTTPClient(host: url))
  }

  /// Updates the authorization header.
  ///
  /// - Parameter token: The new JWT token sent in the authorization header.
  public func setAuth(token: String?) {
    mutableState.withValue {
      if let token {
        $0.headers["Authorization"] = "Bearer \(token)"
      } else {
        $0.headers["Authorization"] = nil
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
    let (data, httpResponse) = try await rawInvoke(
      functionName: functionName, invokeOptions: options
    )
    return try decode(data, httpResponse)
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
    let request = try await buildRequest(functionName: functionName, options: invokeOptions)
    let (data, response) = try await http.fetchData(request)
    return (data, response)
  }

  /// Invokes a function with streamed response.
  ///
  /// Function MUST return a `text/event-stream` content type for this method to work.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - invokeOptions: Options for invoking the function.
  /// - Returns: A stream of Data.
  @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
  public func invokeWithStreamedResponse(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) async throws -> AsyncThrowingStream<Data, any Error> {
    let request = try await buildRequest(functionName: functionName, options: invokeOptions)
    return http.fetchStream(request)
  }

  private func buildRequest(
    functionName: String,
    options: FunctionInvokeOptions
  ) async throws -> URLRequest {
    var request = try await http.createRequest(
      (options.method ?? .post).sharedMethod,
      functionName,
      query: Dictionary(
        uniqueKeysWithValues: options.query.map {
          ($0.name, $0.value.map { Value.string($0) } ?? .null)
        }),
      body: options.body,
      headers: self.headers.merging(options.headers, uniquingKeysWith: { $1 })
    )

    request.timeoutInterval = FunctionsClient.requestIdleTimeout

    if let region = (options.region ?? self.region)?.rawValue {
      request.addValue(region, forHTTPHeaderField: "x-region")
      request.url = request.url?.appendingQueryItems([
        URLQueryItem(name: "forceFunctionRegion", value: region)
      ])
    }

    return request
  }
}
