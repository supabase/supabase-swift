import Foundation

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
  public static let Unknown = ErrorCode("unknown")

  /// ErrorCodeUnexpectedFailure signals an unexpected failure such as a 500 Internal Server Error.
  public static let UnexpectedFailure = ErrorCode("unexpected_failure")

  public static let ValidationFailed = ErrorCode("validation_failed")
  public static let BadJSON = ErrorCode("bad_json")
  public static let EmailExists = ErrorCode("email_exists")
  public static let PhoneExists = ErrorCode("phone_exists")
  public static let BadJWT = ErrorCode("bad_jwt")
  public static let NotAdmin = ErrorCode("not_admin")
  public static let NoAuthorization = ErrorCode("no_authorization")
  public static let UserNotFound = ErrorCode("user_not_found")
  public static let SessionNotFound = ErrorCode("session_not_found")
  public static let FlowStateNotFound = ErrorCode("flow_state_not_found")
  public static let FlowStateExpired = ErrorCode("flow_state_expired")
  public static let SignupDisabled = ErrorCode("signup_disabled")
  public static let UserBanned = ErrorCode("user_banned")
  public static let ProviderEmailNeedsVerification = ErrorCode("provider_email_needs_verification")
  public static let InviteNotFound = ErrorCode("invite_not_found")
  public static let BadOAuthState = ErrorCode("bad_oauth_state")
  public static let BadOAuthCallback = ErrorCode("bad_oauth_callback")
  public static let OAuthProviderNotSupported = ErrorCode("oauth_provider_not_supported")
  public static let UnexpectedAudience = ErrorCode("unexpected_audience")
  public static let SingleIdentityNotDeletable = ErrorCode("single_identity_not_deletable")
  public static let EmailConflictIdentityNotDeletable = ErrorCode("email_conflict_identity_not_deletable")
  public static let IdentityAlreadyExists = ErrorCode("identity_already_exists")
  public static let EmailProviderDisabled = ErrorCode("email_provider_disabled")
  public static let PhoneProviderDisabled = ErrorCode("phone_provider_disabled")
  public static let TooManyEnrolledMFAFactors = ErrorCode("too_many_enrolled_mfa_factors")
  public static let MFAFactorNameConflict = ErrorCode("mfa_factor_name_conflict")
  public static let MFAFactorNotFound = ErrorCode("mfa_factor_not_found")
  public static let MFAIPAddressMismatch = ErrorCode("mfa_ip_address_mismatch")
  public static let MFAChallengeExpired = ErrorCode("mfa_challenge_expired")
  public static let MFAVerificationFailed = ErrorCode("mfa_verification_failed")
  public static let MFAVerificationRejected = ErrorCode("mfa_verification_rejected")
  public static let InsufficientAAL = ErrorCode("insufficient_aal")
  public static let CaptchaFailed = ErrorCode("captcha_failed")
  public static let SAMLProviderDisabled = ErrorCode("saml_provider_disabled")
  public static let ManualLinkingDisabled = ErrorCode("manual_linking_disabled")
  public static let SMSSendFailed = ErrorCode("sms_send_failed")
  public static let EmailNotConfirmed = ErrorCode("email_not_confirmed")
  public static let PhoneNotConfirmed = ErrorCode("phone_not_confirmed")
  public static let SAMLRelayStateNotFound = ErrorCode("saml_relay_state_not_found")
  public static let SAMLRelayStateExpired = ErrorCode("saml_relay_state_expired")
  public static let SAMLIdPNotFound = ErrorCode("saml_idp_not_found")
  public static let SAMLAssertionNoUserID = ErrorCode("saml_assertion_no_user_id")
  public static let SAMLAssertionNoEmail = ErrorCode("saml_assertion_no_email")
  public static let UserAlreadyExists = ErrorCode("user_already_exists")
  public static let SSOProviderNotFound = ErrorCode("sso_provider_not_found")
  public static let SAMLMetadataFetchFailed = ErrorCode("saml_metadata_fetch_failed")
  public static let SAMLIdPAlreadyExists = ErrorCode("saml_idp_already_exists")
  public static let SSODomainAlreadyExists = ErrorCode("sso_domain_already_exists")
  public static let SAMLEntityIDMismatch = ErrorCode("saml_entity_id_mismatch")
  public static let Conflict = ErrorCode("conflict")
  public static let ProviderDisabled = ErrorCode("provider_disabled")
  public static let UserSSOManaged = ErrorCode("user_sso_managed")
  public static let ReauthenticationNeeded = ErrorCode("reauthentication_needed")
  public static let SamePassword = ErrorCode("same_password")
  public static let ReauthenticationNotValid = ErrorCode("reauthentication_not_valid")
  public static let OTPExpired = ErrorCode("otp_expired")
  public static let OTPDisabled = ErrorCode("otp_disabled")
  public static let IdentityNotFound = ErrorCode("identity_not_found")
  public static let WeakPassword = ErrorCode("weak_password")
  public static let OverRequestRateLimit = ErrorCode("over_request_rate_limit")
  public static let OverEmailSendRateLimit = ErrorCode("over_email_send_rate_limit")
  public static let OverSMSSendRateLimit = ErrorCode("over_sms_send_rate_limit")
  public static let odeVerifier = ErrorCode("bad_code_verifier")
  public static let AnonymousProviderDisabled = ErrorCode("anonymous_provider_disabled")
  public static let HookTimeout = ErrorCode("hook_timeout")
  public static let HookTimeoutAfterRetry = ErrorCode("hook_timeout_after_retry")
  public static let HookPayloadOverSizeLimit = ErrorCode("hook_payload_over_size_limit")
  public static let RequestTimeout = ErrorCode("request_timeout")
  public static let MFAPhoneEnrollDisabled = ErrorCode("mfa_phone_enroll_not_enabled")
  public static let MFAPhoneVerifyDisabled = ErrorCode("mfa_phone_verify_not_enabled")
  public static let MFATOTPEnrollDisabled = ErrorCode("mfa_totp_enroll_not_enabled")
  public static let MFATOTPVerifyDisabled = ErrorCode("mfa_totp_verify_not_enabled")
  public static let MFAVerifiedFactorExists = ErrorCode("mfa_verified_factor_exists")
  // #nosec G101 -- Not a secret value.
  public static let InvalidCredentials = ErrorCode("invalid_credentials")
}

