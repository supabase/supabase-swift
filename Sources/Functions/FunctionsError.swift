//
//  FunctionsError.swift
//  Functions
//
//  Created by Guilherme Souza on 05/10/26.
//

public import Foundation
public import Helpers

/// An error thrown by ``FunctionsClient``.
///
/// Check ``kind`` to learn which party failed. ``response`` carries the status, headers and body
/// for ``Kind-swift.struct/relay`` and ``Kind-swift.struct/server``; ``code`` says whether the
/// platform, rather than your function, produced the failure. ``underlyingError`` carries the
/// `URLError`, `DecodingError` or `EncodingError` for ``Kind-swift.struct/transport``,
/// ``Kind-swift.struct/decoding`` and ``Kind-swift.struct/invalidRequest``.
///
/// ```swift
/// do {
///   try await functions.invoke("hello")
/// } catch let error as FunctionsError where error.kind == .server {
///   if error.isPlatformError {
///     print("platform", error.code?.rawValue ?? "?", error.response?.statusCode ?? 0)
///   } else {
///     print("function", error.response?.statusCode ?? 0, error.response?.body ?? Data())
///   }
/// }
/// ```
public struct FunctionsError: SupabaseError {
  /// What failed. Compare against the static members and keep a fallback branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// The Supabase relay could not run the function (`x-relay-error: true`). Your code never
    /// ran: retry later or check the deployment. ``FunctionsError/response`` has the status.
    public static let relay: Kind = "relay"
    /// The function, or the platform in front of it, answered with a non-2xx status. Read
    /// ``FunctionsError/response`` for the status and the body, and ``FunctionsError/code`` to
    /// tell the two apart.
    public static let server: Kind = "server"
    /// No response arrived, so whether the function ran is unknown. Retry only if the function
    /// is idempotent, or after confirming it did not run. ``FunctionsError/underlyingError`` is
    /// usually a `URLError`.
    public static let transport: Kind = "transport"
    /// The function answered 2xx but the body could not be decoded as the requested type.
    /// Nothing to retry; fix the type or the function. ``FunctionsError/underlyingError`` is
    /// usually a `DecodingError`.
    public static let decoding: Kind = "decoding"
    /// The SDK refused to send the request: the body could not be encoded. Nothing was sent.
    /// ``FunctionsError/underlyingError`` is the `EncodingError`.
    public static let invalidRequest: Kind = "invalidRequest"
  }

  /// A platform error code from the `sb-error-code` response header.
  ///
  /// The platform sets one on every failure it produces itself (an unauthorized call, an unknown
  /// function, a worker that failed to boot) and tags a function's own 5xx with
  /// ``edgeFunctionError``. An open set: compare against the static members and keep a fallback
  /// branch. The documented list is the Edge Functions error-codes guide.
  public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// 400: the request URL is malformed.
    public static let invalidURL: Code = "INVALID_URL"
    /// 401: no `Authorization` header.
    public static let unauthorizedNoAuthHeader: Code = "UNAUTHORIZED_NO_AUTH_HEADER"
    /// 401: the bearer token is not a JWT.
    public static let unauthorizedInvalidJWTFormat: Code = "UNAUTHORIZED_INVALID_JWT_FORMAT"
    /// 401: a legacy JWT key was sent where a session token is required.
    public static let unauthorizedLegacyJWT: Code = "UNAUTHORIZED_LEGACY_JWT"
    /// 401: the JWT uses an asymmetric algorithm the gateway cannot verify.
    public static let unauthorizedAsymmetricJWT: Code = "UNAUTHORIZED_ASYMMETRIC_JWT"
    /// 401: the JWT uses an unsupported algorithm.
    public static let unauthorizedUnsupportedTokenAlgorithm: Code =
      "UNAUTHORIZED_UNSUPPORTED_TOKEN_ALGORITHM"
    /// 404: no such function.
    public static let notFound: Code = "NOT_FOUND"
    /// 404: the function's code could not be found.
    public static let notFoundFunctionBlob: Code = "NOT_FOUND_FUNCTION_BLOB"
    /// 429: the nested-call limit was reached.
    public static let rateLimitExceeded: Code = "RATE_LIMIT_EXCEEDED"
    /// 500: the worker crashed.
    public static let workerError: Code = "WORKER_ERROR"
    /// 500: the function returned a status the gateway cannot relay.
    public static let invalidResponseStatusCode: Code = "INVALID_RESPONSE_STATUS_CODE"
    /// 503: the worker could not boot.
    public static let bootError: Code = "BOOT_ERROR"
    /// 503: the edge runtime failed.
    public static let edgeRuntimeError: Code = "SUPABASE_EDGE_RUNTIME_ERROR"
    /// 503: the edge runtime is degraded.
    public static let edgeRuntimeServiceDegraded: Code = "SUPABASE_EDGE_RUNTIME_SERVICE_DEGRADED"
    /// 504: the request idle timeout was reached.
    public static let idleTimeout: Code = "IDLE_TIMEOUT"
    /// 546: the worker hit its memory, CPU or wall-clock limit.
    public static let workerResourceLimit: Code = "WORKER_RESOURCE_LIMIT"
    /// Your function's own 5xx. The platform tags it so a function's failure is distinguishable
    /// from its own; ``FunctionsError/isPlatformError`` is `false` for it.
    public static let edgeFunctionError: Code = "EDGE_FUNCTION_ERROR"
  }

  public var kind: Kind
  public var message: String
  /// The platform error code, when the platform produced the failure or tagged your function's
  /// 5xx. `nil` for a function's own non-5xx answer and for failures that never reached the
  /// server.
  public var code: Code?
  public var response: HTTPErrorResponse?
  public var underlyingError: (any Error)?

  /// `true` when ``code`` names a platform failure rather than your function's own response.
  public var isPlatformError: Bool {
    code != nil && code != .edgeFunctionError
  }

  public init(
    kind: Kind,
    message: String,
    code: Code? = nil,
    response: HTTPErrorResponse? = nil,
    underlyingError: (any Error)? = nil
  ) {
    self.kind = kind
    self.message = message
    self.code = code
    self.response = response
    self.underlyingError = underlyingError
  }

  public var description: String {
    var text = formattedDescription(kind: kind.rawValue)
    if let code {
      text += " [code \(code.rawValue)]"
    }
    return text
  }
}
