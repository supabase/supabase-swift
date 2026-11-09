import Foundation
public import Helpers

extension AuthError.Code {
  /// GoTrue failed in a way it did not expect, such as a 500 Internal Server Error.
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

/// An error thrown by ``AuthClient`` and related Auth types.
///
/// Check ``kind`` to learn which party failed, and ``code`` for the GoTrue error code when the
/// server rejected the request. ``response`` carries the status, headers, body and request
/// id for ``Kind-swift.struct/server``.
///
/// ```swift
/// do {
///   try await supabase.auth.signIn(email: email, password: password)
/// } catch AuthError.Code.invalidCredentials {
///   showWrongPassword()
/// } catch AuthError.Kind.sessionInvalidated {
///   showSignIn()
/// } catch let error as AuthError where error.code == .weakPassword {
///   showReasons(error.weakPasswordReasons)
/// }
/// ```
///
/// ## Topics
///
/// ### Inspecting an error
/// - ``kind``
/// - ``code``
/// - ``message``
/// - ``weakPasswordReasons``
/// - ``oauthError``
/// - ``isRetryable``
/// - ``response``
/// - ``underlyingError``
///
/// ### Common values
/// - ``sessionMissing``
/// - ``Kind-swift.struct``
/// - ``Code-swift.struct``
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

    /// GoTrue answered with a non-2xx status. Branch on ``AuthError/code`` for why (it is `nil`
    /// when the body was not a GoTrue error payload) and read ``AuthError/response`` for the
    /// status and body. For ``AuthError/Code-swift.struct/weakPassword``, show
    /// ``AuthError/weakPasswordReasons``. OAuth-style responses, such as those from the ID token
    /// grant, have no error code; read ``AuthError/oauthError`` instead.
    public static let server: Kind = "server"
    /// A session is required but none is stored locally. Sign the user in.
    public static let sessionMissing: Kind = "sessionMissing"
    /// The server rejected the session or its refresh token: it expired, was revoked, was
    /// already used, or the user is banned. When the rejected session is the current one, the
    /// client signs out and removes it from storage, and you get ``AuthEvent/signedOut``.
    /// A rejected refresh while the access token is still valid keeps the session until it
    /// expires, so react to ``AuthEvent/signedOut``, not to this error, to show
    /// sign-in. ``AuthError/code`` and ``AuthError/message`` keep the server's values.
    public static let sessionInvalidated: Kind = "sessionInvalidated"
    /// The claims of an ID token do not match the sign-in request, for example a nonce,
    /// audience, or issuer mismatch.
    public static let idTokenMismatch: Kind = "idTokenMismatch"
    /// Session storage cannot be read or written right now, for example a Keychain item that
    /// is not accessible while the device is locked. Try again later.
    ///
    /// A sign-in that throws this did not sign in, because the session could not be saved. Try
    /// the sign-in again after the device unlocks.
    public static let storageUnavailable: Kind = "storageUnavailable"
    /// Session storage is set up wrong, for example a missing Keychain entitlement. Fix the
    /// app's configuration; retrying does not help. The client also reports the first such error
    /// from its storage as a runtime issue.
    public static let storageMisconfigured: Kind = "storageMisconfigured"
    /// The client refreshed the session too many times in a short window and stopped, to avoid
    /// a refresh loop.
    public static let excessiveRefresh: Kind = "excessiveRefresh"
    /// The session is expired, and ``AuthClient/Configuration/autoRefresh`` is
    /// ``AuthClient/AutoRefreshPolicy/disabled``, so the client did not refresh it. Let the app
    /// that owns the session refresh it, or call ``AuthClient/refreshSession()``.
    public static let refreshDisabled: Kind = "refreshDisabled"
    /// A redirect-based sign-in (OAuth, magic link, PKCE or implicit flow) could not start or
    /// finish. Either no redirect URL with a scheme is configured, the redirect URL carried an
    /// error or no session, or the server rejected the flow state or code verifier
    /// (``AuthError/Code-swift.struct/flowStateNotFound``, ``AuthError/Code-swift.struct/flowStateExpired``,
    /// ``AuthError/Code-swift.struct/badCodeVerifier``). Start the sign-in again; ``AuthError/code`` carries
    /// the URL's or the server's error code when there was one.
    public static let oauthFlowFailed: Kind = "oauthFlowFailed"
    /// Local JWT verification failed: malformed, expired or bad signature. Discard the token and
    /// refresh the session or sign in again.
    public static let jwtVerificationFailed: Kind = "jwtVerificationFailed"
    /// No response arrived, so whether GoTrue applied the request is unknown. Retry reads
    /// freely; before retrying a sign-up or an update, check that it was not applied.
    /// ``AuthError/underlyingError`` is usually a `URLError`.
    public static let transport: Kind = "transport"
    /// A payload could not be interpreted: a 2xx body did not decode, a WebAuthn options object
    /// was missing a field, or the authenticator returned an unexpected credential. Nothing to
    /// retry; report it. ``AuthError/underlyingError`` is the `DecodingError` when there was one.
    public static let decoding: Kind = "decoding"
    /// A token refresh finished after the session it started from was signed out or replaced, so
    /// its rotated tokens were dropped rather than applied to whichever session is stored now.
    /// Ignore the result; the stored session is unchanged. Distinct from ``sessionMissing``: a
    /// session may well be stored, just not the one that refresh belonged to.
    public static let refreshDiscarded: Kind = "refreshDiscarded"
    /// The platform authenticator ended a passkey ceremony with an error other than a user
    /// cancel, which throws `CancellationError`. ``AuthError/underlyingError`` is the
    /// `ASAuthorizationError`. ``AuthError/code`` is ``AuthError/Code-swift.struct/webAuthnCredentialExists``
    /// when the device already holds one of the user's passkeys.
    @_spi(Experimental) public static let passkeyCeremonyFailed: Kind = "passkeyCeremonyFailed"
    /// ``AuthMFA/verifyWebAuthn(factorID:anchor:)`` got a factor that is not verified yet. The
    /// SDK shows no passkey sheet and sends no credential. Register a factor with
    /// ``AuthMFA/enrollWebAuthn(friendlyName:anchor:)``, or remove the unverified one with
    /// ``AuthMFA/unenroll(factorID:)``.
    @_spi(Experimental) public static let mfaFactorNotVerified: Kind = "mfaFactorNotVerified"
  }

  /// An error code GoTrue sends in the body of a rejected request, such as
  /// ``invalidCredentials``.
  ///
  /// Compare against the static members and keep a fallback branch: GoTrue adds codes, and a
  /// server newer than the SDK can send one this version does not know.
  public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    /// The code as GoTrue sends it, such as `"invalid_credentials"`.
    public let rawValue: String

    /// Creates a code from the value GoTrue sends.
    public init(rawValue: String) {
      self.rawValue = rawValue
    }

    /// Creates a code from a string literal.
    public init(stringLiteral value: String) {
      self.init(rawValue: value)
    }
  }

  public var kind: Kind
  public var message: String
  /// The GoTrue error code. `nil` when the server sent none, as for an OAuth-style response, a
  /// body that is not JSON, or a failure that never reached the server.
  public var code: Code?
  /// Why the password was rejected. Empty unless ``code`` is ``Code-swift.struct/weakPassword``.
  public var weakPasswordReasons: [String]
  /// The raw `error` field of an OAuth-style response, such as `invalid_grant` or
  /// `invalid nonce`. These responses carry no ``code``. `nil` for every other response.
  public var oauthError: String?
  public var response: HTTPErrorResponse?
  public var underlyingError: (any Error)?

  public init(
    kind: Kind,
    message: String,
    code: Code? = nil,
    weakPasswordReasons: [String] = [],
    oauthError: String? = nil,
    response: HTTPErrorResponse? = nil,
    underlyingError: (any Error)? = nil
  ) {
    self.kind = kind
    self.message = message
    self.code = code
    self.weakPasswordReasons = weakPasswordReasons
    self.oauthError = oauthError
    self.response = response
    self.underlyingError = underlyingError
  }

  public var description: String {
    formattedDescription(kind: kind.rawValue)
  }

  /// Whether the same request can succeed if sent again later.
  ///
  /// `true` for ``Kind-swift.struct/transport`` errors and for HTTP 408, 409, 429 and 5xx
  /// responses. GoTrue sends no `Retry-After` header, so back off with jitter before retrying.
  public var isRetryable: Bool {
    if kind == .transport { return true }
    guard let status = response?.status else { return false }
    return [.requestTimeout, .conflict, .tooManyRequests].contains(status)
      || status.kind == .serverError
  }

  /// Thrown when a session is required to proceed but none is stored locally.
  public static let sessionMissing = AuthError(
    kind: .sessionMissing, message: "Auth session missing.")

  /// Thrown when a token refresh finished after the session it started from was signed out or
  /// replaced, so its result was dropped instead of applied to the stored session.
  public static let refreshDiscarded = AuthError(
    kind: .refreshDiscarded,
    message: "Token refresh discarded: the session it started from is no longer stored.")
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
  ///   try await supabase.auth.signIn(email: email, password: password)
  /// } catch AuthError.Kind.transport {
  ///   showOfflineBanner()
  /// }
  /// ```
  public static func ~= (kind: AuthError.Kind, error: any Error) -> Bool {
    (error as? AuthError)?.kind == kind
  }
}