/// Represents an error thrown by Auth, either by the client or the server.
public protocol SupabaseAuthError: LocalizedError {
  var message: String { get }
  var errorCode: ErrorCode { get }
}

public struct SupabaseAuthSessionMissingError: SupabaseAuthError {
  public let errorCode: ErrorCode = .SessionNotFound

  public let message: String = "Auth session missing."
}

/// Error thrown on certain methods when the password used is deemed weak.
/// Inspect the reasons to identify what password strength rules are inadequate.
public struct SupabaseAuthWeakPasswordError: SupabaseAuthError {
  public let errorCode: ErrorCode = .WeakPassword

  public let message: String
  public let reasons: [String]
}

public struct SupabaseAuthAPIError: SupabaseAuthError {
  public let message: String
  public let errorCode: ErrorCode

  /// The Data response for the underlysing request which caused this error to be thrown.
  public let underlyngData: Data

  /// The response for the underlysing request which caused this error to be thrown.
  public let underlyingResponse: HTTPURLResponse

  /// The HTTP status code for the response which caused this error to be thrown.
  public var status: Int { underlyingResponse.statusCode }
}

public struct SupabaseAuthPKCEGrantCodeExchangeError: SupabaseAuthError {
  public let errorCode: ErrorCode = .Unknown

  public let message: String
  public let error: String?
  public let code: String?
}

public struct SupabaseAuthImplicitGrantRedirectError: SupabaseAuthError {
  public let errorCode: ErrorCode = .Unknown
  public var message: String
}
