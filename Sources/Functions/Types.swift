import Alamofire
import Foundation

/// An error type representing various errors that can occur while invoking functions.
public enum FunctionsError: SupabaseError {
  /// Error indicating a relay error while invoking the Edge Function.
  case relayError
  /// Error indicating a non-2xx status code returned by the Edge Function.
  case httpError(code: Int, data: Data)
  /// Error indicating a function was not found.
  case functionNotFound(functionName: String)
  /// Error indicating a function execution failed.
  case functionError(message: String, data: Data?)

  case unknown(any Error)

  /// A localized description of the error.
  public var errorDescription: String? {
    switch self {
    case .relayError:
      "Relay Error invoking the Edge Function"
    case let .httpError(code, _):
      "Edge Function returned a non-2xx status code: \(code)"
    case let .functionNotFound(functionName):
      "Function '\(functionName)' not found"
    case let .functionError(message, _):
      "Function execution failed: \(message)"
    case let .unknown(error):
      "Unknown error: \(error.localizedDescription)"
    }
  }
  
  // MARK: - SupabaseError Protocol Conformance
  
  public var errorCode: String {
    switch self {
    case .relayError: return SupabaseErrorCode.relayError.rawValue
    case .httpError: return SupabaseErrorCode.functionError.rawValue
    case .functionNotFound: return SupabaseErrorCode.functionNotFound.rawValue
    case .functionError: return SupabaseErrorCode.functionError.rawValue
    case .unknown: return SupabaseErrorCode.unknown.rawValue
    }
  }
  
  public var underlyingData: Data? {
    switch self {
    case let .httpError(_, data), let .functionError(_, data?):
      return data
    default:
      return nil
    }
  }
  
  public var underlyingResponse: HTTPURLResponse? {
    return nil
  }
  
  public var context: [String: String] {
    switch self {
    case let .httpError(code, _):
      return ["statusCode": String(code)]
    case let .functionNotFound(functionName):
      return ["functionName": functionName]
    case .functionError:
      return [:]
    default:
      return [:]
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

/// Function region enum for backward compatibility.
public enum FunctionRegion: String, Sendable {
  case usEast1 = "us-east-1"
  case usWest1 = "us-west-1"
  case euWest1 = "eu-west-1"
  case apSoutheast1 = "ap-southeast-1"
  case apNortheast1 = "ap-northeast-1"
}