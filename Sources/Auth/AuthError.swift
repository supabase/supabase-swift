import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// An error code thrown by the server.
public struct ErrorCode: Decodable, RawRepresentable, Sendable, Hashable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(_ rawValue: String) {
    self.init(rawValue: rawValue)
  }
}

// Known error codes. Note that the server may also return other error codes
// not included in this list (if the client library is older than the version
// on the server).
extension ErrorCode {
  /// ErrorCodeUnknown should not be used directly, it only indicates a failure in the error handling system in such a way that an error code was not assigned properly.
  public static let unknown = ErrorCode("unknown")

  /// ErrorCodeUnexpectedFailure signals an unexpected failure such as a 500 Internal Server Error.
  public static let unexpectedFailure = ErrorCode("unexpected_failure")

  public static let validationFailed = ErrorCode("validation_failed")
  public static let badJSON = ErrorCode("bad_json")
  public static let emailExists = ErrorCode("email_exists")
  public static let phoneExists = ErrorCode("phone_exists")
  public static let badJWT = ErrorCode("bad_jwt")
  public static let notAdmin = ErrorCode("not_admin")
  public static let noAuthorization = ErrorCode("no_authorization")
  public static let userNotFound = ErrorCode("user_not_found")
  public static let sessionNotFound = ErrorCode("session_not_found")
  public static let sessionExpired = ErrorCode("session_expired")
  public static let refreshTokenNotFound = ErrorCode("refresh_token_not_found")
  public static let refreshTokenAlreadyUsed = ErrorCode("refresh_token_already_used")
  public static let flowStateNotFound = ErrorCode("flow_state_not_found")
  public static let flowStateExpired = ErrorCode("flow_state_expired")
  public static let signupDisabled = ErrorCode("signup_disabled")
  public static let userBanned = ErrorCode("user_banned")
  public static let providerEmailNeedsVerification = ErrorCode(
    "provider_email_needs_verification")
  public static let inviteNotFound = ErrorCode("invite_not_found")
  public static let badOAuthState = ErrorCode("bad_oauth_state")
  public static let badOAuthCallback = ErrorCode("bad_oauth_callback")
  public static let oauthProviderNotSupported = ErrorCode("oauth_provider_not_supported")
  public static let unexpectedAudience = ErrorCode("unexpected_audience")
  public static let singleIdentityNotDeletable = ErrorCode("single_identity_not_deletable")
  public static let emailConflictIdentityNotDeletable = ErrorCode(
    "email_conflict_identity_not_deletable")
  public static let identityAlreadyExists = ErrorCode("identity_already_exists")
  public static let emailProviderDisabled = ErrorCode("email_provider_disabled")
  public static let phoneProviderDisabled = ErrorCode("phone_provider_disabled")
  public static let tooManyEnrolledMFAFactors = ErrorCode("too_many_enrolled_mfa_factors")
  public static let mfaFactorNameConflict = ErrorCode("mfa_factor_name_conflict")
  public static let mfaFactorNotFound = ErrorCode("mfa_factor_not_found")
  public static let mfaIPAddressMismatch = ErrorCode("mfa_ip_address_mismatch")
  public static let mfaChallengeExpired = ErrorCode("mfa_challenge_expired")
  public static let mfaVerificationFailed = ErrorCode("mfa_verification_failed")
  public static let mfaVerificationRejected = ErrorCode("mfa_verification_rejected")
  public static let insufficientAAL = ErrorCode("insufficient_aal")
  public static let captchaFailed = ErrorCode("captcha_failed")
  public static let samlProviderDisabled = ErrorCode("saml_provider_disabled")
  public static let manualLinkingDisabled = ErrorCode("manual_linking_disabled")
  public static let smsSendFailed = ErrorCode("sms_send_failed")
  public static let emailNotConfirmed = ErrorCode("email_not_confirmed")
  public static let phoneNotConfirmed = ErrorCode("phone_not_confirmed")
  public static let samlRelayStateNotFound = ErrorCode("saml_relay_state_not_found")
  public static let samlRelayStateExpired = ErrorCode("saml_relay_state_expired")
  public static let samlIdPNotFound = ErrorCode("saml_idp_not_found")
  public static let samlAssertionNoUserID = ErrorCode("saml_assertion_no_user_id")
  public static let samlAssertionNoEmail = ErrorCode("saml_assertion_no_email")
  public static let userAlreadyExists = ErrorCode("user_already_exists")
  public static let ssoProviderNotFound = ErrorCode("sso_provider_not_found")
  public static let samlMetadataFetchFailed = ErrorCode("saml_metadata_fetch_failed")
  public static let samlIdPAlreadyExists = ErrorCode("saml_idp_already_exists")
  public static let ssoDomainAlreadyExists = ErrorCode("sso_domain_already_exists")
  public static let samlEntityIDMismatch = ErrorCode("saml_entity_id_mismatch")
  public static let conflict = ErrorCode("conflict")
  public static let providerDisabled = ErrorCode("provider_disabled")
  public static let userSSOManaged = ErrorCode("user_sso_managed")
  public static let reauthenticationNeeded = ErrorCode("reauthentication_needed")
  public static let samePassword = ErrorCode("same_password")
  public static let reauthenticationNotValid = ErrorCode("reauthentication_not_valid")
  public static let otpExpired = ErrorCode("otp_expired")
  public static let otpDisabled = ErrorCode("otp_disabled")
  public static let identityNotFound = ErrorCode("identity_not_found")
  public static let weakPassword = ErrorCode("weak_password")
  public static let overRequestRateLimit = ErrorCode("over_request_rate_limit")
  public static let overEmailSendRateLimit = ErrorCode("over_email_send_rate_limit")
  public static let overSMSSendRateLimit = ErrorCode("over_sms_send_rate_limit")
  public static let badCodeVerifier = ErrorCode("bad_code_verifier")
  public static let anonymousProviderDisabled = ErrorCode("anonymous_provider_disabled")
  public static let hookTimeout = ErrorCode("hook_timeout")
  public static let hookTimeoutAfterRetry = ErrorCode("hook_timeout_after_retry")
  public static let hookPayloadOverSizeLimit = ErrorCode("hook_payload_over_size_limit")
  public static let hookPayloadInvalidContentType = ErrorCode(
    "hook_payload_invalid_content_type")
  public static let requestTimeout = ErrorCode("request_timeout")
  public static let mfaPhoneEnrollDisabled = ErrorCode("mfa_phone_enroll_not_enabled")
  public static let mfaPhoneVerifyDisabled = ErrorCode("mfa_phone_verify_not_enabled")
  public static let mfaTOTPEnrollDisabled = ErrorCode("mfa_totp_enroll_not_enabled")
  public static let mfaTOTPVerifyDisabled = ErrorCode("mfa_totp_verify_not_enabled")
  public static let mfaWebAuthnEnrollDisabled = ErrorCode(
    "mfa_webauthn_enroll_not_enabled")
  public static let mfaWebAuthnVerifyDisabled = ErrorCode(
    "mfa_webauthn_verify_not_enabled")
  public static let mfaVerifiedFactorExists = ErrorCode("mfa_verified_factor_exists")
  //#nosec G101 -- Not a secret value.
  public static let invalidCredentials = ErrorCode("invalid_credentials")
  public static let emailAddressNotAuthorized = ErrorCode("email_address_not_authorized")
  public static let invalidJWT = ErrorCode("invalid_jwt")
}

