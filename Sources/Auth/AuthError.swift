public import Foundation

#if canImport(FoundationNetworking)
  public import FoundationNetworking
#endif

/// An error code GoTrue sends in the body of a rejected request, such as
/// ``invalidCredentials``.
///
/// Compare against the static members and keep a fallback branch: GoTrue adds codes, and a
/// server newer than the SDK can send one this version does not know.
///
/// The next major version names this type `AuthError.Code`. ``AuthError/Code`` is that name.
public struct ErrorCode: Decodable, RawRepresentable, Sendable, Hashable,
  ExpressibleByStringLiteral
{
  /// The code as GoTrue sends it, such as `"invalid_credentials"`.
  public var rawValue: String

  /// Creates a code from the value GoTrue sends.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a code from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  @available(*, deprecated, message: "Use init(rawValue:) or a string literal instead.")
  public init(_ rawValue: String) {
    self.init(rawValue: rawValue)
  }
}

extension AuthError {
  /// An error code GoTrue sends in the body of a rejected request. The name that the next major
  /// version uses for ``ErrorCode``.
  public typealias Code = ErrorCode
}

// Known error codes. Note that the server may also return other error codes
// not included in this list (if the client library is older than the version
// on the server).
extension AuthError.Code {
  /// ErrorCodeUnknown should not be used directly, it only indicates a failure in the error handling system in such a way that an error code was not assigned properly.
  public static let unknown: AuthError.Code = "unknown"

  /// ErrorCodeUnexpectedFailure signals an unexpected failure such as a 500 Internal Server Error.
  public static let unexpectedFailure: AuthError.Code = "unexpected_failure"

