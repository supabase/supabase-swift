public import Foundation
import HTTPRuntime
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
  let headers: [String: String]
  /// Body data to be sent with the function invocation.
  let body: Data?
  /// The Region to invoke the function in.
  let region: String?
  /// The query to be included in the function invocation.
  let query: [URLQueryItem]

  /// Creates options for a function invocation with an encodable body.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - query: Query items appended to the function URL.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region string to invoke the function in.
  ///   - body: The body to encode and send. Strings are sent as `text/plain`, `Data` as
  ///     `application/octet-stream`, and all other `Encodable` values as JSON.
  ///   - encoder: The JSON encoder used when `body` is encoded as JSON.
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: String? = nil,
    body: some Encodable,
    encoder: JSONEncoder = JSONEncoder()
  ) {
    var defaultHeaders: [String: String] = [:]

    switch body {
    case let string as String:
      defaultHeaders["Content-Type"] = "text/plain"
      self.body = string.data(using: .utf8)
    case let data as Data:
      defaultHeaders["Content-Type"] = "application/octet-stream"
      self.body = data
    default:
      defaultHeaders["Content-Type"] = "application/json"
      self.body = try? encoder.encode(body)
    }

    self.method = method
    self.headers = defaultHeaders.merging(headers) { $1 }
    self.region = region
    self.query = query
  }

  /// Creates options for a function invocation with no body.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - query: Query items appended to the function URL.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region string to invoke the function in.
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: String? = nil
  ) {
    self.method = method
    self.headers = headers
    self.region = region
    self.query = query
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

  static func httpMethod(_ method: Method?) -> HTTPMethod? {
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

/// A Supabase Edge Function deployment region.
public enum FunctionRegion: String, Sendable {
  /// Asia Pacific (Tokyo).
  case apNortheast1 = "ap-northeast-1"
  /// Asia Pacific (Seoul).
  case apNortheast2 = "ap-northeast-2"
  /// Asia Pacific (Mumbai).
  case apSouth1 = "ap-south-1"
  /// Asia Pacific (Singapore).
  case apSoutheast1 = "ap-southeast-1"
  /// Asia Pacific (Sydney).
  case apSoutheast2 = "ap-southeast-2"
  /// Canada (Central).
  case caCentral1 = "ca-central-1"
  /// Europe (Frankfurt).
  case euCentral1 = "eu-central-1"
  /// Europe (Ireland).
  case euWest1 = "eu-west-1"
  /// Europe (London).
  case euWest2 = "eu-west-2"
  /// Europe (Paris).
  case euWest3 = "eu-west-3"
  /// South America (São Paulo).
  case saEast1 = "sa-east-1"
  /// US East (N. Virginia).
  case usEast1 = "us-east-1"
  /// US West (N. California).
  case usWest1 = "us-west-1"
  /// US West (Oregon).
  case usWest2 = "us-west-2"
}

extension FunctionInvokeOptions {
  /// Creates options for a function invocation with an encodable body and a typed region.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region to invoke the function in.
  ///   - body: The body to encode and send.
  ///   - encoder: The JSON encoder used when `body` is encoded as JSON.
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    body: some Encodable,
    encoder: JSONEncoder = JSONEncoder()
  ) {
    self.init(
      method: method,
      headers: headers,
      region: region?.rawValue,
      body: body,
      encoder: encoder
    )
  }

  /// Creates options for a function invocation with no body and a typed region.
  /// - Parameters:
  ///   - method: The HTTP method to use. Defaults to POST when `nil`.
  ///   - headers: Additional headers to include in the request.
  ///   - region: The region to invoke the function in.
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil
  ) {
    self.init(method: method, headers: headers, region: region?.rawValue)
  }
}
