import ConcurrencyExtras
import Foundation
import HTTPClient
import HTTPTypes

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

extension URL {
  fileprivate var _baseURL: URL {
    guard let scheme, let host, let port else { return self }
    return URL(string: "\(scheme)://\(host):\(port)")!
  }
}

/// An actor representing a client for invoking functions.
public final class FunctionsClient {
  /// Request idle timeout: 150s (If an Edge Function doesn't send a response before the timeout, 504 Gateway Timeout will be returned)
  ///
  /// See more: https://supabase.com/docs/guides/functions/limits
  public static let requestIdleTimeout: TimeInterval = 150

  /// The base URL for the functions.
  let url: URL

  /// The Region to invoke the functions in.
  let region: FunctionRegion?

  private let client: Client
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
    let client = Client(serverURL: url._baseURL, transport: transport)
    self.client = client
    self.http = client

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

  /// Convenience method for invoking edge functions and decoding response as a Decodable type.
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
    try await invoke(functionName, options: options).decode(as: T.self, using: decoder)
  }

  /// Invokes an edge function.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: Options for invoking the function. (Default: empty `FunctionInvokeOptions`)
  /// - Returns: The `HTTPBody` response.
  @discardableResult
  public func invoke(
    _ functionName: String,
    options invokeOptions: FunctionInvokeOptions = .init()
  ) async throws -> HTTPBody {
    let (request, requestBody) = buildRequest(functionName: functionName, options: invokeOptions)
    let (response, responseBody) = try await client.send(request, body: requestBody)

    guard response.status == .ok else {
      throw FunctionsError.httpError(
        code: response.status.code,
        data: responseBody != nil ? try await Data(collecting: responseBody!, upTo: .max) : Data()
      )
    }

    let isRelayError = response.headerFields[.xRelayError] == "true"
    if isRelayError {
      throw FunctionsError.relayError
    }

    return responseBody ?? HTTPBody()
  }

  private func buildRequest(
    functionName: String,
    options: FunctionInvokeOptions
  ) -> (HTTPTypes.HTTPRequest, HTTPBody?) {
    var query = options.query
    var headers = headers.merging(with: options.headers)

    if let region = options.region ?? region {
      headers[.xRegion] = region.rawValue
      query.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region.rawValue))
    }

    let request = HTTPTypes.HTTPRequest(
      method: options.method ?? .post,
      url: url.appendingPathComponent(functionName).appendingQueryItems(query),
      headerFields: headers
    )

    return (request, options.body.map(HTTPBody.init))
  }
}