  /// One or more request fields failed server-side validation.
  public static let validationFailed: AuthError.Code = "validation_failed"
  /// The request body could not be parsed as JSON.
  public static let badJSON: AuthError.Code = "bad_json"
  /// The supplied email address is already associated with an account.
  public static let emailExists: AuthError.Code = "email_exists"
  /// The supplied phone number is already associated with an account.
  public static let phoneExists: AuthError.Code = "phone_exists"
  /// The supplied JWT is malformed or uses an unsupported algorithm.
  public static let badJWT: AuthError.Code = "bad_jwt"
  /// The operation requires admin privileges but the caller is not an admin.
  public static let notAdmin: AuthError.Code = "not_admin"
  /// The request does not contain a valid `Authorization` header.
  public static let noAuthorization: AuthError.Code = "no_authorization"
  /// No user exists with the given identifier.
  public static let userNotFound: AuthError.Code = "user_not_found"
  /// The session referenced by the token does not exist.
  public static let sessionNotFound: AuthError.Code = "session_not_found"
  /// The session has expired and must be refreshed.
  public static let sessionExpired: AuthError.Code = "session_expired"
  /// The provided refresh token does not exist.
  public static let refreshTokenNotFound: AuthError.Code = "refresh_token_not_found"
  /// The provided refresh token has already been used and cannot be reused.
  public static let refreshTokenAlreadyUsed: AuthError.Code = "refresh_token_already_used"
  /// The PKCE or magic-link flow state referenced was not found.
  public static let flowStateNotFound: AuthError.Code = "flow_state_not_found"
  /// The PKCE or magic-link flow state has expired.
  public static let flowStateExpired: AuthError.Code = "flow_state_expired"
  /// New user sign-ups are disabled for this project.
  public static let signupDisabled: AuthError.Code = "signup_disabled"
  /// The user account has been banned and cannot sign in.
  public static let userBanned: AuthError.Code = "user_banned"
  /// The OAuth provider returned an email address that must be verified before it can be used.
  public static let providerEmailNeedsVerification: AuthError.Code =
    "provider_email_needs_verification"
  /// No invite was found for the supplied email/token combination.
  public static let inviteNotFound: AuthError.Code = "invite_not_found"
  /// The OAuth state parameter is invalid or has been tampered with.
  public static let badOAuthState: AuthError.Code = "bad_oauth_state"
  /// The OAuth provider returned an invalid or unexpected callback.
  public static let badOAuthCallback: AuthError.Code = "bad_oauth_callback"
  /// The requested OAuth provider is not supported or not enabled.
  public static let oauthProviderNotSupported: AuthError.Code = "oauth_provider_not_supported"
  /// The JWT audience (`aud`) claim does not match the expected audience.
  public static let unexpectedAudience: AuthError.Code = "unexpected_audience"
  /// The identity cannot be deleted because it is the only identity linked to the user.
  public static let singleIdentityNotDeletable: AuthError.Code = "single_identity_not_deletable"
  /// The identity cannot be deleted because doing so would create an email conflict.
  public static let emailConflictIdentityNotDeletable: AuthError.Code =
    "email_conflict_identity_not_deletable"
  /// The identity is already linked to another user.
  public static let identityAlreadyExists: AuthError.Code = "identity_already_exists"
  /// The email provider is disabled for this project.
  public static let emailProviderDisabled: AuthError.Code = "email_provider_disabled"
  /// The phone provider is disabled for this project.
  public static let phoneProviderDisabled: AuthError.Code = "phone_provider_disabled"
  /// The user has already enrolled the maximum number of MFA factors.
  public static let tooManyEnrolledMFAFactors: AuthError.Code = "too_many_enrolled_mfa_factors"
  /// Another MFA factor with the same name already exists for this user.
  public static let mfaFactorNameConflict: AuthError.Code = "mfa_factor_name_conflict"
  /// No MFA factor was found with the given ID.
  public static let mfaFactorNotFound: AuthError.Code = "mfa_factor_not_found"
  /// The MFA challenge request originated from a different IP address than the sign-in request.
  public static let mfaIPAddressMismatch: AuthError.Code = "mfa_ip_address_mismatch"
  /// The MFA challenge has expired and a new one must be requested.
  public static let mfaChallengeExpired: AuthError.Code = "mfa_challenge_expired"
  /// The MFA verification code was incorrect.
  public static let mfaVerificationFailed: AuthError.Code = "mfa_verification_failed"
  /// The MFA verification was rejected by the server (e.g. too many attempts).
  public static let mfaVerificationRejected: AuthError.Code = "mfa_verification_rejected"
  /// The session does not meet the required Authenticator Assurance Level (AAL).
  public static let insufficientAAL: AuthError.Code = "insufficient_aal"
  /// The captcha verification token failed validation.
  public static let captchaFailed: AuthError.Code = "captcha_failed"
  /// The SAML provider is disabled for this project.
  public static let samlProviderDisabled: AuthError.Code = "saml_provider_disabled"
  /// Manual identity linking is disabled for this project.
  public static let manualLinkingDisabled: AuthError.Code = "manual_linking_disabled"
  /// The SMS provider failed to send the message.
  public static let smsSendFailed: AuthError.Code = "sms_send_failed"
  /// The user's email address has not been confirmed.
  public static let emailNotConfirmed: AuthError.Code = "email_not_confirmed"
  /// The user's phone number has not been confirmed.
  public static let phoneNotConfirmed: AuthError.Code = "phone_not_confirmed"
  /// The SAML relay state referenced was not found.
  public static let samlRelayStateNotFound: AuthError.Code = "saml_relay_state_not_found"
  /// The SAML relay state has expired.
  public static let samlRelayStateExpired: AuthError.Code = "saml_relay_state_expired"
  /// No SAML identity provider was found for the given domain or ID.
  public static let samlIdPNotFound: AuthError.Code = "saml_idp_not_found"
  /// The SAML assertion does not contain a user ID.
  public static let samlAssertionNoUserID: AuthError.Code = "saml_assertion_no_user_id"
  /// The SAML assertion does not contain an email address.
  public static let samlAssertionNoEmail: AuthError.Code = "saml_assertion_no_email"
  /// A user with the given attributes already exists.
  public static let userAlreadyExists: AuthError.Code = "user_already_exists"
  /// No SSO provider was found for the given domain or ID.
  public static let ssoProviderNotFound: AuthError.Code = "sso_provider_not_found"
  /// Failed to fetch SAML metadata from the identity provider.
  public static let samlMetadataFetchFailed: AuthError.Code = "saml_metadata_fetch_failed"
  /// A SAML identity provider with the same entity ID already exists.
  public static let samlIdPAlreadyExists: AuthError.Code = "saml_idp_already_exists"
  /// An SSO domain with the same name is already registered.
  public static let ssoDomainAlreadyExists: AuthError.Code = "sso_domain_already_exists"
  /// The SAML entity ID in the metadata does not match what was expected.
  public static let samlEntityIDMismatch: AuthError.Code = "saml_entity_id_mismatch"
  /// A conflicting resource already exists (generic conflict).
  public static let conflict: AuthError.Code = "conflict"
  /// The requested provider is disabled for this project.
  public static let providerDisabled: AuthError.Code = "provider_disabled"
  /// The user is managed by an SSO provider and cannot be modified directly.
  public static let userSSOManaged: AuthError.Code = "user_sso_managed"
  /// Reauthentication is required before performing this action.
  public static let reauthenticationNeeded: AuthError.Code = "reauthentication_needed"
  /// The new password is the same as the current password.
  public static let samePassword: AuthError.Code = "same_password"
  /// The reauthentication nonce has expired or is invalid.
  public static let reauthenticationNotValid: AuthError.Code = "reauthentication_not_valid"
  /// The OTP has expired and a new one must be requested.
  public static let otpExpired: AuthError.Code = "otp_expired"
  /// OTP sign-in is disabled for this project.
  public static let otpDisabled: AuthError.Code = "otp_disabled"
  /// The identity referenced was not found.
  public static let identityNotFound: AuthError.Code = "identity_not_found"
  /// The password does not meet the project's strength requirements.
  public static let weakPassword: AuthError.Code = "weak_password"
  /// The caller has exceeded the global request rate limit.
  public static let overRequestRateLimit: AuthError.Code = "over_request_rate_limit"
  /// The caller has exceeded the email-send rate limit.
  public static let overEmailSendRateLimit: AuthError.Code = "over_email_send_rate_limit"
  /// The caller has exceeded the SMS-send rate limit.
  public static let overSMSSendRateLimit: AuthError.Code = "over_sms_send_rate_limit"
  /// The PKCE code verifier does not match the stored code challenge.
  public static let badCodeVerifier: AuthError.Code = "bad_code_verifier"
  /// Anonymous sign-in is disabled for this project.
  public static let anonymousProviderDisabled: AuthError.Code = "anonymous_provider_disabled"
  /// A server-side hook timed out.
  public static let hookTimeout: AuthError.Code = "hook_timeout"
  /// A server-side hook timed out on all retry attempts.
  public static let hookTimeoutAfterRetry: AuthError.Code = "hook_timeout_after_retry"
  /// The hook payload exceeds the size limit.
  public static let hookPayloadOverSizeLimit: AuthError.Code = "hook_payload_over_size_limit"
  /// The hook payload has an invalid `Content-Type`.
  public static let hookPayloadInvalidContentType: AuthError.Code =
    "hook_payload_invalid_content_type"
  /// The upstream request timed out.
  public static let requestTimeout: AuthError.Code = "request_timeout"
  /// Phone factor enrollment is not enabled for this project.
  public static let mfaPhoneEnrollDisabled: AuthError.Code = "mfa_phone_enroll_not_enabled"
  /// Phone factor verification is not enabled for this project.
  public static let mfaPhoneVerifyDisabled: AuthError.Code = "mfa_phone_verify_not_enabled"
  /// TOTP factor enrollment is not enabled for this project.
  public static let mfaTOTPEnrollDisabled: AuthError.Code = "mfa_totp_enroll_not_enabled"
  /// TOTP factor verification is not enabled for this project.
  public static let mfaTOTPVerifyDisabled: AuthError.Code = "mfa_totp_verify_not_enabled"
  /// WebAuthn factor enrollment is not enabled for this project.
  public static let mfaWebAuthnEnrollDisabled: AuthError.Code = "mfa_webauthn_enroll_not_enabled"
  /// WebAuthn factor verification is not enabled for this project.
  public static let mfaWebAuthnVerifyDisabled: AuthError.Code = "mfa_webauthn_verify_not_enabled"
  @_spi(Experimental) public static let webAuthnChallengeNotFound: AuthError.Code =
    "webauthn_challenge_not_found"
  @_spi(Experimental) public static let webAuthnChallengeExpired: AuthError.Code =
    "webauthn_challenge_expired"
  @_spi(Experimental) public static let webAuthnVerificationFailed: AuthError.Code =
    "webauthn_verification_failed"
  @_spi(Experimental) public static let webAuthnCredentialExists: AuthError.Code =
    "webauthn_credential_exists"
  @_spi(Experimental) public static let tooManyPasskeys: AuthError.Code = "too_many_passkeys"
  /// The user already has a verified MFA factor; unenroll it before enrolling a new one.
  public static let mfaVerifiedFactorExists: AuthError.Code = "mfa_verified_factor_exists"
  //#nosec G101 -- Not a secret value.
  /// The provided credentials (email/password or phone/password) are incorrect.
  public static let invalidCredentials: AuthError.Code = "invalid_credentials"
  /// The email address is not on the allow-list for this project.
  public static let emailAddressNotAuthorized: AuthError.Code = "email_address_not_authorized"
  /// The Web3 provider for the requested chain is disabled for this project.
  public static let web3ProviderDisabled: AuthError.Code = "web3_provider_disabled"
  /// The requested Web3 chain is not supported.
  public static let web3UnsupportedChain: AuthError.Code = "web3_unsupported_chain"
  /// The provided JWT is invalid (malformed, bad signature, or expired).
  public static let invalidJWT: AuthError.Code = "invalid_jwt"
  /// No pending OAuth authorization request exists with the given ID, it has expired, or it belongs to a different user.
  public static let oauthAuthorizationNotFound: AuthError.Code = "oauth_authorization_not_found"
  /// No active OAuth consent/grant exists for the given client.
  public static let oauthConsentNotFound: AuthError.Code = "oauth_consent_not_found"
  /// The OAuth 2.1 authorization server feature is disabled for this project.
  public static let featureDisabled: AuthError.Code = "feature_disabled"
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
///
/// ### Inspecting an error
/// - ``kind``
/// - ``code``
/// - ``message``
/// - ``weakPasswordReasons``
/// - ``Kind-swift.struct``
/// - ``Code``
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

