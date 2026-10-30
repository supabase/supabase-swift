public import Foundation
public import HTTPTypes
import Helpers

/// An error type representing various errors that can occur while invoking functions.
public enum FunctionsError: Error, LocalizedError {
  /// Error indicating a relay error while invoking the Edge Function.
  case relayError
  /// Error indicating a non-2xx status code returned by the Edge Function.
  case httpError(code: Int, data: Data)

  /// Identifies which party failed. Matches `FunctionsError.Kind` in v3.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// The Supabase gateway failed to relay the call to the function.
    public static let relay: Kind = "relay"
    /// The function answered with a non-2xx status.
    public static let server: Kind = "server"
  }

  /// The failure category. Prefer matching on `kind` over the enum cases.
  public var kind: Kind {
    switch self {
    case .relayError: .relay
    case .httpError: .server
    }
  }

  /// A human-readable description of the failure.
  public var message: String { errorDescription ?? "" }

  /// The HTTP status code of a ``Kind-swift.struct/server`` failure, `nil` otherwise.
  public var statusCode: Int? {
    if case .httpError(let code, _) = self { code } else { nil }
  }

  /// A localized description of the error.
  public var errorDescription: String? {
    switch self {
    case .relayError:
      "Relay Error invoking the Edge Function"
    case .httpError(let code, _):
      "Edge Function returned a non-2xx status code: \(code)"
    }
  }
}

/// Options for invoking a function.
///
/// Pass the request body separately with ``FunctionBody`` through
/// ``FunctionsClient/invoke(_:body:options:)``.
///
/// ```swift
/// let options = FunctionInvokeOptions(
///   method: .put,
///   headers: [.init("X-Custom")!: "value"],
///   region: .usEast1,
///   timeout: .seconds(30)
/// )
/// ```
public struct FunctionInvokeOptions: Sendable, Hashable {
  /// The HTTP method to use. Defaults to `POST`.
  public var method: HTTPTypes.HTTPRequest.Method

  /// Headers to include in the invocation. They override the client's headers.
  public var headers: HTTPFields

  /// Query items appended to the function URL.
  public var query: [URLQueryItem]

  /// The region to invoke the function in. Overrides the client's region.
  public var region: FunctionRegion?

  /// A per-invocation override for the request timeout. Defaults to
  /// ``FunctionsClient/requestIdleTimeout`` when `nil`.
  public var timeout: Duration?

  /// Body carried by the deprecated `body:` initializers.
  var body: Data?

  /// Creates options for a function invocation.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to `POST`.
  ///   - headers: Additional headers to include in the request.
  ///   - query: Query items appended to the function URL.
  ///   - region: The region to invoke the function in.
  ///   - timeout: A per-invocation override for the request timeout.
  public init(
    method: HTTPTypes.HTTPRequest.Method = .post,
    headers: HTTPFields = [:],
    query: [URLQueryItem] = [],
    region: FunctionRegion? = nil,
    timeout: Duration? = nil
  ) {
    self.method = method
    self.headers = headers
    self.query = query
    self.region = region
    self.timeout = timeout
  }

  /// Creates options for a function invocation with an encodable body.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - query: Query items appended to the function URL.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region string to invoke the function in.
  ///   - body: The body to encode and send. Strings are sent as `text/plain`, `Data` as
  ///     `application/octet-stream`, and all other `Encodable` values as JSON.
  ///   - encoder: The JSON encoder used when `body` is encoded as JSON.
  ///   - timeoutInterval: A per-invocation override for the request timeout.
  @available(
    *, deprecated,
    message:
      "Pass the body as a FunctionBody to invoke(_:body:options:) and use init(method:headers:query:region:timeout:)."
  )
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: String? = nil,
    body: some Encodable,
    encoder: JSONEncoder = JSONEncoder(),
    timeoutInterval: TimeInterval? = nil
  ) {
    var defaultHeaders = HTTPFields()
    let encodedBody: Data?

    switch body {
    case let string as String:
      defaultHeaders[.contentType] = "text/plain"
      encodedBody = string.data(using: .utf8)
    case let data as Data:
      defaultHeaders[.contentType] = "application/octet-stream"
      encodedBody = data
    default:
      defaultHeaders[.contentType] = "application/json"
      encodedBody = try? encoder.encode(body)
    }

    self.init(
      method: method?.httpTypesMethod ?? .post,
      headers: defaultHeaders.merging(with: HTTPFields(headers)),
      query: query,
      region: region.map(FunctionRegion.init(rawValue:)),
      timeout: timeoutInterval.map { .seconds($0) }
    )
    self.body = encodedBody
  }

  /// Creates options for a function invocation with no body.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - query: Query items appended to the function URL.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region string to invoke the function in.
  ///   - timeoutInterval: A per-invocation override for the request timeout.
  @available(
    *, deprecated, message: "Use init(method:headers:query:region:timeout:) instead."
  )
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: String? = nil,
    timeoutInterval: TimeInterval? = nil
  ) {
    self.init(
      method: method?.httpTypesMethod ?? .post,
      headers: HTTPFields(headers),
      query: query,
      region: region.map(FunctionRegion.init(rawValue:)),
      timeout: timeoutInterval.map { .seconds($0) }
    )
  }

  /// The HTTP method to use when invoking a function.
  @available(*, deprecated, message: "Use HTTPTypes.HTTPRequest.Method instead.")
  public enum Method: String, Sendable {
    /// Performs an HTTP GET request.
    case get = "GET"
    /// Performs an HTTP POST request.
    case post = "POST"
    /// Performs an HTTP PUT request.
    case put = "PUT"
    /// Performs an HTTP PATCH request.
    case patch = "PATCH"
    /// Performs an HTTP DELETE request.
    case delete = "DELETE"

    var httpTypesMethod: HTTPTypes.HTTPRequest.Method {
      switch self {
      case .get: .get
      case .post: .post
      case .put: .put
      case .patch: .patch
      case .delete: .delete
      }
    }
  }
}

