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
    case .httpError(let code, _):
      "Edge Function returned a non-2xx status code: \(code)"
    }
  }
}

/// Options for invoking a function.
public struct FunctionInvokeOptions: Sendable {
  /// Method to use in the function invocation.
  public var method: Method?
  /// Headers to be included in the function invocation.
  public var headers: [String: String] = [:]
  /// Body data to be sent with the function invocation.
  public var body: Data?
  /// The Region to invoke the function in.
  public var region: FunctionRegion?
  /// Query parameters to be included in the function invocation.
  public var query: [String: String] = [:]

  public init() {}

  /// HTTP method for invoking an Edge Function.
  public enum Method: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
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