  /// Error thrown when a token refresh finished after the session it started from was signed out
  /// or replaced, so its result was dropped instead of applied to the stored session. Distinct
  /// from ``sessionMissing``: a session may well be stored, just not the one that refresh
  /// belonged to.
  case refreshDiscarded

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
    case .refreshDiscarded:
      "Token refresh discarded: the session it started from is no longer stored."
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

  @available(*, deprecated, message: "Use code instead.")
  public var errorCode: ErrorCode {
    switch self {
    case .sessionMissing: .sessionNotFound
    case .refreshDiscarded: .unknown
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

  /// What failed. Compare against the static members and keep a fallback branch.
  ///
  /// This is the error model of the next major version, reported for the cases of this enum.
  /// ``kind`` reports only ``server``, ``sessionMissing``, ``sessionInvalidated``,
  /// ``oauthFlowFailed``, ``jwtVerificationFailed``, ``invalidRequest``, and ``refreshDiscarded``
  /// in this version. The other members exist so that code written against them compiles now.
  public struct Kind: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }

    /// GoTrue answered with a non-2xx status. Branch on ``AuthError/code`` for why. For
    /// ``ErrorCode/weakPassword``, show ``AuthError/weakPasswordReasons``.
    public static let server: Kind = "server"
    /// A session is required but none is stored locally. Sign the user in.
    ///
    /// In this version the client also throws ``AuthError/sessionMissing`` when the server
    /// rejects the current session and the client removes it from storage.
    public static let sessionMissing: Kind = "sessionMissing"
    /// The server rejected the session or its refresh token: it expired, was revoked, was
    /// already used, or the user is banned. ``AuthError/code`` and ``AuthError/message`` keep
    /// the server's values.
    public static let sessionInvalidated: Kind = "sessionInvalidated"
    /// The claims of an ID token do not match the sign-in request, for example a nonce,
    /// audience, or issuer mismatch. Not reported in this version.
    public static let idTokenMismatch: Kind = "idTokenMismatch"
    /// Session storage cannot be read or written right now. Not reported in this version:
    /// storage errors are thrown as they are.
    public static let storageUnavailable: Kind = "storageUnavailable"
    /// Session storage is set up wrong, for example a missing Keychain entitlement. Not reported
    /// in this version: storage errors are thrown as they are.
    public static let storageMisconfigured: Kind = "storageMisconfigured"
    /// The client refreshed the session too many times in a short window and stopped. Not
    /// reported in this version.
    public static let excessiveRefresh: Kind = "excessiveRefresh"
    /// The session is expired and the client was told not to refresh it. Not reported in this
    /// version.
    public static let refreshDisabled: Kind = "refreshDisabled"
    /// A redirect-based sign-in (OAuth, magic link, PKCE or implicit flow) could not start or
    /// finish. Either the redirect URL carried an error or no session, or the server rejected the
    /// flow state or code verifier (``ErrorCode/flowStateNotFound``,
    /// ``ErrorCode/flowStateExpired``,
    /// ``ErrorCode/badCodeVerifier``). Start the sign-in again;
    /// ``AuthError/code`` carries the URL's or the server's error code when there was one.
    public static let oauthFlowFailed: Kind = "oauthFlowFailed"
    /// Local JWT verification failed: malformed, expired or bad signature. Discard the token and
    /// refresh the session or sign in again.
    public static let jwtVerificationFailed: Kind = "jwtVerificationFailed"
    /// No response arrived. Not reported in this version: a `URLError` is thrown as it is.
    public static let transport: Kind = "transport"
    /// A payload could not be interpreted. Not reported in this version: a `DecodingError` is
    /// thrown as it is.
    public static let decoding: Kind = "decoding"
    /// The client configuration was refused. Not reported in this version.
    public static let invalidConfiguration: Kind = "invalidConfiguration"
    /// The SDK refused to send the request, for example because a URL could not be built.
    public static let invalidRequest: Kind = "invalidRequest"
    /// A token refresh finished after the session it started from was signed out or replaced, so
    /// its rotated tokens were dropped rather than applied to whichever session is stored now.
    /// Ignore the result; the stored session is unchanged. Distinct from ``sessionMissing``: a
    /// session may well be stored, just not the one that refresh belonged to.
    public static let refreshDiscarded: Kind = "refreshDiscarded"

    static let kindsByCode: [AuthError.Code: Kind] = [
      .refreshTokenNotFound: .sessionInvalidated,
      .refreshTokenAlreadyUsed: .sessionInvalidated,
      .sessionExpired: .sessionInvalidated,
      .sessionNotFound: .sessionInvalidated,
      .userBanned: .sessionInvalidated,
      .flowStateNotFound: .oauthFlowFailed,
      .flowStateExpired: .oauthFlowFailed,
      .badCodeVerifier: .oauthFlowFailed,
    ]
  }

