import Alamofire
import ConcurrencyExtras
import Foundation

/// Errors that can occur while invoking Supabase Edge Functions.
///
/// This enum provides specific error types for different failure scenarios when calling Edge Functions.
/// All errors include localized descriptions for better user experience.
///
/// ## Examples
///
/// ```swift
/// do {
///   let result = try await functionsClient.invoke("my-function")
/// } catch let error as FunctionsError {
///   switch error {
///   case .relayError:
///     print("Function relay failed")
///   case .httpError(let code, let data):
///     print("HTTP error \(code): \(String(data: data, encoding: .utf8) ?? "")")
///   case .unknown(let underlyingError):
///     print("Unknown error: \(underlyingError)")
///   }
/// }
/// ```
public enum FunctionsError: Error, LocalizedError {
  /// Error indicating a relay error while invoking the Edge Function.
  /// This typically occurs when there's an issue with the Supabase infrastructure.
  case relayError
  
  /// Error indicating a non-2xx status code returned by the Edge Function.
  /// - Parameters:
  ///   - code: The HTTP status code returned by the function
  ///   - data: The response body data (may contain error details)
  case httpError(code: Int, data: Data)

  /// An unknown error that doesn't fit into the other categories.
  /// - Parameter error: The underlying error that occurred
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

/// Supported body types for invoking Edge Functions.
///
/// This enum provides type-safe options for different types of request bodies when invoking functions.
/// Each case automatically sets the appropriate `Content-Type` header.
///
/// ## Examples
///
/// ```swift
/// // JSON data
/// let user = User(name: "John", email: "john@example.com")
/// options.body = .encodable(user)
///
/// // Binary data
/// let imageData = Data(contentsOf: imageURL)
/// options.body = .data(imageData)
///
/// // Text data
/// options.body = .string("Hello, World!")
///
/// // File upload
/// let fileURL = URL(fileURLWithPath: "/path/to/file.pdf")
/// options.body = .fileURL(fileURL)
///
/// // Multipart form data
/// options.body = .multipartFormData { formData in
///   formData.append("value1".data(using: .utf8)!, withName: "field1")
///   formData.append(imageData, withName: "image", fileName: "photo.jpg", mimeType: "image/jpeg")
/// }
/// ```
public enum FunctionInvokeSupportedBody: Sendable {
  /// A data body for binary data.
  /// Sets `Content-Type: application/octet-stream`
  /// - Parameter data: The binary data to send
  case data(Data)
  
  /// An encodable body for JSON data.
  /// Sets `Content-Type: application/json`
  /// - Parameters:
  ///   - encodable: The object to encode as JSON
  ///   - encoder: Optional custom JSON encoder (defaults to standard JSONEncoder)
  case encodable(any Sendable & Encodable, encoder: JSONEncoder?)
  
  /// A multipart form data body for file uploads and form submissions.
  /// Uses Alamofire's built-in multipart form data support.
  /// - Parameter formData: A closure to configure the multipart form data
  case multipartFormData(@Sendable (MultipartFormData) -> Void)
  
  /// A string body for text data.
  /// Sets `Content-Type: text/plain`
  /// - Parameter string: The text string to send
  case string(String)
  
  /// A file URL body for file uploads.
  /// Uses Alamofire's built-in file upload support.
  /// - Parameter url: The URL of the file to upload
  case fileURL(URL)
}

/// Configuration options for invoking Edge Functions.
///
/// This struct provides a comprehensive set of options to customize how functions are invoked.
/// All properties have sensible defaults, so you only need to specify what you want to change.
///
/// ## Examples
///
/// ```swift
/// // Basic usage with defaults
/// let options = FunctionInvokeOptions()
///
/// // Custom configuration
/// let options = FunctionInvokeOptions(
///   method: .post,
///   body: .encodable(["key": "value"]),
///   query: [URLQueryItem(name: "limit", value: "10")],
///   headers: HTTPHeaders(["X-Custom": "header"]),
///   region: .usEast1,
///   timeout: 30.0
/// )
///
/// // Using in function invocation
/// try await functionsClient.invoke("my-function") { options in
///   options.method = .put
///   options.body = .string("Hello, World!")
///   options.query.append(URLQueryItem(name: "id", value: "123"))
/// }
/// ```
public struct FunctionInvokeOptions: Sendable {
  /// The HTTP method to use for the request.
  /// Defaults to `.post`
  public var method: HTTPMethod = .post

  /// The body of the request.
  /// Can be JSON, binary data, text, file upload, or multipart form data.
  public var body: FunctionInvokeSupportedBody?

  /// Query parameters to include in the request URL.
  /// Defaults to an empty array.
  public var query: [URLQueryItem] = []

  /// Additional headers to include in the request.
  /// These will be merged with the client's default headers.
  public var headers: HTTPHeaders = []

  /// The AWS region to invoke the function in.
  /// If not specified, uses the client's default region or Supabase's default.
  public var region: FunctionRegion?

  /// Timeout for the request in seconds.
  /// If not specified, uses the client's default timeout (150 seconds).
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

/// AWS regions for Edge Function deployment and invocation.
///
/// This struct represents AWS regions where Supabase Edge Functions can be deployed and invoked.
/// It conforms to `ExpressibleByStringLiteral` for convenient string-based initialization.
///
/// ## Examples
///
/// ```swift
/// // Using predefined regions
/// let region = FunctionRegion.usEast1
///
/// // Using string literal
/// let region: FunctionRegion = "eu-west-1"
///
/// // Custom region
/// let customRegion = FunctionRegion(rawValue: "ap-southeast-1")
///
/// // In function invocation
/// try await functionsClient.invoke("my-function") { options in
///   options.region = .usWest2
/// }
/// ```
public struct FunctionRegion: RawRepresentable, Sendable {
  /// The raw string value of the region.
  public let rawValue: String
  
  /// Creates a new region with the specified raw value.
  /// - Parameter rawValue: The AWS region identifier (e.g., "us-east-1")
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
