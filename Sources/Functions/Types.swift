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
public struct FunctionInvokeOptions {
  /// Method to use in the function invocation.
  let method: Method?
  /// Headers to be included in the function invocation.
  let headers: [String: String]
  /// Body data to be sent with the function invocation.
  let body: Data?

  /// Initializes the `FunctionInvokeOptions` structure.
  ///
  /// - Parameters:
  ///   - method: Method to use in the function invocation.
  ///   - headers: Headers to be included in the function invocation. (Default: empty dictionary)
  ///   - body: The body data to be sent with the function invocation. (Default: nil)
  public init(method: Method? = nil, headers: [String: String] = [:], body: some Encodable) {
    var defaultHeaders = headers

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
    self.headers = defaultHeaders.merging(headers) { _, new in new }
  }

  /// Initializes the `FunctionInvokeOptions` structure.
  ///
  /// - Parameters:
  ///   - method: Method to use in the function invocation.
  ///   - headers: Headers to be included in the function invocation. (Default: empty dictionary)
  public init(method: Method? = nil, headers: [String: String] = [:]) {
    self.method = method
    self.headers = headers
    body = nil
  }

  public enum Method: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
  }
}
