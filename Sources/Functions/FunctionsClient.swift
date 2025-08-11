import ConcurrencyExtras
import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Logging
import OpenAPIURLSession

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

  /// Request idle timeout: 150s (If an Edge Function doesn't send a response before the timeout, 504 Gateway Timeout will be returned)
  ///
  /// See more: https://supabase.com/docs/guides/functions/limits
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: String?

  struct MutableState {
    /// Headers to be included in the requests.
    var headers = HTTPFields()
  }

  private let client: Client
  private let mutableState = LockIsolated(MutableState())

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
  @available(
    *,
    deprecated,
    message: "Fetch handler is deprecated, use init with `transport` instead."
  )
  @_disfavoredOverload
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region,
      logger: logger,
      client: Client(serverURL: url, transport: FetchTransportAdapter(fetch: fetch))
    )
  }

  @_disfavoredOverload
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    logger: (any SupabaseLogger)? = nil,
    transport: (any ClientTransport)? = nil
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region,
      logger: logger,
      client: Client(
        serverURL: url,
        transport: transport ?? URLSessionTransport(),
        middlewares: [LoggingMiddleware(logger: .functions)]
      )
    )
  }

  init(
    url: URL,
    headers: [String: String] = [:],
    region: String? = nil,
    logger: (any SupabaseLogger)? = nil,
    client: Client
  ) {
    self.url = url
    self.region = region
    self.client = client

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

  @available(
    *,
    deprecated,
    message: "Fetch handler is deprecated, use init with `transport` instead."
  )
  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region?.rawValue,
      logger: logger,
      fetch: fetch
    )
  }

  public convenience init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    logger: (any SupabaseLogger)? = nil,
    transport: (any ClientTransport)? = nil
  ) {
    self.init(
      url: url,
      headers: headers,
      region: region?.rawValue,
      logger: logger,
      transport: transport
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

  /// Inokes a functions returns the raw response and body.
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
  /// - Returns: The raw response and body.
  @discardableResult
  public func invoke(
    _ functionName: String,
    options: FunctionInvokeOptions = .init()
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody) {
    try await self.invoke(functionName, options: options) { ($0, $1) }
  }

  /// Invokes a function and decodes the response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
  ///   - decode: A closure to decode the response data and `HTTPResponse` into a `Response`
  /// object.
  /// - Returns: The decoded `Response` object.
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (HTTPTypes.HTTPResponse, HTTPBody) async throws -> Response
  ) async throws -> Response {
    let (_, response, body) = try await _invoke(
      functionName: functionName,
      invokeOptions: options
    )

    return try await decode(response, body)
  }

  /// Invokes a function and decodes the response.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
  ///   - decode: A closure to decode the response data and HTTPURLResponse into a `Response`
  /// object.
  /// - Returns: The decoded `Response` object.
  @available(*, deprecated, message: "Use `invoke` with HTTPBody instead.")
  public func invoke<Response>(
    _ functionName: String,
    options: FunctionInvokeOptions = .init(),
    decode: (Data, HTTPURLResponse) throws -> Response
  ) async throws -> Response {
    let (request, response, body) = try await _invoke(
      functionName: functionName,
      invokeOptions: options
    )

    let data = try await Data(collecting: body, upTo: .max)

    return try decode(data, HTTPURLResponse(httpResponse: response, url: request.url ?? self.url)!)
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
    try await invoke(functionName, options: options) { _, body in
      let data = try await Data(collecting: body, upTo: .max)
      return try decoder.decode(T.self, from: data)
    }
  }

  private func _invoke(
    functionName: String,
    invokeOptions: FunctionInvokeOptions
  ) async throws -> (HTTPTypes.HTTPRequest, HTTPTypes.HTTPResponse, HTTPBody) {
    let (request, requestBody) = buildRequest(functionName: functionName, options: invokeOptions)
    let (response, responseBody) = try await client.send(request, body: requestBody)

    guard response.status.kind == .successful else {
      let data = try await Data(collecting: responseBody, upTo: .max)
      throw FunctionsError.httpError(code: response.status.code, data: data)
    }

    let isRelayError = response.headerFields[.xRelayError] == "true"
    if isRelayError {
      throw FunctionsError.relayError
    }

    return (request, response, responseBody)
  }

  private func buildRequest(
    functionName: String,
    options: FunctionInvokeOptions
  ) -> (HTTPTypes.HTTPRequest, HTTPBody?) {
    var region = options.region
    var queryItems = options.query
    var headers = options.headers

    // TODO: Check how to assign FunctionsClient.requestIdleTimeout

    if region == nil {
      region = self.region
    }

    if let region, region != "any" {
      headers[.xRegion] = region
      queryItems.append(URLQueryItem(name: "forceFunctionRegion", value: region))
    }

    let request = HTTPTypes.HTTPRequest(
      method: FunctionInvokeOptions.httpMethod(options.method) ?? .post,
      url: url.appendingPathComponent(functionName).appendingQueryItems(queryItems),
      headerFields: mutableState.headers.merging(with: headers)
    )

    let body = options.body.map(HTTPBody.init)

    return (request, body)
  }
}
