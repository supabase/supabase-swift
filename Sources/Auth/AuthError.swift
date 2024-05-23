import Foundation

public enum AuthError: LocalizedError, Sendable, Equatable {
  case missingExpClaim
  case malformedJWT
  case sessionNotFound
  case api(APIError)

  /// Error thrown during PKCE flow.
  case pkce(PKCEFailureReason)

  case invalidImplicitGrantFlowURL
  case missingURL
  case invalidRedirectScheme

  /// An error returned by the API.
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
    /// Code verifier not found in the URL.
    case codeVerifierNotFound

    /// Not a valid PKCE flow URL.
    case invalidPKCEFlowURL
  }

  public var errorDescription: String? {
    switch self {
    case let .api(error): error.errorDescription ?? error.msg ?? error.error
    case .missingExpClaim: "Missing expiration claim in the access token."
    case .malformedJWT: "A malformed JWT received."
    case .sessionNotFound: "Unable to get a valid session."
    case let .pkce(reason): reason.errorDescription
    case .invalidImplicitGrantFlowURL: "Not a valid implicit grant flow url."
    case .missingURL: "Missing URL."
    case .invalidRedirectScheme: "Invalid redirect scheme."
    }
  }
}

extension AuthError.PKCEFailureReason {
  var errorDescription: String {
    switch self {
    case .codeVerifierNotFound: "A code verifier wasn't found in PKCE flow."
    case .invalidPKCEFlowURL: "Not a valid PKCE flow url."
    }
  }
}
