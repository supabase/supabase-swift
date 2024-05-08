import _Helpers
import Foundation

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
    case let .httpError(code, _):
      "Edge Function returned a non-2xx status code: \(code)"
    }
  }
}

/// Options for invoking a function.
public struct FunctionInvokeOptions: Sendable {
  /// Method to use in the function invocation.
  let method: Method?
  /// Headers to be included in the function invocation.
  let headers: HTTPHeaders
  /// Body data to be sent with the function invocation.
  let body: Data?
  /// The Region to invoke the function in.
  let region: String?

  /// Initializes the `FunctionInvokeOptions` structure.
  ///
  /// - Parameters:
  ///   - method: Method to use in the function invocation.
  ///   - headers: Headers to be included in the function invocation. (Default: empty dictionary)
  ///   - region: The Region to invoke the function in.
  ///   - body: The body data to be sent with the function invocation. (Default: nil)
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: String? = nil,
    body: some Encodable
  ) {
    var defaultHeaders = HTTPHeaders()

    switch body {
    case let string as String:
      defaultHeaders["Content-Type"] = "text/plain"
      self.body = string.data(using: .utf8)
    case let data as Data:
      defaultHeaders["Content-Type"] = "application/octet-stream"
      self.body = data
    default:
      // default, assume this is JSON
      defaultHeaders["Content-Type"] = "application/json"
      self.body = try? JSONEncoder().encode(body)
    }

    self.method = method
    self.headers = defaultHeaders.merged(with: HTTPHeaders(headers))
    self.region = region
  }

  /// Initializes the `FunctionInvokeOptions` structure.
  ///
  /// - Parameters:
  ///   - method: Method to use in the function invocation.
  ///   - headers: Headers to be included in the function invocation. (Default: empty dictionary)
  ///   - region: The Region to invoke the function in.
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: String? = nil
  ) {
    self.method = method
    self.headers = HTTPHeaders(headers)
    self.region = region
    body = nil
  }

  public enum Method: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
  }

  var httpMethod: HTTPMethod? {
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

public enum FunctionRegion: String, Sendable {
  case apNortheast1 = "ap-northeast-1"
  case apNortheast2 = "ap-northeast-2"
  case apSouth1 = "ap-south-1"
  case apSoutheast1 = "ap-southeast-1"
  case apSoutheast2 = "ap-southeast-2"
  case caCentral1 = "ca-central-1"
  case euCentral1 = "eu-central-1"
  case euWest1 = "eu-west-1"
  case euWest2 = "eu-west-2"
  case euWest3 = "eu-west-3"
  case saEast1 = "sa-east-1"
  case usEast1 = "us-east-1"
  case usWest1 = "us-west-1"
  case usWest2 = "us-west-2"
}

extension FunctionInvokeOptions {
  /// Initializes the `FunctionInvokeOptions` structure.
  ///
  /// - Parameters:
  ///   - method: Method to use in the function invocation.
  ///   - headers: Headers to be included in the function invocation. (Default: empty dictionary)
  ///   - region: The Region to invoke the function in.
  ///   - body: The body data to be sent with the function invocation. (Default: nil)
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    body: some Encodable
  ) {
    self.init(
      method: method,
      headers: headers,
      region: region?.rawValue,
      body: body
    )
  }

  /// Initializes the `FunctionInvokeOptions` structure.
  ///
  /// - Parameters:
  ///   - method: Method to use in the function invocation.
  ///   - headers: Headers to be included in the function invocation. (Default: empty dictionary)
  ///   - region: The Region to invoke the function in.
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil
  ) {
    self.init(method: method, headers: headers, region: region?.rawValue)
  }
}
