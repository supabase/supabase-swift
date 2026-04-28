import Foundation

/// An error type representing failures that can occur when invoking an Edge Function.
public enum FunctionsError: Error, LocalizedError {
  /// The Supabase relay reported an error before the function could respond.
  ///
  /// This typically indicates a network or infrastructure problem between the client and the
  /// Supabase edge network rather than an error inside the function itself.
  case relayError

  /// The Edge Function responded with a non-2xx HTTP status code.
  ///
  /// - Parameters:
  ///   - code: The HTTP status code returned by the function.
  ///   - data: The raw response body, which may contain a JSON error payload from the function.
  ///
  /// ## Example
  ///
  /// ```swift
  /// do {
  ///   let (data, _) = try await functions.invoke("my-function")
  /// } catch FunctionsError.httpError(let code, let data) {
  ///   let message = String(data: data, encoding: .utf8) ?? "<binary>"
  ///   print("Function failed with status \(code): \(message)")
  /// }
  /// ```
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

/// Options used to customise a single Edge Function invocation.
///
/// Build an instance by passing a closure to any of the `invoke` methods on ``FunctionsClient``:
///
/// ```swift
/// try await functions.invoke("my-function") {
///   $0.method = .post
///   $0.body = try! JSONEncoder().encode(payload)
///   $0.headers["Content-Type"] = "application/json"
///   $0.region = .usEast1
/// }
/// ```
public struct FunctionInvokeOptions: Sendable {
  /// The HTTP method to use for the invocation. Defaults to `.post` when `nil`.
  public var method: Method?

  /// Additional HTTP headers merged into the request.
  ///
  /// These headers are merged with the client-level headers set on ``FunctionsClient/headers``.
  /// Per-invocation values win on collision.
  public var headers: [String: String] = [:]

  /// The raw body data sent with the request.
  ///
  /// Set `headers["Content-Type"]` appropriately when providing a body. For JSON payloads,
  /// encode your value with `JSONEncoder` and set `"Content-Type"` to `"application/json"`.
  public var body: Data?

  /// The region in which to invoke this function, overriding the client-level default.
  ///
  /// When set, an `x-region` header and a `forceFunctionRegion` query parameter are added to
  /// the request. Pass `nil` to fall back to ``FunctionsClient/region``, or automatic routing
  /// if that is also `nil`.
  public var region: FunctionRegion?

  /// URL query parameters appended to the function URL.
  ///
  /// ```swift
  /// $0.query = ["filter": "active", "page": "1"]
  /// ```
  public var query: [String: String] = [:]

  /// Creates a default `FunctionInvokeOptions` with all fields at their zero values.
  public init() {}

  /// HTTP methods supported for Edge Function invocations.
  public enum Method: String, Sendable {
    /// Retrieves data without a request body. Useful for read-only functions.
    case get = "GET"
    /// Submits data to the function. This is the default when no method is specified.
    case post = "POST"
    /// Replaces a resource; the function receives the full new representation.
    case put = "PUT"
    /// Partially updates a resource; the function receives only the changed fields.
    case patch = "PATCH"
    /// Requests the function to delete a resource.
    case delete = "DELETE"
  }
}

/// A Supabase Edge Network region identifier.
///
/// Use the predefined static constants for known regions, or create a custom value with
/// ``init(rawValue:)`` or a string literal when targeting a region not listed here:
///
/// ```swift
/// // Using a predefined constant
/// $0.region = .usEast1
///
/// // Using a string literal (ExpressibleByStringLiteral)
/// $0.region = "ap-northeast-1"
///
/// // Using a custom raw value
/// $0.region = FunctionRegion(rawValue: "custom-region")
/// ```
public struct FunctionRegion: RawRepresentable, Hashable, Sendable {
  /// The raw region string sent in the `x-region` header and `forceFunctionRegion` query parameter.
  public var rawValue: String

  /// Creates a `FunctionRegion` from an arbitrary region string.
  ///
  /// - Parameter rawValue: The region identifier, e.g. `"us-east-1"`.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Asia Pacific (Tokyo).
  public static let apNortheast1 = FunctionRegion(rawValue: "ap-northeast-1")
  /// Asia Pacific (Seoul).
  public static let apNortheast2 = FunctionRegion(rawValue: "ap-northeast-2")
  /// Asia Pacific (Mumbai).
  public static let apSouth1 = FunctionRegion(rawValue: "ap-south-1")
  /// Asia Pacific (Singapore).
  public static let apSoutheast1 = FunctionRegion(rawValue: "ap-southeast-1")
  /// Asia Pacific (Sydney).
  public static let apSoutheast2 = FunctionRegion(rawValue: "ap-southeast-2")
  /// Canada (Central).
  public static let caCentral1 = FunctionRegion(rawValue: "ca-central-1")
  /// Europe (Frankfurt).
  public static let euCentral1 = FunctionRegion(rawValue: "eu-central-1")
  /// Europe (Ireland).
  public static let euWest1 = FunctionRegion(rawValue: "eu-west-1")
  /// Europe (London).
  public static let euWest2 = FunctionRegion(rawValue: "eu-west-2")
  /// Europe (Paris).
  public static let euWest3 = FunctionRegion(rawValue: "eu-west-3")
  /// South America (São Paulo).
  public static let saEast1 = FunctionRegion(rawValue: "sa-east-1")
  /// US East (N. Virginia).
  public static let usEast1 = FunctionRegion(rawValue: "us-east-1")
  /// US West (N. California).
  public static let usWest1 = FunctionRegion(rawValue: "us-west-1")
  /// US West (Oregon).
  public static let usWest2 = FunctionRegion(rawValue: "us-west-2")
}

extension FunctionRegion: ExpressibleByStringLiteral {
  /// Creates a `FunctionRegion` from a string literal.
  ///
  /// - Parameter value: The region identifier string.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
}
