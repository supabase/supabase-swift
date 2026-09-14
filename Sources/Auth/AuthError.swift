import Foundation
public import Helpers

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

  /// One or more request fields failed server-side validation.
  public static let validationFailed = ErrorCode("validation_failed")
  /// The request body could not be parsed as JSON.
  public static let badJSON = ErrorCode("bad_json")
  /// The supplied email address is already associated with an account.
  public static let emailExists = ErrorCode("email_exists")
  /// The supplied phone number is already associated with an account.
  public static let phoneExists = ErrorCode("phone_exists")
  /// The supplied JWT is malformed or uses an unsupported algorithm.
  public static let badJWT = ErrorCode("bad_jwt")
  /// The operation requires admin privileges but the caller is not an admin.
  public static let notAdmin = ErrorCode("not_admin")
  /// The request does not contain a valid `Authorization` header.
  public static let noAuthorization = ErrorCode("no_authorization")
  /// No user exists with the given identifier.
  public static let userNotFound = ErrorCode("user_not_found")
  /// The session referenced by the token does not exist.
  public static let sessionNotFound = ErrorCode("session_not_found")
  /// The session has expired and must be refreshed.
  public static let sessionExpired = ErrorCode("session_expired")
  /// The provided refresh token does not exist.
  public static let refreshTokenNotFound = ErrorCode("refresh_token_not_found")
  /// The provided refresh token has already been used and cannot be reused.
  public static let refreshTokenAlreadyUsed = ErrorCode("refresh_token_already_used")
  /// The PKCE or magic-link flow state referenced was not found.
  public static let flowStateNotFound = ErrorCode("flow_state_not_found")
  /// The PKCE or magic-link flow state has expired.
  public static let flowStateExpired = ErrorCode("flow_state_expired")
  /// New user sign-ups are disabled for this project.
  public static let signupDisabled = ErrorCode("signup_disabled")
  /// The user account has been banned and cannot sign in.
  public static let userBanned = ErrorCode("user_banned")
  /// The OAuth provider returned an email address that must be verified before it can be used.
  public static let providerEmailNeedsVerification = ErrorCode(
    "provider_email_needs_verification")
  /// No invite was found for the supplied email/token combination.
  public static let inviteNotFound = ErrorCode("invite_not_found")
  /// The OAuth state parameter is invalid or has been tampered with.
  public static let badOAuthState = ErrorCode("bad_oauth_state")
  /// The OAuth provider returned an invalid or unexpected callback.
  public static let badOAuthCallback = ErrorCode("bad_oauth_callback")
  /// The requested OAuth provider is not supported or not enabled.
  public static let oauthProviderNotSupported = ErrorCode("oauth_provider_not_supported")
  /// The JWT audience (`aud`) claim does not match the expected audience.
  public static let unexpectedAudience = ErrorCode("unexpected_audience")
  /// The identity cannot be deleted because it is the only identity linked to the user.
  public static let singleIdentityNotDeletable = ErrorCode("single_identity_not_deletable")
  /// The identity cannot be deleted because doing so would create an email conflict.
  public static let emailConflictIdentityNotDeletable = ErrorCode(
    "email_conflict_identity_not_deletable")
  /// The identity is already linked to another user.
  public static let identityAlreadyExists = ErrorCode("identity_already_exists")
  /// The email provider is disabled for this project.
  public static let emailProviderDisabled = ErrorCode("email_provider_disabled")
  /// The phone provider is disabled for this project.
  public static let phoneProviderDisabled = ErrorCode("phone_provider_disabled")
  /// The user has already enrolled the maximum number of MFA factors.
  public static let tooManyEnrolledMFAFactors = ErrorCode("too_many_enrolled_mfa_factors")
  /// Another MFA factor with the same name already exists for this user.
  public static let mfaFactorNameConflict = ErrorCode("mfa_factor_name_conflict")
  /// No MFA factor was found with the given ID.
  public static let mfaFactorNotFound = ErrorCode("mfa_factor_not_found")
  /// The MFA challenge request originated from a different IP address than the sign-in request.
  public static let mfaIPAddressMismatch = ErrorCode("mfa_ip_address_mismatch")
  /// The MFA challenge has expired and a new one must be requested.
  public static let mfaChallengeExpired = ErrorCode("mfa_challenge_expired")
  /// The MFA verification code was incorrect.
  public static let mfaVerificationFailed = ErrorCode("mfa_verification_failed")
  /// The MFA verification was rejected by the server (e.g. too many attempts).
  public static let mfaVerificationRejected = ErrorCode("mfa_verification_rejected")
  /// The session does not meet the required Authenticator Assurance Level (AAL).
  public static let insufficientAAL = ErrorCode("insufficient_aal")
  /// The captcha verification token failed validation.
  public static let captchaFailed = ErrorCode("captcha_failed")
  /// The SAML provider is disabled for this project.
  public static let samlProviderDisabled = ErrorCode("saml_provider_disabled")
  /// Manual identity linking is disabled for this project.
  public static let manualLinkingDisabled = ErrorCode("manual_linking_disabled")
  /// The SMS provider failed to send the message.
  public static let smsSendFailed = ErrorCode("sms_send_failed")
  /// The user's email address has not been confirmed.
  public static let emailNotConfirmed = ErrorCode("email_not_confirmed")
  /// The user's phone number has not been confirmed.
  public static let phoneNotConfirmed = ErrorCode("phone_not_confirmed")
  /// The SAML relay state referenced was not found.
  public static let samlRelayStateNotFound = ErrorCode("saml_relay_state_not_found")
  /// The SAML relay state has expired.
  public static let samlRelayStateExpired = ErrorCode("saml_relay_state_expired")
  /// No SAML identity provider was found for the given domain or ID.
  public static let samlIdPNotFound = ErrorCode("saml_idp_not_found")
  /// The SAML assertion does not contain a user ID.
  public static let samlAssertionNoUserID = ErrorCode("saml_assertion_no_user_id")
  /// The SAML assertion does not contain an email address.
  public static let samlAssertionNoEmail = ErrorCode("saml_assertion_no_email")
  /// A user with the given attributes already exists.
  public static let userAlreadyExists = ErrorCode("user_already_exists")
  /// No SSO provider was found for the given domain or ID.
  public static let ssoProviderNotFound = ErrorCode("sso_provider_not_found")
  /// Failed to fetch SAML metadata from the identity provider.
  public static let samlMetadataFetchFailed = ErrorCode("saml_metadata_fetch_failed")
  /// A SAML identity provider with the same entity ID already exists.
  public static let samlIdPAlreadyExists = ErrorCode("saml_idp_already_exists")
  /// An SSO domain with the same name is already registered.
  public static let ssoDomainAlreadyExists = ErrorCode("sso_domain_already_exists")
  /// The SAML entity ID in the metadata does not match what was expected.
  public static let samlEntityIDMismatch = ErrorCode("saml_entity_id_mismatch")
  /// A conflicting resource already exists (generic conflict).
  public static let conflict = ErrorCode("conflict")
  /// The requested provider is disabled for this project.
  public static let providerDisabled = ErrorCode("provider_disabled")
  /// The user is managed by an SSO provider and cannot be modified directly.
  public static let userSSOManaged = ErrorCode("user_sso_managed")
  /// Reauthentication is required before performing this action.
  public static let reauthenticationNeeded = ErrorCode("reauthentication_needed")
  /// The new password is the same as the current password.
  public static let samePassword = ErrorCode("same_password")
  /// The reauthentication nonce has expired or is invalid.
  public static let reauthenticationNotValid = ErrorCode("reauthentication_not_valid")
  /// The OTP has expired and a new one must be requested.
  public static let otpExpired = ErrorCode("otp_expired")
  /// OTP sign-in is disabled for this project.
  public static let otpDisabled = ErrorCode("otp_disabled")
  /// The identity referenced was not found.
  public static let identityNotFound = ErrorCode("identity_not_found")
  /// The password does not meet the project's strength requirements.
  public static let weakPassword = ErrorCode("weak_password")
  /// The caller has exceeded the global request rate limit.
  public static let overRequestRateLimit = ErrorCode("over_request_rate_limit")
  /// The caller has exceeded the email-send rate limit.
  public static let overEmailSendRateLimit = ErrorCode("over_email_send_rate_limit")
  /// The caller has exceeded the SMS-send rate limit.
  public static let overSMSSendRateLimit = ErrorCode("over_sms_send_rate_limit")
  /// The PKCE code verifier does not match the stored code challenge.
  public static let badCodeVerifier = ErrorCode("bad_code_verifier")
  /// Anonymous sign-in is disabled for this project.
  public static let anonymousProviderDisabled = ErrorCode("anonymous_provider_disabled")
  /// A server-side hook timed out.
  public static let hookTimeout = ErrorCode("hook_timeout")
  /// A server-side hook timed out on all retry attempts.
  public static let hookTimeoutAfterRetry = ErrorCode("hook_timeout_after_retry")
  /// The hook payload exceeds the size limit.
  public static let hookPayloadOverSizeLimit = ErrorCode("hook_payload_over_size_limit")
  /// The hook payload has an invalid `Content-Type`.
  public static let hookPayloadInvalidContentType = ErrorCode(
    "hook_payload_invalid_content_type")
  /// The upstream request timed out.
  public static let requestTimeout = ErrorCode("request_timeout")
  /// Phone factor enrollment is not enabled for this project.
  public static let mfaPhoneEnrollDisabled = ErrorCode("mfa_phone_enroll_not_enabled")
  /// Phone factor verification is not enabled for this project.
  public static let mfaPhoneVerifyDisabled = ErrorCode("mfa_phone_verify_not_enabled")
  /// TOTP factor enrollment is not enabled for this project.
  public static let mfaTOTPEnrollDisabled = ErrorCode("mfa_totp_enroll_not_enabled")
  /// TOTP factor verification is not enabled for this project.
  public static let mfaTOTPVerifyDisabled = ErrorCode("mfa_totp_verify_not_enabled")
  /// WebAuthn factor enrollment is not enabled for this project.
  public static let mfaWebAuthnEnrollDisabled = ErrorCode(
    "mfa_webauthn_enroll_not_enabled")
  /// WebAuthn factor verification is not enabled for this project.
  public static let mfaWebAuthnVerifyDisabled = ErrorCode(
    "mfa_webauthn_verify_not_enabled")
  @_spi(Experimental) public static let webAuthnChallengeNotFound = ErrorCode(
    "webauthn_challenge_not_found")
  @_spi(Experimental) public static let webAuthnChallengeExpired = ErrorCode(
    "webauthn_challenge_expired")
  @_spi(Experimental) public static let webAuthnVerificationFailed = ErrorCode(
    "webauthn_verification_failed")
  @_spi(Experimental) public static let webAuthnCredentialExists = ErrorCode(
    "webauthn_credential_exists")
  @_spi(Experimental) public static let tooManyPasskeys = ErrorCode("too_many_passkeys")
  /// The user already has a verified MFA factor; unenroll it before enrolling a new one.
  public static let mfaVerifiedFactorExists = ErrorCode("mfa_verified_factor_exists")
  //#nosec G101 -- Not a secret value.
  /// The provided credentials (email/password or phone/password) are incorrect.
  public static let invalidCredentials = ErrorCode("invalid_credentials")
  /// The email address is not on the allow-list for this project.
  public static let emailAddressNotAuthorized = ErrorCode("email_address_not_authorized")
  /// The Web3 provider for the requested chain is disabled for this project.
  public static let web3ProviderDisabled = ErrorCode("web3_provider_disabled")
  /// The requested Web3 chain is not supported.
  public static let web3UnsupportedChain = ErrorCode("web3_unsupported_chain")
  /// The provided JWT is invalid (malformed, bad signature, or expired).
  public static let invalidJWT = ErrorCode("invalid_jwt")
  /// No pending OAuth authorization request exists with the given ID, it has expired, or it belongs to a different user.
  public static let oauthAuthorizationNotFound = ErrorCode("oauth_authorization_not_found")
  /// No active OAuth consent/grant exists for the given client.
  public static let oauthConsentNotFound = ErrorCode("oauth_consent_not_found")
  /// The OAuth 2.1 authorization server feature is disabled for this project.
  public static let featureDisabled = ErrorCode("feature_disabled")
}