extension Duration {
  var timeInterval: TimeInterval {
    TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
  }
}

/// A Supabase Edge Network region identifier.
///
/// Use the predefined static constants for known regions, or supply a custom value
/// for regions not listed here:
///
/// ```swift
/// // predefined
/// let options = FunctionInvokeOptions(region: .usEast1)
/// // custom region
/// let options2 = FunctionInvokeOptions(region: FunctionRegion(rawValue: "custom-region"))
/// let options3 = FunctionInvokeOptions(region: "custom-region")
/// ```
public struct FunctionRegion: RawRepresentable, Hashable, Sendable {
  /// The raw region string sent in the request.
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let apNortheast1 = FunctionRegion(rawValue: "ap-northeast-1")
  public static let apNortheast2 = FunctionRegion(rawValue: "ap-northeast-2")
  public static let apSouth1 = FunctionRegion(rawValue: "ap-south-1")
  public static let apSoutheast1 = FunctionRegion(rawValue: "ap-southeast-1")
  public static let apSoutheast2 = FunctionRegion(rawValue: "ap-southeast-2")
  public static let caCentral1 = FunctionRegion(rawValue: "ca-central-1")
  public static let euCentral1 = FunctionRegion(rawValue: "eu-central-1")
  public static let euCentral2 = FunctionRegion(rawValue: "eu-central-2")
  public static let euWest1 = FunctionRegion(rawValue: "eu-west-1")
  public static let euWest2 = FunctionRegion(rawValue: "eu-west-2")
  public static let euWest3 = FunctionRegion(rawValue: "eu-west-3")
  public static let saEast1 = FunctionRegion(rawValue: "sa-east-1")
  public static let usEast1 = FunctionRegion(rawValue: "us-east-1")
  public static let usWest1 = FunctionRegion(rawValue: "us-west-1")
  public static let usWest2 = FunctionRegion(rawValue: "us-west-2")
}

extension FunctionRegion: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}

extension FunctionInvokeOptions {
  /// Creates options for a function invocation with an encodable body and a typed region.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region to invoke the function in.
  ///   - body: The body to encode and send.
  ///   - encoder: The JSON encoder used when `body` is encoded as JSON.
  ///   - timeoutInterval: A per-invocation override for the request timeout.
  @available(
    *, deprecated,
    message:
      "Pass the body as a FunctionBody to invoke(_:body:options:) and use init(method:headers:query:region:timeout:)."
  )
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    body: some Encodable,
    encoder: JSONEncoder = JSONEncoder(),
    timeoutInterval: TimeInterval? = nil
  ) {
    self.init(
      method: method,
      headers: headers,
      region: region?.rawValue,
      body: body,
      encoder: encoder,
      timeoutInterval: timeoutInterval
    )
  }

  /// Creates options for a function invocation with no body and a typed region.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region to invoke the function in.
  ///   - timeoutInterval: A per-invocation override for the request timeout.
  @available(
    *, deprecated, message: "Use init(method:headers:query:region:timeout:) instead."
  )
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    timeoutInterval: TimeInterval? = nil
  ) {
    self.init(
      method: method, headers: headers, region: region?.rawValue, timeoutInterval: timeoutInterval)
  }
}
