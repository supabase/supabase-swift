import Alamofire
import ConcurrencyExtras
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

/// Supported body types for invoking a function.
public enum FunctionInvokeSupportedBody: Sendable {
  /// A data body, used for binary data, sent with the `Content-Type` header set to `application/octet-stream`.
  case data(Data)
  /// An encodable body, used for JSON data, sent with the `Content-Type` header set to `application/json`.
  case encodable(any Sendable & Encodable, encoder: JSONEncoder?)
  /// A multipart form data body, uploaded using Alamofire's built-in multipart form data support.
  case multipartFormData(@Sendable (MultipartFormData) -> Void)
  /// A string body, used for text data, sent with the `Content-Type` header set to `text/plain`.
  case string(String)
  /// A file URL body, uploaded using Alamofire's built-in file upload support.
  case fileURL(URL)
}

/// Options for invoking a function, used to configure the request.
public struct FunctionInvokeOptions: Sendable {
  /// The HTTP method to use for the request.
  public var method: HTTPMethod = .post

  /// The body of the request.
  public var body: FunctionInvokeSupportedBody?

  /// Query parameters to include in the request.
  public var query: [URLQueryItem] = []

  /// Headers to include in the request.
  public var headers: HTTPHeaders = []

  /// The region to invoke the function in.
  public var region: FunctionRegion?

  /// Timeout for the request.
  public var timeout: TimeInterval?

  public init(
    method: HTTPMethod = .post,
    body: FunctionInvokeSupportedBody? = nil,
    query: [URLQueryItem] = [],
    headers: HTTPHeaders = [],
    region: FunctionRegion? = nil,
    timeout: TimeInterval? = nil,
  ) {
    self.method = method
    self.body = body
    self.query = query
    self.headers = headers
    self.region = region
    self.timeout = timeout
  }
}

/// Function region for specifying AWS regions, used to configure the request.
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

/// Allows creating a `FunctionRegion` from a string literal.
extension FunctionRegion: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}
