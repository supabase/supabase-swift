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
    case let .httpError(code, _):
      "Edge Function returned a non-2xx status code: \(code)"
    case let .unknown(error):
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
  public var body: Data?
  
  /// Query parameters to include in the request.
  public var query: [URLQueryItem] = []
  
  /// Headers to include in the request.
  public var headers: [HTTPHeader] = []
  
  /// The region to invoke the function in.
  public var region: String?
  
  /// Timeout for the request.
  public var timeout: TimeInterval?
  
  /// Retry configuration for failed requests.
  public var retryConfiguration: RetryConfiguration?
  
  public init(
    method: HTTPMethod = .post,
    body: Data? = nil,
    query: [URLQueryItem] = [],
    headers: [HTTPHeader] = [],
    region: String? = nil,
    timeout: TimeInterval? = nil,
    retryConfiguration: RetryConfiguration? = nil
  ) {
    self.method = method
    self.body = body
    self.query = query
    self.headers = headers
    self.region = region
    self.timeout = timeout
    self.retryConfiguration = retryConfiguration
  }
  
  /// Configuration for retrying failed requests.
  public struct RetryConfiguration: Sendable {
    /// Maximum number of retry attempts.
    public let maxRetries: Int
    
    /// Base delay between retries (exponential backoff will be applied).
    public let baseDelay: TimeInterval
    
    /// Maximum delay between retries.
    public let maxDelay: TimeInterval
    
    /// HTTP status codes that should trigger a retry.
    public let retryableStatusCodes: Set<Int>
    
    public init(
      maxRetries: Int = 3,
      baseDelay: TimeInterval = 1.0,
      maxDelay: TimeInterval = 30.0,
      retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) {
      self.maxRetries = maxRetries
      self.baseDelay = baseDelay
      self.maxDelay = maxDelay
      self.retryableStatusCodes = retryableStatusCodes
    }
  }
  
  /// Convenience initializer for JSON body.
  public init(
    method: HTTPMethod = .post,
    jsonBody: some Encodable,
    query: [URLQueryItem] = [],
    headers: [HTTPHeader] = [],
    region: String? = nil,
    timeout: TimeInterval? = nil,
    retryConfiguration: RetryConfiguration? = nil
  ) throws {
    let body = try JSONEncoder().encode(jsonBody)
    self.init(
      method: method,
      body: body,
      query: query,
      headers: headers + [.contentType("application/json")],
      region: region,
      timeout: timeout,
      retryConfiguration: retryConfiguration
    )
  }
  
  /// Convenience initializer for string body.
  public init(
    method: HTTPMethod = .post,
    stringBody: String,
    query: [URLQueryItem] = [],
    headers: [HTTPHeader] = [],
    region: String? = nil,
    timeout: TimeInterval? = nil,
    retryConfiguration: RetryConfiguration? = nil
  ) {
    let body = stringBody.data(using: .utf8)
    self.init(
      method: method,
      body: body,
      query: query,
      headers: headers + [.contentType("text/plain")],
      region: region,
      timeout: timeout,
      retryConfiguration: retryConfiguration
    )
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