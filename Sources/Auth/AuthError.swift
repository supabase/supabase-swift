import Foundation

public enum AuthError: LocalizedError, Sendable, Equatable {
  case missingExpClaim
  case malformedJWT
  case sessionNotFound
  case api(APIError)
  case pkce(PKCEFailureReason)
  case invalidImplicitGrantFlowURL
  case missingURL
  case invalidRedirectScheme

  public struct APIError: Error, Decodable, Sendable, Equatable {
    /// A basic message describing the problem with the request. Usually missing if
    /// ``AuthError/APIError/error`` is present.
    public var msg: String?

    /// The HTTP status code. Usually missing if ``AuthError/APIError/error`` is present.
    public var code: Int?

    /// Certain responses will contain this property with the provided values.
    ///
    /// Usually one of these:
    ///   - `invalid_request`
    ///   - `unauthorized_client`
    ///   - `access_denied`
    ///   - `server_error`
    ///   - `temporarily_unavailable`
    ///   - `unsupported_otp_type`
    public var error: String?

    /// Certain responses that have an ``AuthError/APIError/error`` property may have this property
    /// which describes the error.
    public var errorDescription: String?

    /// Only returned when signing up if the password used is too weak. Inspect the
    /// ``WeakPassword/reasons`` and ``AuthError/APIError/msg`` property to identify the causes.
    public var weakPassword: WeakPassword?
  }

  public enum PKCEFailureReason: Sendable {
    case codeVerifierNotFound
    case invalidPKCEFlowURL
  }

  public var errorDescription: String? {
    switch self {
    case let .api(error): return error.errorDescription ?? error.msg ?? error.error
    case .missingExpClaim: return "Missing expiration claim on access token."
    case .malformedJWT: return "A malformed JWT received."
    case .sessionNotFound: return "Unable to get a valid session."
    case .pkce(.codeVerifierNotFound): return "A code verifier wasn't found in PKCE flow."
    case .pkce(.invalidPKCEFlowURL): return "Not a valid PKCE flow url."
    case .invalidImplicitGrantFlowURL: return "Not a valid implicit grant flow url."
    case .missingURL: return "Missing URL."
    case .invalidRedirectScheme: return "Invalid redirect scheme."
    }
  }
}
