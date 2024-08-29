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

public enum AuthError: LocalizedError {
  @available(
    *,
    deprecated,
    message: "Error used to be thrown when no exp claim was found in JWT during setSession(accessToken:refreshToken:) method."
  )
  case missingExpClaim

  @available(
    *,
    deprecated,
    message: "Error used to be thrown when provided JWT wasn't valid during setSession(accessToken:refreshToken:) method."
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
    message: "This error is never thrown, if you depend on it, you can remove the logic as it never happens."
  )
  case missingURL

  @available(
    *,
    deprecated,
    message: "Error used to be thrown on methods which required a valid redirect scheme, such as signInWithOAuth. This is now considered a programming error an a assertion is triggered in case redirect scheme isn't provided."
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
      errorCode: .Unknown,
      underlyingData: (try? AuthClient.Configuration.jsonEncoder.encode(error)) ?? Data(),
      underlyingResponse: HTTPURLResponse(
        url: URL(string: "http://localhost")!,
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

  case sessionMissing
  case weakPassword(message: String, reasons: [String])
  case api(
    message: String,
    errorCode: ErrorCode,
    underlyingData: Data,
    underlyingResponse: HTTPURLResponse
  )
  case pkceGrantCodeExchange(message: String, error: String? = nil, code: String? = nil)
  case implicitGrantRedirect(message: String)

  public var message: String {
    switch self {
    case .sessionMissing: "Auth session missing."
    case let .weakPassword(message, _),
         let .api(message, _, _, _),
         let .pkceGrantCodeExchange(message, _, _),
         let .implicitGrantRedirect(message):
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
    case .sessionMissing: .SessionNotFound
    case .weakPassword: .WeakPassword
    case let .api(_, errorCode, _, _): errorCode
    case .pkceGrantCodeExchange, .implicitGrantRedirect: .Unknown
    // Deprecated cases
    case .missingExpClaim, .malformedJWT, .invalidRedirectScheme, .missingURL: .Unknown
    }
  }

  public var errorDescription: String? {
    if errorCode == .Unknown {
      message
    } else {
      "\(errorCode.rawValue): \(message)"
    }
  }
}