/// An error thrown by ``AuthClient`` and related Auth types.
///
/// Check ``kind`` to learn what failed, and ``errorCode`` for the GoTrue error code when the
/// server rejected the request. ``response`` carries the status, headers, body and request id
/// for ``Kind-swift.struct/api`` and ``Kind-swift.struct/unexpectedResponse``.
///
/// ```swift
/// do {
///   try await supabase.auth.signIn(email: email, password: password)
/// } catch let error as AuthError where error.errorCode == .invalidCredentials {
///   showWrongPassword()
/// } catch let error as AuthError where error.kind == .weakPassword {
///   showReasons(error.weakPasswordReasons)
/// }
/// ```
///
/// ## Topics
///
/// ### Inspecting an error
/// - ``kind``
/// - ``errorCode``
/// - ``message``
/// - ``weakPasswordReasons``
/// - ``response``
/// - ``underlyingError``
///
/// ### Common values
/// - ``sessionMissing``
/// - ``Kind-swift.struct``
public struct AuthError: SupabaseError {
  /// What failed. Compare against the static members and keep a fallback branch.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// GoTrue rejected the request. ``AuthError/errorCode`` says why and
    /// ``AuthError/response`` has the body.
    public static let api: Kind = "api"
    /// A session is required but none is stored, or the server reported the session as gone.
    public static let sessionMissing: Kind = "sessionMissing"
    /// The password does not meet the project's strength rules. See
    /// ``AuthError/weakPasswordReasons``.
    public static let weakPassword: Kind = "weakPassword"
    /// The PKCE redirect URL carried an error, or the code exchange failed.
    public static let pkceGrantCodeExchange: Kind = "pkceGrantCodeExchange"
    /// The implicit-flow redirect URL carried an error or no session.
    public static let implicitGrantRedirect: Kind = "implicitGrantRedirect"
    /// An OAuth flow could not start or finish on the client, before any request reached the
    /// server. Most often no redirect URL with a scheme is configured.
    public static let oauthFlowFailed: Kind = "oauthFlowFailed"
    /// Local JWT verification failed (malformed, expired or bad signature).
    public static let jwtVerificationFailed: Kind = "jwtVerificationFailed"
    /// A WebAuthn ceremony could not be driven: a required field was missing or malformed, or
    /// the authenticator returned an unexpected credential type.
    public static let webAuthn: Kind = "webAuthn"
    /// A non-2xx status whose body was not a GoTrue error payload. ``AuthError/response`` has the
    /// raw body.
    public static let unexpectedResponse: Kind = "unexpectedResponse"
    /// The request never completed. ``AuthError/underlyingError`` is usually a `URLError`.
    public static let transport: Kind = "transport"
    /// A success body could not be decoded. ``AuthError/underlyingError`` is usually a
    /// `DecodingError`.
    public static let decoding: Kind = "decoding"
  }

  public var kind: Kind
  public var message: String
  /// The GoTrue error code. `.unknown` when the failure did not come from the server.
  public var errorCode: ErrorCode
  /// Why the password was rejected. Empty unless ``kind`` is ``Kind-swift.struct/weakPassword``.
  public var weakPasswordReasons: [String]
  public var response: HTTPErrorResponse?
  public var underlyingError: (any Error)?

  public init(
    kind: Kind,
    message: String,
    errorCode: ErrorCode = .unknown,
    weakPasswordReasons: [String] = [],
    response: HTTPErrorResponse? = nil,
    underlyingError: (any Error)? = nil
  ) {
    self.kind = kind
    self.message = message
    self.errorCode = errorCode
    self.weakPasswordReasons = weakPasswordReasons
    self.response = response
    self.underlyingError = underlyingError
  }

  public var description: String {
    formattedDescription(kind: kind.rawValue)
  }

  /// Thrown when a session is required to proceed but none was found, either locally or as
  /// reported by the server.
  public static let sessionMissing = AuthError(
    kind: .sessionMissing, message: "Auth session missing.", errorCode: .sessionNotFound)
}

extension AuthError {
  static func weakPassword(message: String, reasons: [String]) -> AuthError {
    AuthError(
      kind: .weakPassword, message: message, errorCode: .weakPassword,
      weakPasswordReasons: reasons)
  }

  static func implicitGrantRedirect(_ message: String) -> AuthError {
    AuthError(kind: .implicitGrantRedirect, message: message)
  }

  static func oauthFlowFailed(_ message: String) -> AuthError {
    AuthError(kind: .oauthFlowFailed, message: message)
  }

  static func pkceGrantCodeExchange(_ message: String, errorCode: ErrorCode = .unknown)
    -> AuthError
  {
    AuthError(kind: .pkceGrantCodeExchange, message: message, errorCode: errorCode)
  }

  static func jwtVerificationFailed(_ message: String) -> AuthError {
    AuthError(kind: .jwtVerificationFailed, message: message, errorCode: .invalidJWT)
  }

  static func webAuthn(_ message: String) -> AuthError {
    AuthError(kind: .webAuthn, message: message)
  }
}
