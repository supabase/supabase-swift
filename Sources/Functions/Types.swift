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
    case .httpError(let code, _):
      "Edge Function returned a non-2xx status code: \(code)"
    }
  }
}

/// Options for invoking a function.
public struct FunctionInvokeOptions: Sendable {
  /// HTTP method to use in the function invocation.
  public var method: Method?
  /// Headers to be included in the function invocation.
  public var headers: [String: String] = [:]
  /// Body data to be sent with the function invocation.
  public var body: Data?
  /// The region to invoke the function in.
  public var region: FunctionRegion?
  /// Query parameters to be included in the function invocation.
  public var query: [String: String] = [:]

  /// Creates a `FunctionInvokeOptions` with default values.
  public init() {}

  /// HTTP methods available for function invocation.
  public enum Method: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
  }

  static func httpMethod(_ method: Method?) -> HTTPTypes.HTTPRequest.Method? {
    switch method {
    case .get: .get
    case .post: .post
    case .put: .put
    case .patch: .patch
    case .delete: .delete
    case nil: nil
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
/// options.region = .usEast1
/// // custom region
/// options.region = FunctionRegion(rawValue: "custom-region")
/// options.region = "custom-region"
/// ```
public struct FunctionRegion: RawRepresentable, Hashable, Sendable {
  /// The raw region string sent in the request.
  public var rawValue: String

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

// MARK: - Deprecated initializers

extension FunctionInvokeOptions {
  @available(*, deprecated, message: "Use the builder-style invoke API instead.")
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: String? = nil,
    body: some Encodable,
    encoder: JSONEncoder = JSONEncoder()
  ) {
    self.init()
    self.method = method
    self.region = region.map { FunctionRegion(rawValue: $0) }
    self.query = query.reduce(into: [:]) { dict, item in
      if let value = item.value { dict[item.name] = value }
    }
    var computedHeaders: [String: String] = [:]
    switch body {
    case let string as String:
      computedHeaders["Content-Type"] = "text/plain"
      self.body = string.data(using: .utf8)
    case let data as Data:
      computedHeaders["Content-Type"] = "application/octet-stream"
      self.body = data
    default:
      computedHeaders["Content-Type"] = "application/json"
      self.body = try? encoder.encode(body)
    }
    self.headers = computedHeaders.merging(headers) { _, new in new }
  }

  @available(*, deprecated, message: "Use the builder-style invoke API instead.")
  @_disfavoredOverload
  public init(
    method: Method? = nil,
    query: [URLQueryItem] = [],
    headers: [String: String] = [:],
    region: String? = nil
  ) {
    self.init()
    self.method = method
    self.headers = headers
    self.region = region.map { FunctionRegion(rawValue: $0) }
    self.query = query.reduce(into: [:]) { dict, item in
      if let value = item.value { dict[item.name] = value }
    }
  }

  @available(*, deprecated, message: "Use the builder-style invoke API instead.")
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil,
    body: some Encodable,
    encoder: JSONEncoder = JSONEncoder()
  ) {
    self.init(
      method: method, query: [], headers: headers, region: region?.rawValue, body: body,
      encoder: encoder)
  }

  @available(*, deprecated, message: "Use the builder-style invoke API instead.")
  public init(
    method: Method? = nil,
    headers: [String: String] = [:],
    region: FunctionRegion? = nil
  ) {
    self.init(method: method, query: [], headers: headers, region: region?.rawValue)
  }
}
