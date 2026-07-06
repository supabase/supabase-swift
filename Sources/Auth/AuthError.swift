public import Foundation

#if canImport(FoundationNetworking)
  public import FoundationNetworking
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
  /// The provided JWT is invalid (malformed, bad signature, or expired).
  public static let invalidJWT = ErrorCode("invalid_jwt")
}

/// Errors that can be thrown by ``AuthClient`` and related Auth types.
///
/// ## Topics
///
/// ### Common errors
/// - ``sessionMissing``
/// - ``weakPassword(message:reasons:)``
/// - ``api(message:errorCode:underlyingData:underlyingResponse:)``
///
/// ### OAuth flow errors
/// - ``pkceGrantCodeExchange(message:error:code:)``
/// - ``implicitGrantRedirect(message:)``
///
/// ### JWT errors
/// - ``jwtVerificationFailed(message:)``
public enum AuthError: LocalizedError, Equatable {
  @available(
    *,
    deprecated,
    message:
      "Error used to be thrown when no exp claim was found in JWT during setSession(accessToken:refreshToken:) method."
  )
  case missingExpClaim

  @available(
    *,
    deprecated,
    message:
      "Error used to be thrown when provided JWT wasn't valid during setSession(accessToken:refreshToken:) method."
  )
  case malformedJWT

  @available(*, deprecated, renamed: "sessionMissing")
  public static var sessionNotFound: AuthError { .sessionMissing }

  /// Error thrown during PKCE flow.
  @available(
    *,
    deprecated,
    renamed: "pkceGrantCodeExchange",
    message: "Error was grouped in `pkceGrantCodeExchange`, please use it instead of `pkce`."
  )
  public static func pkce(_ reason: PKCEFailureReason) -> AuthError {
    switch reason {
    case .codeVerifierNotFound:
      .pkceGrantCodeExchange(message: "A code verifier wasn't found in PKCE flow.")
    case .invalidPKCEFlowURL:
      .pkceGrantCodeExchange(message: "Not a valid PKCE flow url.")
    }
  }

  @available(*, deprecated, message: "Use `pkceGrantCodeExchange` instead.")
  public enum PKCEFailureReason: Sendable {
    /// Code verifier not found in the URL.
    case codeVerifierNotFound

    /// Not a valid PKCE flow URL.
    case invalidPKCEFlowURL
  }

  @available(*, deprecated, renamed: "implicitGrantRedirect")
  public static var invalidImplicitGrantFlowURL: AuthError {
    .implicitGrantRedirect(message: "Not a valid implicit grant flow url.")
  }

  @available(
    *,
    deprecated,
    message:
      "This error is never thrown, if you depend on it, you can remove the logic as it never happens."
  )
  case missingURL

  @available(
    *,
    deprecated,
    message:
      "Error used to be thrown on methods which required a valid redirect scheme, such as signInWithOAuth. This is now considered a programming error an a assertion is triggered in case redirect scheme isn't provided."
  )
  case invalidRedirectScheme

  @available(
    *,
    deprecated,
    renamed: "api(message:errorCode:underlyingData:underlyingResponse:)"
  )
  public static func api(_ error: APIError) -> AuthError {
    let message = error.msg ?? error.error ?? error.errorDescription ?? "Unexpected API error."
    if let weakPassword = error.weakPassword {
      return .weakPassword(message: message, reasons: weakPassword.reasons)
    }

    return .api(
      message: message,
      errorCode: .unknown,
      underlyingData: (try? AuthClient.Configuration.jsonEncoder.encode(error)) ?? Data(),
      underlyingResponse: HTTPURLResponse(
        url: defaultAuthURL,
        statusCode: error.code ?? 500,
        httpVersion: nil,
        headerFields: nil
      )!
    )
  }

  /// An error returned by the API.
  @available(
    *,
    deprecated,
    renamed: "api(message:errorCode:underlyingData:underlyingResponse:)"
  )
  public struct APIError: Error, Codable, Sendable, Equatable {
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
    case .weakPassword(let message, _),
      .api(let message, _, _, _),
      .pkceGrantCodeExchange(let message, _, _),
      .implicitGrantRedirect(let message),
      .jwtVerificationFailed(let message):
      message
    // Deprecated cases
    case .missingExpClaim: "Missing expiration claim in the access token."
    case .malformedJWT: "A malformed JWT received."
    case .invalidRedirectScheme: "Invalid redirect scheme."
    case .missingURL: "Missing URL."
    }
  }

  public var errorCode: ErrorCode {
    switch self {
    case .sessionMissing: .sessionNotFound
    case .weakPassword: .weakPassword
    case .api(_, let errorCode, _, _): errorCode
    case .pkceGrantCodeExchange, .implicitGrantRedirect: .unknown
    case .jwtVerificationFailed: .invalidJWT
    // Deprecated cases
    case .missingExpClaim, .malformedJWT, .invalidRedirectScheme, .missingURL: .unknown
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