  /// What failed, in the terms of the next major version's error model.
  public var kind: Kind {
    switch self {
    case .sessionMissing: .sessionMissing
    case .refreshDiscarded: .refreshDiscarded
    case .weakPassword: .server
    case .api(_, let errorCode, _, _): Kind.kindsByCode[errorCode] ?? .server
    case .pkceGrantCodeExchange, .implicitGrantRedirect: .oauthFlowFailed
    case .jwtVerificationFailed: .jwtVerificationFailed
    // Deprecated cases
    case .invalidRedirectScheme: .oauthFlowFailed
    case .missingExpClaim, .malformedJWT: .jwtVerificationFailed
    case .missingURL: .invalidRequest
    }
  }

  /// The GoTrue error code. `nil` when the server sent none, or when the failure never reached
  /// the server.
  ///
  /// Unlike ``errorCode``, this is `nil` where ``errorCode`` reports a placeholder: `unknown`,
  /// `session_not_found` for ``sessionMissing``, and `invalid_jwt` for
  /// ``jwtVerificationFailed(message:)``.
  public var code: Code? {
    switch self {
    case .weakPassword: .weakPassword
    case .api(_, let errorCode, _, _): errorCode.rawValue == "unknown" ? nil : errorCode
    case .pkceGrantCodeExchange(_, _, let code): code.map(Code.init(rawValue:))
    default: nil
    }
  }

  /// Why the password was rejected. Empty unless this is
  /// ``weakPassword(message:reasons:)``.
  public var weakPasswordReasons: [String] {
    if case .weakPassword(_, let reasons) = self { reasons } else { [] }
  }
}

extension AuthError.Code {
  /// Matches an ``AuthError`` with this ``AuthError/code``, so a `catch` clause can name the
  /// code directly.
  ///
  /// ```swift
  /// do {
  ///   try await supabase.auth.signIn(email: email, password: password)
  /// } catch AuthError.Code.invalidCredentials {
  ///   showWrongPassword()
  /// }
  /// ```
  public static func ~= (code: AuthError.Code, error: any Error) -> Bool {
    (error as? AuthError)?.code == code
  }
}

extension AuthError.Kind {
  /// Matches an ``AuthError`` of this ``AuthError/kind``, so a `catch` clause can name the kind
  /// directly.
  ///
  /// ```swift
  /// do {
  ///   try await supabase.auth.refreshSession()
  /// } catch AuthError.Kind.sessionInvalidated {
  ///   showSignIn()
  /// }
  /// ```
  public static func ~= (kind: AuthError.Kind, error: any Error) -> Bool {
    (error as? AuthError)?.kind == kind
  }
}
