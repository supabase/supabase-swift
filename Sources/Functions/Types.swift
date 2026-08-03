public import Foundation
import HTTPTypes
import Helpers

/// An error type representing various errors that can occur while invoking functions.
public enum FunctionsError: Error, LocalizedError {
  /// Error indicating a relay error while invoking the Edge Function.
  case relayError
  /// Error indicating a non-2xx status code returned by the Edge Function.
  case httpError(code: Int, data: Data)

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
public struct FunctionInvokeOptions: Sendable {
  /// Method to use in the function invocation.
  let method: Method?
  /// Headers to be included in the function invocation.
  let headers: HTTPFields
  /// Body data to be sent with the function invocation.
  let body: Data?
  /// The Region to invoke the function in.
  let region: String?
  /// The query to be included in the function invocation.
  let query: [URLQueryItem]
  /// A per-invocation override for the request timeout. Defaults to
  /// ``FunctionsClient/requestIdleTimeout`` when `nil`.
  let timeoutInterval: TimeInterval?

  /// Creates options for a function invocation with an encodable body.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - query: Query items appended to the function URL.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region string to invoke the function in.
  ///   - body: The body to encode and send. Strings are sent as `text/plain`, `Data` as
  ///     `application/octet-stream`, and all other `Encodable` values as JSON.
  ///   - encoder: The JSON encoder used when `body` is encoded as JSON.
  ///   - timeoutInterval: A per-invocation override for the request timeout. Defaults to
  ///     ``FunctionsClient/requestIdleTimeout`` when `nil`.
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

    switch body {
    case let string as String:
      defaultHeaders[.contentType] = "text/plain"
      self.body = string.data(using: .utf8)
    case let data as Data:
      defaultHeaders[.contentType] = "application/octet-stream"
      self.body = data
    default:
      defaultHeaders[.contentType] = "application/json"
      self.body = try? encoder.encode(body)
    }

    self.method = method
    self.headers = defaultHeaders.merging(with: HTTPFields(headers))
    self.region = region
    self.query = query
    self.timeoutInterval = timeoutInterval
  }

  /// Creates options for a function invocation with no body.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - query: Query items appended to the function URL.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region string to invoke the function in.
  ///   - timeoutInterval: A per-invocation override for the request timeout. Defaults to
  ///     ``FunctionsClient/requestIdleTimeout`` when `nil`.
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: String? = nil,
    timeoutInterval: TimeInterval? = nil
  ) {
    self.method = method
    self.headers = HTTPFields(headers)
    self.region = region
    self.query = query
    self.timeoutInterval = timeoutInterval
    body = nil
  }

  /// The HTTP method to use when invoking a function.
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
  }

  static func httpMethod(_ method: Method?) -> HTTPTypes.HTTPRequest.Method? {
    switch method {
    case .get:
      .get
    case .post:
      .post
    case .put:
      .put
    case .patch:
      .patch
    case .delete:
      .delete
    case nil:
      nil
    }
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
  ///   - timeoutInterval: A per-invocation override for the request timeout. Defaults to
  ///     ``FunctionsClient/requestIdleTimeout`` when `nil`.
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
  ///   - timeoutInterval: A per-invocation override for the request timeout. Defaults to
  ///     ``FunctionsClient/requestIdleTimeout`` when `nil`.
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
