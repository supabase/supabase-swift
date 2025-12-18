import ConcurrencyExtras
import Foundation
import HTTPClient
import HTTPTypes
import Helpers
import IssueReporting

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

let version = Helpers.version

/// A client for invoking Supabase Edge Functions.
public final class FunctionsClient: Sendable {
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
  ///   - headers: Default headers to include with every request.
  ///   - region: The default Region to invoke the functions in.
  ///   - session: The URLSession to use for requests.
  ///   - logger: A logger instance to use for request/response logging.
  public init(
    url: URL,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    session: URLSession = .shared,
    logger: (any SupabaseLogger)? = nil
  ) {
    self.url = url
    self.region = region

    let configuration = session.configuration
    configuration.timeoutIntervalForRequest = Self.requestIdleTimeout
    let configuredSession = URLSession(configuration: configuration)
    let transport = URLSessionTransport(configuration: .init(session: configuredSession))

    var middlewares: [any ClientMiddleware] = []
    if let logger {
      middlewares.append(SupabaseLoggerMiddleware(logger: logger))
    }

    client = Client(serverURL: url, transport: transport, middlewares: middlewares)

    mutableState.withValue {
      $0.headers = HTTPFields(headers)
      if $0.headers[.xClientInfo] == nil {
        $0.headers[.xClientInfo] = "functions-swift/\(version)"
      }
    }
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

  /// Options for invoking a function.
  public struct InvokeOptions {
    /// The method to use in the function invocation.
    public var method: HTTPTypes.HTTPRequest.Method = .post
    /// The headers to include in the function invocation.
    public var headers: HTTPFields = [:]
    /// The query to include in the function invocation.
    public var query: [URLQueryItem] = []
    /// The region to invoke the function in.
    public var region: FunctionRegion? = nil

    var _body: HTTPBody? = nil
    var _multipartFormData: MultipartFormData? = nil

    /// Appends a `HTTPBody` body to the request.
    ///
    /// - Parameter raw: The `HTTPBody` to append to the request.
    public mutating func body(_ raw: HTTPBody) {
      assert(_multipartFormData == nil, "body and multipartFormData cannot be used together")
      self._body = raw
    }

    /// Appends an `Encodable` body to the request.
    ///
    /// - Parameters:
    ///   - body: The `Encodable` to append to the request.
    ///   - encoder: The `JSONEncoder` to use to encode the body.
    public mutating func body(
      encodable body: some Encodable,
      encoder: JSONEncoder = JSONEncoder()
    ) throws {
      self.body(try HTTPBody(encoder.encode(body)))

      if headers[.contentType] == nil {
        headers[.contentType] = "application/json"
      }
    }

    /// Appends a `MultipartFormData` body to the request.
    ///
    /// - Parameter multipartFormData: The `MultipartFormData` to append to the request.
    public mutating func body(multipartFormData: MultipartFormData) {
      assert(self._body == nil, "body and multipartFormData cannot be used together")
      self._multipartFormData = multipartFormData
    }

    /// Appends a `String` body to the request.
    ///
    /// - Parameter string: The `String` to append to the request.
    public mutating func body(string: String) {
      self.body(HTTPBody(string))

      if headers[.contentType] == nil {
        headers[.contentType] = "text/plain"
      }
    }

    /// Appends a `Data` body to the request.
    ///
    /// - Parameter data: The `Data` to append to the request.
    public mutating func body(data: Data) {
      self.body(HTTPBody(data))

      if headers[.contentType] == nil {
        headers[.contentType] = "application/octet-stream"
      }
    }
  }

  /// Invokes an Edge Function.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - options: A closure that allows you to configure the invoke options.
  /// - Throws: An error if the function invocation fails.
  /// - Returns: A tuple containing the response and the response body.
  @discardableResult
  public func invoke(
    _ functionName: String,
    options optionsBuilder: (inout InvokeOptions) -> Void
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    var options = InvokeOptions()
    optionsBuilder(&options)

    let request = try buildRequest(
      functionName: functionName, method: options.method, headers: options.headers,
      query: options.query,
      region: options.region)

    let (response, responseBody) = try await {
      if let multipartFormData = options._multipartFormData {
        if options._body != nil {
          reportIssue("multipartFormData and body cannot be used together")
        }
        return try await client.send(multipartFormData: multipartFormData, with: request)
      } else {
        return try await client.send(request, body: options._body)
      }
    }()

    guard response.status.kind == .successful else {
      throw FunctionsError.httpError(
        code: response.status.code,
        data: try await Data(collecting: responseBody ?? HTTPBody(), upTo: .max)
      )
    }

    if response.headerFields[HTTPField.Name("x-relay-error")!] == "true" {
      throw FunctionsError.relayError
    }

    return (response, responseBody)
  }

  /// Invokes an Edge Function and decodes the response body into a `Decodable` type.
  ///
  /// - Parameters:
  ///   - functionName: The name of the function to invoke.
  ///   - type: The type to decode the response body into.
  ///   - decoder: The `JSONDecoder` to use to decode the response body (default: `JSONDecoder()`)
  ///   - options: A closure that allows you to configure the invoke options.
  /// - Throws: An error if the function invocation fails.
  /// - Returns: The decoded response body.
  public func invokeDecodable<T: Decodable>(
    _ functionName: String,
    as type: T.Type = T.self,
    decoder: JSONDecoder = JSONDecoder(),
    options optionsBuilder: (inout InvokeOptions) -> Void
  ) async throws -> T {
    let (_, responseBody) = try await invoke(functionName, options: optionsBuilder)
    return try decoder.decode(
      type,
      from: try await Data(collecting: responseBody ?? HTTPBody(), upTo: .max)
    )
  }

  private func buildRequest(
    functionName: String,
    method: HTTPTypes.HTTPRequest.Method,
    headers: HTTPFields,
    query: [URLQueryItem],
    region: FunctionRegion?
  ) throws -> HTTPTypes.HTTPRequest {
    var headerFields = HTTPTypes.HTTPFields()
    let mergedHeaders = mutableState.headers.merging(with: headers)
    for field in mergedHeaders {
      headerFields[HTTPField.Name(field.name.rawName)!] = field.value
    }

    var queryItems = query
    if let region = (region ?? self.region)?.rawValue {
      headerFields[HTTPField.Name("x-region")!] = region
      queryItems.appendOrUpdate(URLQueryItem(name: "forceFunctionRegion", value: region))
    }

    var path = "/\(functionName)"
    if !queryItems.isEmpty {
      var components = URLComponents()
      components.path = path
      components.queryItems = queryItems
      path = components.string ?? path
    }

    let request = HTTPTypes.HTTPRequest(
      method: method,
      scheme: nil,
      authority: nil,
      path: path,
      headerFields: headerFields
    )

    return request
  }
}

private struct SupabaseLoggerMiddleware: ClientMiddleware {
  let logger: any SupabaseLogger

  func intercept(
    _ request: HTTPTypes.HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    next:
      @Sendable (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
    logger.verbose("⬆️ \(request.method.rawValue) \(request.path ?? "<nil>")")
    let (response, responseBody) = try await next(request, body, baseURL)
    logger.verbose("⬇️ \(response.status.code) \(response.status.reasonPhrase)")
    return (response, responseBody)
  }
}