public enum AuthError: LocalizedError, Equatable {
  /// Error thrown when a session is required to proceed, but none was found, either thrown by the client, or returned by the server.
  case sessionMissing

  /// Error thrown when password is deemed weak, check associated reasons to know why.
  case weakPassword(message: String, reasons: [String])

  /// Error thrown by API when an error occurs, check `errorCode` to know more,
  /// or use `underlyingData` or `underlyingResponse` for access to the response which originated this error.
  case api(
    message: String,
    errorCode: ErrorCode,
    underlyingData: Data,
    underlyingResponse: HTTPURLResponse
  )

  /// Error thrown when an error happens during PKCE grant flow.
  case pkceGrantCodeExchange(message: String, error: String? = nil, code: String? = nil)

  /// Error thrown when an error happens during implicit grant flow.
  case implicitGrantRedirect(message: String)

  /// Error thrown when JWT verification fails.
  case jwtVerificationFailed(message: String)

  public var message: String {
    switch self {
    case .sessionMissing: "Auth session missing."
    case let .weakPassword(message, _),
      let .api(message, _, _, _),
      let .pkceGrantCodeExchange(message, _, _),
      let .implicitGrantRedirect(message),
      let .jwtVerificationFailed(message):
      message
    }
  }

  public var errorCode: ErrorCode {
    switch self {
    case .sessionMissing: .sessionNotFound
    case .weakPassword: .weakPassword
    case let .api(_, errorCode, _, _): errorCode
    case .pkceGrantCodeExchange, .implicitGrantRedirect: .unknown
    case .jwtVerificationFailed: .invalidJWT
    }
  }

  public var errorDescription: String? {
    message
  }

  public static func ~= (lhs: AuthError, rhs: any Error) -> Bool {
    guard let rhs = rhs as? AuthError else { return false }
    return lhs == rhs
  }
}
