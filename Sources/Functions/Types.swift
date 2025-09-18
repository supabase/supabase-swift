import Alamofire
import Foundation

/// An error type representing various errors that can occur while invoking functions.
public enum FunctionsError: Error, LocalizedError {
  /// Error indicating a relay error while invoking the Edge Function.
  case relayError
  /// Error indicating a non-2xx status code returned by the Edge Function.
  case httpError(code: Int, data: Data)

  case unknown(any Error)

  /// A localized description of the error.
  public var errorDescription: String? {
    switch self {
    case .relayError:
      "Relay Error invoking the Edge Function"
    case .httpError(let code, _):
      "Edge Function returned a non-2xx status code: \(code)"
    case .unknown(let error):
      "Unkown error: \(error.localizedDescription)"
    }
  }
}

func mapToFunctionsError(_ error: any Error) -> FunctionsError {
  if let error = error as? FunctionsError {
    return error
  }

  if let error = error.asAFError,
    let underlyingError = error.underlyingError as? FunctionsError
  {
    return underlyingError
  }

  return FunctionsError.unknown(error)
}

/// Options for invoking a function.
public struct FunctionInvokeOptions: Sendable {
  /// The HTTP method to use for the request.
  public var method: HTTPMethod = .post

  /// The body of the request.
  public var rawBody: Data?

  /// Query parameters to include in the request.
  public var query: [URLQueryItem] = []

  /// Headers to include in the request.
  public var headers: HTTPHeaders = []

  /// The region to invoke the function in.
  public var region: FunctionRegion?

  /// Timeout for the request.
  public var timeout: TimeInterval?

  /// Set the body of the request to a data.
  public mutating func setBody(_ body: Data) {
    self.rawBody = body
    headers["Content-Type"] = "application/octet-stream"
  }

  /// Set the body of the request to a string.
  public mutating func setBody(_ body: String) {
    self.rawBody = body.data(using: .utf8)
    headers["Content-Type"] = "text/plain"
  }

  /// Set the body of the request to a JSON encodable.
  public mutating func setBody(_ body: some Encodable) {
    self.rawBody = try? JSONEncoder().encode(body)
    headers["Content-Type"] = "application/json"
  }

  public init(
    method: HTTPMethod = .post,
    rawBody: Data? = nil,
    query: [URLQueryItem] = [],
    headers: HTTPHeaders = [],
    region: FunctionRegion? = nil,
    timeout: TimeInterval? = nil,
  ) {
    self.method = method
    self.rawBody = rawBody
    self.query = query
    self.headers = headers
    self.region = region
    self.timeout = timeout
  }
}

/// Function region for specifying AWS regions.
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