extension AuthError {
  var invalidatesSession: Bool {
    kind == .sessionInvalidated
  }

  /// Whether a refresh rejection means the session can never be refreshed again, so nothing is
  /// left to revoke. Narrower than ``invalidatesSession``: with refresh token rotation off,
  /// `refresh_token_already_used` fails only this request and leaves the session alive.
  var endsSessionForGood: Bool {
    [.refreshTokenNotFound, .sessionNotFound, .sessionExpired].contains(code)
  }

  /// Whether the server answered with a 4xx status.
  var isClientError: Bool {
    response?.status.kind == .clientError
  }

  static let excessiveRefresh = AuthError(
    kind: .excessiveRefresh,
    message: "Token refresh stopped: too many refreshes started in the last 30 seconds.")

  static let refreshDisabled = AuthError(
    kind: .refreshDisabled,
    message: "The session is expired, and auto refresh is disabled, so it was not refreshed.")

  static func oauthFlowFailed(_ message: String, code: Code? = nil) -> AuthError {
    AuthError(kind: .oauthFlowFailed, message: message, code: code)
  }

  static func passkeyCeremonyFailed(_ error: any Error, code: Code?) -> AuthError {
    AuthError(
      kind: .passkeyCeremonyFailed, message: error.localizedDescription, code: code,
      underlyingError: error)
  }

  static func jwtVerificationFailed(_ message: String) -> AuthError {
    AuthError(kind: .jwtVerificationFailed, message: message)
  }

  static func decoding(_ message: String) -> AuthError {
    AuthError(kind: .decoding, message: message)
  }
}
