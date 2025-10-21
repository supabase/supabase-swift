import Foundation
import HTTPTypes

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
  let headers: HTTPFields
  /// Body data to be sent with the function invocation.
  let body: Data?
  /// The Region to invoke the function in.
  let region: FunctionRegion?
  /// The query to be included in the function invocation.
  let query: [URLQueryItem]

  /// Initializes the `FunctionInvokeOptions` structure.
  ///
  /// - Parameters:
  ///   - method: Method to use in the function invocation.
  ///   - query: The query to be included in the function invocation.
  ///   - headers: Headers to be included in the function invocation. (Default: empty dictionary)
  ///   - region: The Region to invoke the function in.
  ///   - body: The body data to be sent with the function invocation. (Default: nil)
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    body: some Encodable
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
      // default, assume this is JSON
      defaultHeaders[.contentType] = "application/json"
      self.body = try? JSONEncoder().encode(body)
    }

    self.method = method
    self.headers = defaultHeaders.merging(with: HTTPFields(headers))
    self.region = region
    self.query = query
  }

  /// Initializes the `FunctionInvokeOptions` structure.
  ///
  /// - Parameters:
  ///   - method: Method to use in the function invocation.
  ///   - query: The query to be included in the function invocation.
  ///   - headers: Headers to be included in the function invocation. (Default: empty dictionary)
  ///   - region: The Region to invoke the function in.
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: FunctionRegion? = nil
  ) {
    self.method = method
    self.headers = HTTPFields(headers)
    self.region = region
    self.query = query
    body = nil
  }

  public enum Method: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
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

public struct FunctionRegion: RawRepresentable, Sendable {
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
