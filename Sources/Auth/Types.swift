import Foundation

/// An event emitted when the authentication state of the current user changes.
public enum AuthChangeEvent: String, Sendable {
  /// Emitted when an initial session is loaded from local storage on startup.
  case initialSession = "INITIAL_SESSION"

  /// Emitted when a password-recovery email link is clicked, making the session available.
  case passwordRecovery = "PASSWORD_RECOVERY"

  /// Emitted when a user signs in or a new session is established.
  case signedIn = "SIGNED_IN"

  /// Emitted when a user signs out.
  case signedOut = "SIGNED_OUT"

  /// Emitted when the access token is refreshed.
  case tokenRefreshed = "TOKEN_REFRESHED"

  /// Emitted when the user's data is updated.
  case userUpdated = "USER_UPDATED"

  /// Emitted when the user's account is deleted.
  case userDeleted = "USER_DELETED"

  /// Emitted when an MFA challenge is successfully verified.
  case mfaChallengeVerified = "MFA_CHALLENGE_VERIFIED"
}

@available(
  *,
  deprecated,
  message: "Access to UserCredentials will be removed on the next major release."
)
public struct UserCredentials: Codable, Hashable, Sendable {
  public var email: String?
  public var password: String?
  public var phone: String?
  public var refreshToken: String?
  public var gotrueMetaSecurity: AuthMetaSecurity?

  public init(
    email: String? = nil,
    password: String? = nil,
    phone: String? = nil,
    refreshToken: String? = nil,
    gotrueMetaSecurity: AuthMetaSecurity? = nil
  ) {
    self.email = email
    self.password = password
    self.phone = phone
    self.refreshToken = refreshToken
    self.gotrueMetaSecurity = gotrueMetaSecurity
  }
}

struct SignUpRequest: Codable, Hashable, Sendable {
  var email: String?
  var password: String?
  var phone: String?
  var channel: MessagingChannel?
  var data: [String: AnyJSON]?
  var gotrueMetaSecurity: AuthMetaSecurity?
  var codeChallenge: String?
  var codeChallengeMethod: String?
}

/// An active authentication session containing the tokens and user details.
public struct Session: Codable, Hashable, Sendable {
  /// The OAuth provider token. If present, this can be used to make external API requests to the
  /// OAuth provider used.
  public var providerToken: String?

  /// The OAuth provider refresh token. If present, this can be used to refresh the provider_token
  /// via the OAuth provider's API. Not all OAuth providers return a provider refresh token. If the
  /// provider_refresh_token is missing, please refer to the OAuth provider's documentation for
  /// information on how to obtain the provider refresh token.
  public var providerRefreshToken: String?

  /// A valid JWT that will expire in ``Session/expiresIn`` seconds.
  ///
  /// It is recommended to set the `JWT_EXPIRY` to a shorter expiry value.
  public var accessToken: String

  /// The token type. Currently only `bearer` is returned; this may change in the future.
  public var tokenType: String

  /// Number of seconds after which the ``Session/accessToken`` should be renewed by using the
  /// refresh token with the `refresh_token` grant type.
  public var expiresIn: TimeInterval

  /// UNIX timestamp after which the ``Session/accessToken`` should be renewed by using the refresh
  /// token with the `refresh_token` grant type.
  public var expiresAt: TimeInterval

  /// An opaque string that can be used once to obtain a new access and refresh token.
  public var refreshToken: String

  /// Only returned on the `/token?grant_type=password` endpoint. When present, it indicates that
  /// the password used is weak. Inspect the ``WeakPassword/reasons`` property to identify why.
  public var weakPassword: WeakPassword?

  /// The authenticated user associated with this session.
  public var user: User

  /// Creates a new session value.
  ///
  /// - Parameters:
  ///   - providerToken: The OAuth provider token.
  ///   - providerRefreshToken: The OAuth provider refresh token.
  ///   - accessToken: A valid JWT access token.
  ///   - tokenType: The token type (e.g. `bearer`).
  ///   - expiresIn: Number of seconds until the access token expires.
  ///   - expiresAt: UNIX timestamp at which the access token expires.
  ///   - refreshToken: Opaque refresh token string.
  ///   - weakPassword: Weak-password information returned by the server, if any.
  ///   - user: The authenticated user.
  public init(
    providerToken: String? = nil,
    providerRefreshToken: String? = nil,
    accessToken: String,
    tokenType: String,
    expiresIn: TimeInterval,
    expiresAt: TimeInterval,
    refreshToken: String,
    weakPassword: WeakPassword? = nil,
    user: User
  ) {
    self.providerToken = providerToken
    self.providerRefreshToken = providerRefreshToken
    self.accessToken = accessToken
    self.tokenType = tokenType
    self.expiresIn = expiresIn
    self.expiresAt = expiresAt
    self.refreshToken = refreshToken
    self.weakPassword = weakPassword
    self.user = user
  }

  /// Returns `true` if the access token is expired or will expire within the next 30 seconds.
  ///
  /// The 30-second buffer accounts for network latency.
  public var isExpired: Bool {
    let expiresAt = Date(timeIntervalSince1970: expiresAt)
    return expiresAt.timeIntervalSinceNow < defaultExpiryMargin
  }
}

/// A Supabase Auth user record.
public struct User: Codable, Hashable, Identifiable, Sendable {
  /// The unique identifier of the user.
  public var id: UUID

  /// Application-specific metadata stored by the administrator in `auth.users.app_metadata`.
  public var appMetadata: [String: AnyJSON]

  /// User-supplied metadata stored in `auth.users.raw_user_meta_data`.
  public var userMetadata: [String: AnyJSON]

  /// The audience claim (`aud`) of the user's JWT.
  public var aud: String

  /// Timestamp when a confirmation email was last sent to this user.
  public var confirmationSentAt: Date?

  /// Timestamp when a recovery email was last sent to this user.
  public var recoverySentAt: Date?

  /// Timestamp when an email-change confirmation was last sent to this user.
  public var emailChangeSentAt: Date?

  /// The new email address the user has requested, pending confirmation.
  public var newEmail: String?

  /// Timestamp when the user was invited.
  public var invitedAt: Date?

  /// A one-time action link, if one was generated for this user.
  public var actionLink: String?

  /// The user's email address.
  public var email: String?

  /// The user's phone number in E.164 format.
  public var phone: String?

  /// Timestamp when the user account was created.
  public var createdAt: Date

  /// Timestamp when the user account was confirmed (email or phone).
  public var confirmedAt: Date?

  /// Timestamp when the user's email address was confirmed.
  public var emailConfirmedAt: Date?

  /// Timestamp when the user's phone number was confirmed.
  public var phoneConfirmedAt: Date?

  /// Timestamp of the user's last sign-in.
  public var lastSignInAt: Date?

  /// The role assigned to the user (appears in the JWT `role` claim).
  public var role: String?

  /// Timestamp when the user record was last updated.
  public var updatedAt: Date

  /// Third-party provider identities linked to this user.
  public var identities: [UserIdentity]?

  /// Whether this is an anonymous user.
  public var isAnonymous: Bool

  /// MFA factors registered for this user.
  public var factors: [Factor]?

  /// Creates a new user value with the given properties.
  ///
  /// - Parameters:
  ///   - id: The unique identifier.
  ///   - appMetadata: Application-level metadata.
  ///   - userMetadata: User-supplied metadata.
  ///   - aud: The JWT audience claim.
  ///   - confirmationSentAt: Timestamp a confirmation email was sent.
  ///   - recoverySentAt: Timestamp a recovery email was sent.
  ///   - emailChangeSentAt: Timestamp an email-change email was sent.
  ///   - newEmail: Pending new email address.
  ///   - invitedAt: Timestamp the user was invited.
  ///   - actionLink: A one-time action link.
  ///   - email: The user's email address.
  ///   - phone: The user's phone number.
  ///   - createdAt: Timestamp the account was created.
  ///   - confirmedAt: Timestamp the account was confirmed.
  ///   - emailConfirmedAt: Timestamp the email was confirmed.
  ///   - phoneConfirmedAt: Timestamp the phone was confirmed.
  ///   - lastSignInAt: Timestamp of the last sign-in.
  ///   - role: The user's role.
  ///   - updatedAt: Timestamp the record was last updated.
  ///   - identities: Linked third-party identities.
  ///   - isAnonymous: Whether the user is anonymous.
  ///   - factors: Registered MFA factors.
  public init(
    id: UUID,
    appMetadata: [String: AnyJSON],
    userMetadata: [String: AnyJSON],
    aud: String,
    confirmationSentAt: Date? = nil,
    recoverySentAt: Date? = nil,
    emailChangeSentAt: Date? = nil,
    newEmail: String? = nil,
    invitedAt: Date? = nil,
    actionLink: String? = nil,
    email: String? = nil,
    phone: String? = nil,
    createdAt: Date,
    confirmedAt: Date? = nil,
    emailConfirmedAt: Date? = nil,
    phoneConfirmedAt: Date? = nil,
    lastSignInAt: Date? = nil,
    role: String? = nil,
    updatedAt: Date,
    identities: [UserIdentity]? = nil,
    isAnonymous: Bool = false,
    factors: [Factor]? = nil
  ) {
    self.id = id
    self.appMetadata = appMetadata
    self.userMetadata = userMetadata
    self.aud = aud
    self.confirmationSentAt = confirmationSentAt
    self.recoverySentAt = recoverySentAt
    self.emailChangeSentAt = emailChangeSentAt
    self.newEmail = newEmail
    self.invitedAt = invitedAt
    self.actionLink = actionLink
    self.email = email
    self.phone = phone
    self.createdAt = createdAt
    self.confirmedAt = confirmedAt
    self.emailConfirmedAt = emailConfirmedAt
    self.phoneConfirmedAt = phoneConfirmedAt
    self.lastSignInAt = lastSignInAt
    self.role = role
    self.updatedAt = updatedAt
    self.identities = identities
    self.isAnonymous = isAnonymous
    self.factors = factors
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    appMetadata = try container.decodeIfPresent([String: AnyJSON].self, forKey: .appMetadata) ?? [:]
    userMetadata =
      try container.decodeIfPresent([String: AnyJSON].self, forKey: .userMetadata) ?? [:]
    aud = try container.decode(String.self, forKey: .aud)
    confirmationSentAt = try container.decodeIfPresent(Date.self, forKey: .confirmationSentAt)
    recoverySentAt = try container.decodeIfPresent(Date.self, forKey: .recoverySentAt)
    emailChangeSentAt = try container.decodeIfPresent(Date.self, forKey: .emailChangeSentAt)
    newEmail = try container.decodeIfPresent(String.self, forKey: .newEmail)
    invitedAt = try container.decodeIfPresent(Date.self, forKey: .invitedAt)
    actionLink = try container.decodeIfPresent(String.self, forKey: .actionLink)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    phone = try container.decodeIfPresent(String.self, forKey: .phone)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    confirmedAt = try container.decodeIfPresent(Date.self, forKey: .confirmedAt)
    emailConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .emailConfirmedAt)
    phoneConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .phoneConfirmedAt)
    lastSignInAt = try container.decodeIfPresent(Date.self, forKey: .lastSignInAt)
    role = try container.decodeIfPresent(String.self, forKey: .role)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    identities = try container.decodeIfPresent([UserIdentity].self, forKey: .identities)
    isAnonymous = try container.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? false
    factors = try container.decodeIfPresent([Factor].self, forKey: .factors)
  }
}

/// A third-party identity linked to a ``User``.
public struct UserIdentity: Codable, Hashable, Identifiable, Sendable {
  /// Provider-specific identifier of this identity.
  public var id: String

  /// Unique identifier of the identity record within Supabase.
  public var identityId: UUID

  /// The user this identity belongs to.
  public var userId: UUID

  /// Provider-specific identity data returned by the third-party.
  public var identityData: [String: AnyJSON]?

  /// The name of the provider (e.g. `google`, `github`).
  public var provider: String

  /// Timestamp when this identity was created.
  public var createdAt: Date?

  /// Timestamp of the last sign-in with this identity.
  public var lastSignInAt: Date?

  /// Timestamp when this identity record was last updated.
  public var updatedAt: Date?

  /// Creates a new user identity value.
  ///
  /// - Parameters:
  ///   - id: The provider-specific identity ID.
  ///   - identityId: The Supabase identity UUID.
  ///   - userId: The owning user's UUID.
  ///   - identityData: Provider-specific identity data.
  ///   - provider: The provider name.
  ///   - createdAt: Timestamp the identity was created.
  ///   - lastSignInAt: Timestamp of the last sign-in via this identity.
  ///   - updatedAt: Timestamp the identity was last updated.
  public init(
    id: String,
    identityId: UUID,
    userId: UUID,
    identityData: [String: AnyJSON],
    provider: String,
    createdAt: Date?,
    lastSignInAt: Date?,
    updatedAt: Date?
  ) {
    self.id = id
    self.identityId = identityId
    self.userId = userId
    self.identityData = identityData
    self.provider = provider
    self.createdAt = createdAt
    self.lastSignInAt = lastSignInAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: CodingKey {
    case id
    case identityId
    case userId
    case identityData
    case provider
    case createdAt
    case lastSignInAt
    case updatedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(String.self, forKey: .id)
    identityId =
      try container.decodeIfPresent(UUID.self, forKey: .identityId)
      ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    userId = try container.decode(UUID.self, forKey: .userId)
    identityData = try container.decodeIfPresent([String: AnyJSON].self, forKey: .identityData)
    provider = try container.decode(String.self, forKey: .provider)
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    lastSignInAt = try container.decodeIfPresent(Date.self, forKey: .lastSignInAt)
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(id, forKey: .id)
    try container.encode(identityId, forKey: .identityId)
    try container.encode(userId, forKey: .userId)
    try container.encodeIfPresent(identityData, forKey: .identityData)
    try container.encode(provider, forKey: .provider)
    try container.encodeIfPresent(createdAt, forKey: .createdAt)
    try container.encodeIfPresent(lastSignInAt, forKey: .lastSignInAt)
    try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
  }
}

/// One of the providers supported by Auth.
public enum Provider: String, Identifiable, Codable, CaseIterable, Sendable {
  case apple
  case azure
  case bitbucket
  case discord
  case email
  case facebook
  case figma
  case github
  case gitlab
  case google
  case kakao
  case keycloak
  case linkedin
  case linkedinOIDC = "linkedin_oidc"
  case notion
  case slack
  case slackOIDC = "slack_oidc"
  case spotify
  case twitch
  /// Uses OAuth 1.0a
  case twitter
  /// Uses OAuth 2.0
  case x
  case workos
  case zoom
  case fly

  /// The raw string value of the provider, used as the stable identifier.
  public var id: RawValue { rawValue }
}

/// Credentials for signing in with an OpenID Connect (OIDC) ID token issued by a third-party.
public struct OpenIDConnectCredentials: Codable, Hashable, Sendable {
  /// Provider name or OIDC `iss` value identifying which provider should be used to verify the
  /// provided token. Supported names: `google`, `apple`, `azure`, `facebook`.
  public var provider: Provider

  /// OIDC ID token issued by the specified provider. The `iss` claim in the ID token must match the
  /// supplied provider. Some ID tokens contain an `at_hash` which require that you provide an
  /// `access_token` value to be accepted properly. If the token contains a `nonce` claim you must
  /// supply the nonce used to obtain the ID token.
  public var idToken: String

  /// If the ID token contains an `at_hash` claim, then the hash of this value is compared to the
  /// value in the ID token.
  public var accessToken: String?

  /// If the ID token contains a `nonce` claim, then the hash of this value is compared to the value
  /// in the ID token.
  public var nonce: String?

  /// Verification token received when the user completes the captcha on the site.
  public var gotrueMetaSecurity: AuthMetaSecurity?

  var linkIdentity: Bool = false

  /// Creates OIDC credentials for sign-in.
  ///
  /// - Parameters:
  ///   - provider: The OIDC provider.
  ///   - idToken: The ID token issued by the provider.
  ///   - accessToken: Optional access token, required when the ID token contains an `at_hash` claim.
  ///   - nonce: Optional nonce, required when the ID token contains a `nonce` claim.
  ///   - gotrueMetaSecurity: Optional captcha verification token.
  public init(
    provider: Provider,
    idToken: String,
    accessToken: String? = nil,
    nonce: String? = nil,
    gotrueMetaSecurity: AuthMetaSecurity? = nil
  ) {
    self.provider = provider
    self.idToken = idToken
    self.accessToken = accessToken
    self.nonce = nonce
    self.gotrueMetaSecurity = gotrueMetaSecurity
  }

  /// Providers supported by the OIDC sign-in flow.
  public enum Provider: String, Codable, Hashable, Sendable {
    case google, apple, azure, facebook
  }
}

/// A captcha verification token used to secure Auth endpoints.
public struct AuthMetaSecurity: Codable, Hashable, Sendable {
  /// The captcha token obtained after the user completes a captcha challenge.
  public var captchaToken: String

  /// Creates an ``AuthMetaSecurity`` value with the given captcha token.
  ///
  /// - Parameter captchaToken: The captcha token.
  public init(captchaToken: String) {
    self.captchaToken = captchaToken
  }
}

struct OTPParams: Codable, Hashable, Sendable {
  var email: String?
  var phone: String?
  var createUser: Bool
  var channel: MessagingChannel?
  var data: [String: AnyJSON]?
  var gotrueMetaSecurity: AuthMetaSecurity?
  var codeChallenge: String?
  var codeChallengeMethod: String?
}

enum VerifyOTPParams: Encodable {
  case email(VerifyEmailOTPParams)
  case mobile(VerifyMobileOTPParams)
  case tokenHash(VerifyTokenHashParams)

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .email(let value):
      try container.encode(value)
    case .mobile(let value):
      try container.encode(value)
    case .tokenHash(let value):
      try container.encode(value)
    }
  }
}

struct VerifyEmailOTPParams: Encodable, Hashable, Sendable {
  var email: String
  var token: String
  var type: EmailOTPType
  var gotrueMetaSecurity: AuthMetaSecurity?
}

struct VerifyTokenHashParams: Encodable, Hashable, Sendable {
  var tokenHash: String
  var type: EmailOTPType
}

struct VerifyMobileOTPParams: Encodable, Hashable {
  var phone: String
  var token: String
  var type: MobileOTPType
  var gotrueMetaSecurity: AuthMetaSecurity?
}

/// The OTP type used when verifying a mobile (SMS/WhatsApp) one-time password.
public enum MobileOTPType: String, Encodable, Sendable {
  /// A standard SMS OTP sent to the phone number.
  case sms

  /// An OTP used when confirming a phone number change.
  case phoneChange = "phone_change"
}

/// The OTP type used when verifying an email one-time password.
public enum EmailOTPType: String, Encodable, CaseIterable, Sendable {
  /// OTP sent during initial sign-up email confirmation.
  case signup

  /// OTP sent when an admin invites a user by email.
  case invite

  /// OTP sent as part of a magic-link sign-in flow.
  case magiclink

  /// OTP sent when the user requests a password reset.
  case recovery

  /// OTP sent when the user requests an email address change.
  case emailChange = "email_change"

  /// Generic email OTP.
  case email
}

/// The response from sign-up and OTP-verification calls that may return either a session or a
/// user depending on whether email confirmation is required.
public enum AuthResponse: Codable, Hashable, Sendable {
  /// A full session was created, meaning the user is immediately signed in.
  case session(Session)

  /// Only a user record was returned, meaning email confirmation is still pending.
  case user(User)

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Session.self) {
      self = .session(value)
    } else if let value = try? container.decode(User.self) {
      self = .user(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Data could not be decoded as any of the expected types (Session, User)."
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .session(let value): try container.encode(value)
    case .user(let value): try container.encode(value)
    }
  }

  /// The user in either case of the response.
  public var user: User {
    switch self {
    case .session(let session): session.user
    case .user(let user): user
    }
  }

  /// The session, or `nil` if only a user was returned (confirmation pending).
  public var session: Session? {
    if case .session(let session) = self { return session }
    return nil
  }
}

/// Attributes that a user can update for their own account.
public struct UserAttributes: Codable, Hashable, Sendable {
  /// The user's email.
  public var email: String?

  /// The user's phone.
  public var phone: String?

  /// The user's password.
  public var password: String?

  /// The nonce sent for reauthentication if the user's password is to be updated.
  ///
  /// > Note: Call ``AuthClient/reauthenticate()`` to obtain the nonce first.
  public var nonce: String?

  /// An email change token.
  @available(*, deprecated, message: "This is an old field, stop relying on it.")
  public var emailChangeToken: String?

  /// A custom data object to store the user's metadata. This maps to the `auth.users.user_metadata`
  /// column. The `data` should be a JSON object that includes user-specific info, such as their
  /// first and last name.
  public var data: [String: AnyJSON]?

  var codeChallenge: String?
  var codeChallengeMethod: String?

  /// Creates user attributes for an update call.
  ///
  /// - Parameters:
  ///   - email: New email address.
  ///   - phone: New phone number.
  ///   - password: New password.
  ///   - nonce: Reauthentication nonce, required when updating the password.
  ///   - emailChangeToken: Deprecated email-change token.
  ///   - data: Additional user metadata to merge.
  public init(
    email: String? = nil,
    phone: String? = nil,
    password: String? = nil,
    nonce: String? = nil,
    emailChangeToken: String? = nil,
    data: [String: AnyJSON]? = nil
  ) {
    self.email = email
    self.phone = phone
    self.password = password
    self.nonce = nonce
    self.emailChangeToken = emailChangeToken
    self.data = data
  }
}

/// Attributes that an administrator can set when creating or updating a user.
public struct AdminUserAttributes: Encodable, Hashable, Sendable {

  /// A custom data object to store the user's application specific metadata. This maps to the `auth.users.app_metadata` column.
  public var appMetadata: [String: AnyJSON]?

  /// Determines how long a user is banned for.
  ///
  /// Pass `none` to remove an existing ban.
  public var banDuration: String?

  /// The user's email.
  public var email: String?

  /// Confirms the user's email address if set to `true`.
  public var emailConfirm: Bool?

  /// The `id` for the user.
  public var id: String?

  /// The nonce sent for reauthentication if the user's password is to be updated.
  public var nonce: String?

  /// The user's password.
  public var password: String?

  /// The `password_hash` for the user's password.
  public var passwordHash: String?

  /// The user's phone.
  public var phone: String?

  /// Confirms the user's phone number if set to `true`.
  public var phoneConfirm: Bool?

  /// The role claim set in the user's access token JWT.
  public var role: String?

  /// A custom data object to store the user's metadata. This maps to the `auth.users.raw_user_meta_data` column.
  public var userMetadata: [String: AnyJSON]?

  /// Creates admin user attributes.
  ///
  /// - Parameters:
  ///   - appMetadata: Application-level metadata.
  ///   - banDuration: Ban duration string, e.g. `"24h"`, or `"none"` to lift a ban.
  ///   - email: The user's email address.
  ///   - emailConfirm: Whether to mark the email as confirmed.
  ///   - id: The user's UUID (string form).
  ///   - nonce: Reauthentication nonce for password updates.
  ///   - password: Plain-text password.
  ///   - passwordHash: Pre-hashed password.
  ///   - phone: The user's phone number.
  ///   - phoneConfirm: Whether to mark the phone as confirmed.
  ///   - role: The JWT role claim.
  ///   - userMetadata: User-supplied metadata.
  public init(
    appMetadata: [String: AnyJSON]? = nil,
    banDuration: String? = nil,
    email: String? = nil,
    emailConfirm: Bool? = nil,
    id: String? = nil,
    nonce: String? = nil,
    password: String? = nil,
    passwordHash: String? = nil,
    phone: String? = nil,
    phoneConfirm: Bool? = nil,
    role: String? = nil,
    userMetadata: [String: AnyJSON]? = nil
  ) {
    self.appMetadata = appMetadata
    self.banDuration = banDuration
    self.email = email
    self.emailConfirm = emailConfirm
    self.id = id
    self.nonce = nonce
    self.password = password
    self.passwordHash = passwordHash
    self.phone = phone
    self.phoneConfirm = phoneConfirm
    self.role = role
    self.userMetadata = userMetadata
  }
}

struct RecoverParams: Codable, Hashable, Sendable {
  var email: String
  var gotrueMetaSecurity: AuthMetaSecurity?
  var codeChallenge: String?
  var codeChallengeMethod: String?
}

/// The OAuth / sign-in flow type used by ``AuthClient``.
public enum AuthFlowType: Sendable {
  /// The implicit grant flow — tokens are returned in the URL fragment.
  ///
  /// > Warning: This flow is less secure than PKCE and should only be used when PKCE is not
  /// > supported by the environment.
  case implicit

  /// The Proof Key for Code Exchange (PKCE) flow — an authorization code is exchanged for tokens.
  ///
  /// This is the recommended flow for mobile and desktop applications.
  case pkce
}

/// The string type used to identify an MFA factor type (e.g. `"totp"`, `"phone"`, `"webauthn"`).
public typealias FactorType = String

/// The enrollment status of an MFA factor.
public enum FactorStatus: String, Codable, Sendable {
  /// The factor has been verified and is active.
  case verified

  /// The factor has been enrolled but not yet verified.
  case unverified
}

/// An MFA Factor.
public struct Factor: Identifiable, Codable, Hashable, Sendable {
  /// ID of the factor.
  public let id: String

  /// Friendly name of the factor, useful to disambiguate between multiple factors.
  public let friendlyName: String?

  /// Type of factor. `totp` and `phone` supported with this version.
  public let factorType: FactorType

  /// Factor's status.
  public let status: FactorStatus

  /// Timestamp when the factor was created.
  public let createdAt: Date

  /// Timestamp when the factor was last updated.
  public let updatedAt: Date
}

/// The protocol that MFA enrollment parameter types must conform to.
public protocol MFAEnrollParamsType: Encodable, Hashable, Sendable {
  /// The factor type identifier (e.g. `"totp"`, `"phone"`, `"webauthn"`).
  var factorType: FactorType { get }
}

/// Parameters for enrolling a TOTP (Time-based One-Time Password) MFA factor.
public struct MFATotpEnrollParams: MFAEnrollParamsType {
  /// The factor type, always `"totp"`.
  public let factorType: FactorType = "totp"

  /// Domain which the user is enrolled with.
  public let issuer: String?

  /// Human readable name assigned to the factor.
  public let friendlyName: String?

  /// Creates TOTP enrollment parameters.
  ///
  /// - Parameters:
  ///   - issuer: The issuer domain shown in authenticator apps.
  ///   - friendlyName: A human-readable label for the factor.
  public init(issuer: String? = nil, friendlyName: String? = nil) {
    self.issuer = issuer
    self.friendlyName = friendlyName
  }
}

extension MFAEnrollParamsType where Self == MFATotpEnrollParams {
  /// Creates parameters for enrolling a TOTP factor.
  ///
  /// - Parameters:
  ///   - issuer: The issuer domain shown in authenticator apps.
  ///   - friendlyName: A human-readable label for the factor.
  public static func totp(issuer: String? = nil, friendlyName: String? = nil) -> Self {
    MFATotpEnrollParams(issuer: issuer, friendlyName: friendlyName)
  }
}

/// Parameters for enrolling a phone (SMS/WhatsApp) MFA factor.
public struct MFAPhoneEnrollParams: MFAEnrollParamsType {
  /// The factor type, always `"phone"`.
  public let factorType: FactorType = "phone"

  /// Human readable name assigned to the factor.
  public let friendlyName: String?

  /// Phone number to be enrolled. Number should conform to E.164 standard.
  public let phone: String

  /// Creates phone enrollment parameters.
  ///
  /// - Parameters:
  ///   - friendlyName: A human-readable label for the factor.
  ///   - phone: The phone number in E.164 format.
  public init(friendlyName: String? = nil, phone: String) {
    self.friendlyName = friendlyName
    self.phone = phone
  }
}

extension MFAEnrollParamsType where Self == MFAPhoneEnrollParams {
  /// Creates parameters for enrolling a phone factor.
  ///
  /// - Parameters:
  ///   - friendlyName: A human-readable label for the factor.
  ///   - phone: The phone number in E.164 format.
  public static func phone(friendlyName: String? = nil, phone: String) -> Self {
    MFAPhoneEnrollParams(friendlyName: friendlyName, phone: phone)
  }
}

/// The response returned after successfully enrolling a new MFA factor.
public struct AuthMFAEnrollResponse: Decodable, Hashable, Sendable {
  /// ID of the factor that was just enrolled (in an unverified state).
  public let id: String

  /// Type of MFA factor.
  public let type: FactorType

  /// TOTP enrollment information. Available only if the ``type`` is `totp`.
  public var totp: TOTP?

  /// Friendly name of the factor, useful to disambiguate between multiple factors.
  public var friendlyName: String?

  /// Phone number of the MFA factor in E.164 format. Used to send messages. Available only if the ``type`` is `phone`.
  public var phone: String?

  /// TOTP-specific enrollment data, including the QR code and shared secret.
  public struct TOTP: Decodable, Hashable, Sendable {
    /// Contains a QR code encoding the authenticator URI. You can convert it to a URL by prepending
    /// `data:image/svg+xml;utf-8,` to the value. Avoid logging this value to the console.
    public var qrCode: String

    /// The TOTP secret (also encoded in the QR code). Show this secret in a password-style field to
    /// the user, in case they are unable to scan the QR code. Avoid logging this value to the
    /// console.
    public let secret: String

    /// The authenticator URI encoded within the QR code, should you need to use it. Avoid logging
    /// this value to the console.
    public let uri: String
  }
}

/// Parameters for creating an MFA challenge.
public struct MFAChallengeParams: Encodable, Hashable {
  /// ID of the factor to be challenged. Returned in ``AuthMFA/enroll(params:)``.
  public let factorId: String

  /// Messaging channel to use (e.g. `whatsapp` or `sms`). Only relevant for phone factors.
  public let channel: MessagingChannel?

  /// Relying-party options. Only relevant for WebAuthn factors.
  @_spi(Experimental) public let webAuthn: WebAuthnChallengeOptions?

  /// Creates challenge parameters for a TOTP or phone factor.
  ///
  /// - Parameters:
  ///   - factorId: The factor ID to challenge.
  ///   - channel: The messaging channel for phone factors.
  public init(factorId: String, channel: MessagingChannel? = nil) {
    self.factorId = factorId
    self.channel = channel
    self.webAuthn = nil
  }

  /// Creates challenge parameters including WebAuthn relying-party options.
  ///
  /// - Parameters:
  ///   - factorId: The factor ID to challenge.
  ///   - channel: The messaging channel for phone factors.
  ///   - webAuthn: WebAuthn-specific options.
  @_spi(Experimental)
  public init(
    factorId: String,
    channel: MessagingChannel? = nil,
    webAuthn: WebAuthnChallengeOptions?
  ) {
    self.factorId = factorId
    self.channel = channel
    self.webAuthn = webAuthn
  }
}

/// Parameters for verifying an MFA challenge.
public struct MFAVerifyParams: Encodable, Hashable {
  /// ID of the factor being verified. Returned in ``AuthMFA/enroll(params:)``.
  public let factorId: String

  /// ID of the challenge being verified. Returned in challenge().
  public let challengeId: String

  /// Verification code provided by the user. Used for `totp` and `phone` factors; empty for
  /// `webauthn` factors (which use ``credentialResponse`` instead).
  public let code: String

  /// The W3C credential (assertion) response produced by the authenticator. Used for `webauthn`
  /// factors. Forwarded verbatim to the backend, preserving the W3C field names.
  @_spi(Experimental) public let credentialResponse: AnyJSON?

  /// Verifies a `totp` or `phone` factor using a user-provided code.
  ///
  /// - Parameters:
  ///   - factorId: The factor ID being verified.
  ///   - challengeId: The challenge ID being verified.
  ///   - code: The verification code from the authenticator app or SMS.
  public init(factorId: String, challengeId: String, code: String) {
    self.factorId = factorId
    self.challengeId = challengeId
    self.code = code
    self.credentialResponse = nil
  }

  /// Verifies a `webauthn` factor using the credential response produced by the authenticator.
  ///
  /// - Parameters:
  ///   - factorId: The factor ID being verified.
  ///   - challengeId: The challenge ID being verified.
  ///   - credentialResponse: The W3C assertion produced by the platform authenticator.
  @_spi(Experimental)
  public init(factorId: String, challengeId: String, credentialResponse: AnyJSON) {
    self.factorId = factorId
    self.challengeId = challengeId
    self.code = ""
    self.credentialResponse = credentialResponse
  }
}

/// Parameters for unenrolling an MFA factor.
public struct MFAUnenrollParams: Encodable, Hashable, Sendable {
  /// ID of the factor to unenroll. Returned in ``AuthMFA/enroll(params:)``.
  public let factorId: String

  /// Creates unenroll parameters.
  ///
  /// - Parameter factorId: The factor ID to unenroll.
  public init(factorId: String) {
    self.factorId = factorId
  }
}

/// Parameters for the combined challenge-and-verify operation.
public struct MFAChallengeAndVerifyParams: Encodable, Hashable, Sendable {
  /// ID of the factor to be challenged. Returned in ``AuthMFA/enroll(params:)``.
  public let factorId: String

  /// Verification code provided by the user.
  public let code: String

  /// Creates challenge-and-verify parameters.
  ///
  /// - Parameters:
  ///   - factorId: The factor ID to challenge and verify.
  ///   - code: The verification code from the user.
  public init(factorId: String, code: String) {
    self.factorId = factorId
    self.code = code
  }
}

/// The response returned after creating an MFA challenge.
public struct AuthMFAChallengeResponse: Decodable, Hashable, Sendable {
  /// ID of the newly created challenge.
  public let id: String

  /// Factor type which generated the challenge.
  public let type: FactorType

  /// Timestamp in UNIX seconds when this challenge will no longer be usable.
  public let expiresAt: TimeInterval

  /// WebAuthn credential options. Present only when ``type`` is `webauthn`.
  @_spi(Experimental) public var webauthn: WebAuthnChallengeResponseData? = nil
}

/// A type alias that maps an MFA verify response to a ``Session``.
public typealias AuthMFAVerifyResponse = Session

/// The response returned after successfully unenrolling an MFA factor.
public struct AuthMFAUnenrollResponse: Decodable, Hashable, Sendable {
  /// ID of the factor that was successfully unenrolled.
  public let id: String
}

/// The response returned by ``AuthMFA/listFactors()``.
public struct AuthMFAListFactorsResponse: Decodable, Hashable, Sendable {
  /// All available factors (verified and unverified).
  public let all: [Factor]

  /// Only verified TOTP factors. (A subset of `all`.)
  public let totp: [Factor]

  /// Only verified phone factors. (A subset of `all`.)
  public let phone: [Factor]

  /// Only verified WebAuthn (passkey) factors. (A subset of `all`.)
  @_spi(Experimental) public let webauthn: [Factor]
}

/// A string representing an Authenticator Assurance Level (`aal1` or `aal2`).
public typealias AuthenticatorAssuranceLevels = String

/// An authentication method reference (AMR) entry.
///
/// An entry designates what method was used by the user to verify their identity and at what time.
public struct AMREntry: Decodable, Hashable, Sendable {
  /// Authentication method name.
  public let method: Method

  /// Timestamp when the method was successfully used.
  public let timestamp: TimeInterval

  /// The string type used for authentication method names.
  public typealias Method = String
}

extension AMREntry {
  init?(value: Any) {
    guard let dict = value as? [String: Any],
      let method = dict["method"] as? Method,
      let timestamp = dict["timestamp"] as? TimeInterval
    else {
      return nil
    }

    self.method = method
    self.timestamp = timestamp
  }
}

/// The response returned by ``AuthMFA/getAuthenticatorAssuranceLevel()``.
public struct AuthMFAGetAuthenticatorAssuranceLevelResponse: Decodable, Hashable, Sendable {
  /// Current AAL level of the session.
  public let currentLevel: AuthenticatorAssuranceLevels?

  /// Next possible AAL level for the session. If the next level is higher than the current one, the
  /// user should go through MFA.
  public let nextLevel: AuthenticatorAssuranceLevels?

  /// A list of all authentication methods attached to this session. Use the information here to
  /// detect the last time a user verified a factor, for example if implementing a step-up scenario.
  public let currentAuthenticationMethods: [AMREntry]
}

/// The scope of a sign-out operation.
public enum SignOutScope: String, Sendable {
  /// All sessions by this account will be signed out.
  case global

  /// Only this session will be signed out.
  case local

  /// All other sessions except the current one will be signed out. When using
  /// ``SignOutScope/others``, there is no ``AuthChangeEvent/signedOut`` event fired on the current
  /// session.
  case others
}

/// The type of email to resend when calling ``AuthClient/resend(email:type:emailRedirectTo:captchaToken:)``.
public enum ResendEmailType: String, Hashable, Sendable, Encodable {
  /// Resends the initial sign-up confirmation email.
  case signup

  /// Resends the email-change confirmation email.
  case emailChange = "email_change"
}

struct ResendEmailParams: Encodable {
  let type: ResendEmailType
  let email: String
  let gotrueMetaSecurity: AuthMetaSecurity?
}

/// The type of mobile OTP to resend when calling ``AuthClient/resend(phone:type:captchaToken:)``.
public enum ResendMobileType: String, Hashable, Sendable, Encodable {
  /// Resends the SMS OTP for the current phone sign-in.
  case sms

  /// Resends the OTP for confirming a phone number change.
  case phoneChange = "phone_change"
}

struct ResendMobileParams: Encodable {
  let type: ResendMobileType
  let phone: String
  let gotrueMetaSecurity: AuthMetaSecurity?
}

/// The response returned when resending an SMS OTP.
public struct ResendMobileResponse: Decodable, Hashable, Sendable {
  /// Unique ID of the message as reported by the SMS sending provider. Useful for tracking
  /// deliverability problems.
  public let messageId: String?

  /// Creates a resend mobile response.
  ///
  /// - Parameter messageId: The provider-assigned message ID.
  public init(messageId: String?) {
    self.messageId = messageId
  }
}

/// Information about why a password is considered weak.
public struct WeakPassword: Codable, Hashable, Sendable {
  /// List of reasons the password is too weak, could be any of `length`, `characters`, or `pwned`.
  public let reasons: [String]
}

struct DeleteUserRequest: Encodable {
  let shouldSoftDelete: Bool
}

/// The messaging channel used to deliver OTPs.
public enum MessagingChannel: String, Codable, Sendable {
  /// Deliver the OTP via SMS.
  case sms

  /// Deliver the OTP via WhatsApp.
  case whatsapp
}

struct SignInWithSSORequest: Encodable {
  let providerId: String?
  let domain: String?
  let redirectTo: URL?
  let gotrueMetaSecurity: AuthMetaSecurity?
  let codeChallenge: String?
  let codeChallengeMethod: String?
}

/// The response from a single sign-on (SSO) initiation request.
public struct SSOResponse: Codable, Hashable, Sendable {
  /// URL to open in a browser which will complete the sign-in flow by taking the user to the
  /// identity provider's authentication flow.
  public let url: URL
}

/// The URL and provider returned when building an OAuth sign-in URL.
public struct OAuthResponse: Codable, Hashable, Sendable {
  /// The OAuth provider.
  public let provider: Provider

  /// The URL to open in order to start the OAuth flow.
  public let url: URL
}

/// Pagination parameters for list endpoints.
public struct PageParams {
  /// The page number.
  public let page: Int?

  /// Number of items returned per page.
  public let perPage: Int?

  /// Creates pagination parameters.
  ///
  /// - Parameters:
  ///   - page: The page number (1-indexed).
  ///   - perPage: The number of items per page.
  public init(page: Int? = nil, perPage: Int? = nil) {
    self.page = page
    self.perPage = perPage
  }
}

/// A paginated list of users returned by ``AuthAdmin/listUsers(params:)``.
public struct ListUsersPaginatedResponse: Hashable, Sendable {
  /// The users on the current page.
  public let users: [User]

  /// The audience the users belong to.
  public let aud: String

  /// The page number of the next page, if one exists.
  public var nextPage: Int?

  /// The page number of the last page.
  public var lastPage: Int

  /// The total number of users matching the query.
  public var total: Int
}

//public struct GenerateLinkParams: Sendable {
//  struct Body: Encodable {
//    var type: GenerateLinkType
//    var email: String
//    var password: String?
//    var newEmail: String?
//    var data: [String: AnyJSON]?
//  }
//  var body: Body
//  var redirectTo: URL?
//
//  /// Generates a signup link.
//  public static func signUp(
//    email: String,
//    password: String,
//    data: [String: AnyJSON]? = nil,
//    redirectTo: URL? = nil
//  ) -> GenerateLinkParams {
//    GenerateLinkParams(
//      body: .init(
//        type: .signup,
//        email: email,
//        password: password,
//        data: data
//      ),
//      redirectTo: redirectTo
//    )
//  }
//
//  /// Generates an invite link.
//  public static func invite(
//    email: String,
//    data: [String: AnyJSON]? = nil,
//    redirectTo: URL? = nil
//  ) -> GenerateLinkParams {
//    GenerateLinkParams(
//      body: .init(
//        type: .invite,
//        email: email,
//        data: data
//      ),
//      redirectTo: redirectTo
//    )
//  }
//
//  /// Generates a magic link.
//  public static func magicLink(
//    email: String,
//    data: [String: AnyJSON]? = nil,
//    redirectTo: URL? = nil
//  ) -> GenerateLinkParams {
//    GenerateLinkParams(
//      body: .init(
//        type: .magiclink,
//        email: email,
//        data: data
//      ),
//      redirectTo: redirectTo
//    )
//  }
//
//  /// Generates a recovery link.
//  public static func recovery(
//    email: String,
//    redirectTo: URL? = nil
//  ) -> GenerateLinkParams {
//    GenerateLinkParams(
//      body: .init(
//        type: .recovery,
//        email: email
//      ),
//      redirectTo: redirectTo
//    )
//  }
//
//}
//
///// The response from the ``AuthAdmin/generateLink(params:)`` function.
//public struct GenerateLinkResponse: Hashable, Sendable, Decodable {
//  /// The properties related to the email link generated.
//  public let properties: GenerateLinkProperties
//  /// The user that the email link is associated to.
//  public let user: User
//
//  public init(from decoder: any Decoder) throws {
//    self.properties = try GenerateLinkProperties(from: decoder)
//    self.user = try User(from: decoder)
//  }
//}
//
///// The properties related to the email link generated.
//public struct GenerateLinkProperties: Decodable, Hashable, Sendable {
//  /// The email link to send to the users.
//  /// The action link follows the following format: auth/v1/verify?type={verification_type}&token={hashed_token}&redirect_to={redirect_to}
//  public let actionLink: URL
//  /// The raw email OTP.
//  /// You should send this in the email if you want your users to verify using an OTP instead of the action link.
//  public let emailOTP: String
//  /// The hashed token appended to the action link.
//  public let hashedToken: String
//  /// The URL appended to the action link.
//  public let redirectTo: URL
//  /// The verification type that the emaillink is associated to.
//  public let verificationType: GenerateLinkType
//}
//
//public struct GenerateLinkType: RawRepresentable, Codable, Hashable, Sendable {
//  public let rawValue: String
//
//  public init(rawValue: String) {
//    self.rawValue = rawValue
//  }
//
//  public static let signup = GenerateLinkType(rawValue: "signup")
//  public static let invite = GenerateLinkType(rawValue: "invite")
//  public static let magiclink = GenerateLinkType(rawValue: "magiclink")
//  public static let recovery = GenerateLinkType(rawValue: "recovery")
//  public static let emailChangeCurrent = GenerateLinkType(rawValue: "email_change_current")
//  public static let emailChangeNew = GenerateLinkType(rawValue: "email_change_new")
//}

// MARK: - OAuth Client Types

/// OAuth client grant types supported by the OAuth 2.1 server.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthClientGrantType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The raw string value of the grant type.
  public let rawValue: String

  /// Creates an ``OAuthClientGrantType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``OAuthClientGrantType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The `authorization_code` grant type.
  public static let authorizationCode: OAuthClientGrantType = "authorization_code"

  /// The `refresh_token` grant type.
  public static let refreshToken: OAuthClientGrantType = "refresh_token"
}

/// OAuth client response types supported by the OAuth 2.1 server.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthClientResponseType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The raw string value of the response type.
  public let rawValue: String

  /// Creates an ``OAuthClientResponseType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``OAuthClientResponseType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The `code` response type.
  public static let code: OAuthClientResponseType = "code"
}

/// OAuth client type indicating whether the client can keep credentials confidential.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthClientType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The raw string value of the client type.
  public let rawValue: String

  /// Creates an ``OAuthClientType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``OAuthClientType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// A public client that cannot keep credentials confidential (e.g. a browser or mobile app).
  public static let `public`: OAuthClientType = "public"

  /// A confidential client that can securely store credentials (e.g. a server-side app).
  public static let confidential: OAuthClientType = "confidential"
}

/// OAuth client registration type.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthClientRegistrationType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The raw string value of the registration type.
  public let rawValue: String

  /// Creates an ``OAuthClientRegistrationType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``OAuthClientRegistrationType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The client was registered using dynamic client registration.
  public static let dynamic: OAuthClientRegistrationType = "dynamic"

  /// The client was registered manually via the dashboard or admin API.
  public static let manual: OAuthClientRegistrationType = "manual"
}

/// OAuth client object returned from the OAuth 2.1 server.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthClient: Codable, Hashable, Sendable {
  /// Unique identifier for the OAuth client
  public let clientId: UUID

  /// Human-readable name of the OAuth client
  public let clientName: String

  /// Client secret (only returned on registration and regeneration)
  public let clientSecret: String?

  /// Type of OAuth client
  public let clientType: OAuthClientType

  /// Token endpoint authentication method
  public let tokenEndpointAuthMethod: String

  /// Registration type of the client
  public let registrationType: OAuthClientRegistrationType

  /// URI of the OAuth client
  public let clientUri: String?

  /// URL of the client application's logo
  public let logoUri: String?

  /// Array of allowed redirect URIs
  public let redirectUris: [String]

  /// Array of allowed grant types
  public let grantTypes: [OAuthClientGrantType]

  /// Array of allowed response types
  public let responseTypes: [OAuthClientResponseType]

  /// Scope of the OAuth client
  public let scope: String?

  /// Timestamp when the client was created
  public let createdAt: Date

  /// Timestamp when the client was last updated
  public let updatedAt: Date
}

/// Parameters for creating a new OAuth client.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct CreateOAuthClientParams: Encodable, Hashable, Sendable {
  /// Human-readable name of the OAuth client
  public let clientName: String

  /// URI of the OAuth client
  public let clientUri: String?

  /// Array of allowed redirect URIs
  public let redirectUris: [String]

  /// Array of allowed grant types (optional, defaults to authorization_code and refresh_token)
  public let grantTypes: [OAuthClientGrantType]?

  /// Array of allowed response types (optional, defaults to code)
  public let responseTypes: [OAuthClientResponseType]?

  /// Scope of the OAuth client
  public let scope: String?

  /// Creates parameters for a new OAuth client.
  ///
  /// - Parameters:
  ///   - clientName: Human-readable name for the client.
  ///   - clientUri: URI of the client application's homepage.
  ///   - redirectUris: Allowed redirect URIs.
  ///   - grantTypes: Allowed grant types; defaults to `authorization_code` and `refresh_token`.
  ///   - responseTypes: Allowed response types; defaults to `code`.
  ///   - scope: Requested scope.
  public init(
    clientName: String,
    clientUri: String? = nil,
    redirectUris: [String],
    grantTypes: [OAuthClientGrantType]? = nil,
    responseTypes: [OAuthClientResponseType]? = nil,
    scope: String? = nil
  ) {
    self.clientName = clientName
    self.clientUri = clientUri
    self.redirectUris = redirectUris
    self.grantTypes = grantTypes
    self.responseTypes = responseTypes
    self.scope = scope
  }
}

/// Parameters for updating an existing OAuth client.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct UpdateOAuthClientParams: Encodable, Hashable, Sendable {
  /// Human-readable name of the client application
  public let clientName: String?

  /// URL of the client application's homepage
  public let clientUri: String?

  /// URL of the client application's logo
  public let logoUri: String?

  /// Array of redirect URIs used by the client
  public let redirectUris: [String]?

  /// OAuth grant types the client is authorized to use
  public let grantTypes: [OAuthClientGrantType]?

  /// Creates parameters for updating an existing OAuth client.
  ///
  /// - Parameters:
  ///   - clientName: New human-readable name.
  ///   - clientUri: New URI for the client application.
  ///   - logoUri: New logo URI.
  ///   - redirectUris: Replacement list of redirect URIs.
  ///   - grantTypes: Replacement list of grant types.
  public init(
    clientName: String? = nil,
    clientUri: String? = nil,
    logoUri: String? = nil,
    redirectUris: [String]? = nil,
    grantTypes: [OAuthClientGrantType]? = nil
  ) {
    self.clientName = clientName
    self.clientUri = clientUri
    self.logoUri = logoUri
    self.redirectUris = redirectUris
    self.grantTypes = grantTypes
  }
}

/// A paginated list of OAuth clients returned by ``AuthAdminOAuth/listClients(params:)``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct ListOAuthClientsPaginatedResponse: Hashable, Sendable {
  /// The OAuth clients on the current page.
  public let clients: [OAuthClient]

  /// The audience the clients belong to.
  public let aud: String

  /// The page number of the next page, if one exists.
  public var nextPage: Int?

  /// The page number of the last page.
  public var lastPage: Int

  /// The total number of OAuth clients.
  public var total: Int
}

// MARK: - JWT Claims

/// JSON Web Key (JWK) representation.
public struct JWK: Codable, Hashable, Sendable {
  /// Key type (e.g., `"RSA"`, `"EC"`, `"oct"`).
  public let kty: String

  /// Key operations (e.g., `["sign", "verify"]`).
  public let keyOps: [String]?

  /// Algorithm (e.g., `"RS256"`, `"ES256"`, `"HS256"`).
  public let alg: String?

  /// Key ID.
  public let kid: String?

  // RSA-specific fields
  /// RSA modulus (base64url-encoded).
  public let n: String?

  /// RSA exponent (base64url-encoded).
  public let e: String?

  // EC-specific fields
  /// EC curve name (e.g., `"P-256"`).
  public let crv: String?

  /// EC x coordinate (base64url-encoded).
  public let x: String?

  /// EC y coordinate (base64url-encoded).
  public let y: String?

  // Symmetric key field
  /// Symmetric key value (base64url-encoded).
  public let k: String?

  enum CodingKeys: String, CodingKey {
    case kty
    case keyOps = "key_ops"
    case alg
    case kid
    case n
    case e
    case crv
    case x
    case y
    case k
  }
}

/// A JSON Web Key Set (JWKS) containing one or more JWKs.
public struct JWKS: Codable, Hashable, Sendable {
  /// The set of JSON Web Keys.
  public let keys: [JWK]
}

/// The header portion of a decoded JSON Web Token.
public struct JWTHeader: Codable, Hashable, Sendable {
  /// Algorithm (e.g., `"RS256"`, `"ES256"`, `"HS256"`).
  public let alg: String

  /// Key ID used to select the signing key.
  public let kid: String?

  /// Token type (typically `"JWT"`).
  public let typ: String?
}

/// The decoded claims from a JSON Web Token.
public struct JWTClaims: Codable, Hashable, Sendable {
  /// Issuer (`iss` claim).
  public let iss: String?

  /// Subject (`sub` claim) — typically the user's UUID.
  public let sub: String?

  /// Audience (`aud` claim) — can be a single string or an array of strings.
  public let aud: AudienceClaim?

  /// Expiration time (`exp` claim) as a UNIX timestamp.
  public let exp: TimeInterval?

  /// Issued-at time (`iat` claim) as a UNIX timestamp.
  public let iat: TimeInterval?

  /// Not-before time (`nbf` claim) as a UNIX timestamp.
  public let nbf: TimeInterval?

  /// JWT ID (`jti` claim).
  public let jti: String?

  /// Role claim.
  public let role: String?

  /// Authenticator Assurance Level (`aal` claim).
  public let aal: String?

  /// Session ID.
  public let sessionId: String?

  /// Email claim.
  public let email: String?

  /// Phone claim.
  public let phone: String?

  /// Application metadata.
  public let appMetadata: [String: AnyJSON]?

  /// User metadata.
  public let userMetadata: [String: AnyJSON]?

  /// Any claims not recognized by the standard set of ``CodingKeys``.
  public var additionalClaims: [String: AnyJSON] = [:]

  enum CodingKeys: String, CodingKey {
    case iss
    case sub
    case aud
    case exp
    case iat
    case nbf
    case jti
    case role
    case aal
    case sessionId = "session_id"
    case email
    case phone
    case appMetadata = "app_metadata"
    case userMetadata = "user_metadata"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    iss = try container.decodeIfPresent(String.self, forKey: .iss)
    sub = try container.decodeIfPresent(String.self, forKey: .sub)
    aud = try container.decodeIfPresent(AudienceClaim.self, forKey: .aud)
    exp = try container.decodeIfPresent(TimeInterval.self, forKey: .exp)
    iat = try container.decodeIfPresent(TimeInterval.self, forKey: .iat)
    nbf = try container.decodeIfPresent(TimeInterval.self, forKey: .nbf)
    jti = try container.decodeIfPresent(String.self, forKey: .jti)
    role = try container.decodeIfPresent(String.self, forKey: .role)
    aal = try container.decodeIfPresent(String.self, forKey: .aal)
    sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    phone = try container.decodeIfPresent(String.self, forKey: .phone)
    appMetadata = try container.decodeIfPresent([String: AnyJSON].self, forKey: .appMetadata)
    userMetadata = try container.decodeIfPresent([String: AnyJSON].self, forKey: .userMetadata)

    // Decode additional claims
    let allKeys = try decoder.container(keyedBy: AnyCodingKey.self)
    var additional: [String: AnyJSON] = [:]
    for key in allKeys.allKeys where CodingKeys(stringValue: key.stringValue) == nil {
      if let value = try? allKeys.decode(AnyJSON.self, forKey: key) {
        additional[key.stringValue] = value
      }
    }
    additionalClaims = additional
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(self.iss, forKey: .iss)
    try container.encodeIfPresent(self.sub, forKey: .sub)
    try container.encodeIfPresent(self.aud, forKey: .aud)
    try container.encodeIfPresent(self.exp, forKey: .exp)
    try container.encodeIfPresent(self.iat, forKey: .iat)
    try container.encodeIfPresent(self.nbf, forKey: .nbf)
    try container.encodeIfPresent(self.jti, forKey: .jti)
    try container.encodeIfPresent(self.role, forKey: .role)
    try container.encodeIfPresent(self.aal, forKey: .aal)
    try container.encodeIfPresent(self.sessionId, forKey: .sessionId)
    try container.encodeIfPresent(self.email, forKey: .email)
    try container.encodeIfPresent(self.phone, forKey: .phone)
    try container.encodeIfPresent(self.appMetadata, forKey: .appMetadata)
    try container.encodeIfPresent(self.userMetadata, forKey: .userMetadata)

    var additionalClaimsContainer = encoder.container(keyedBy: AnyCodingKey.self)
    for (key, value) in additionalClaims {
      try additionalClaimsContainer.encode(value, forKey: AnyCodingKey(stringValue: key)!)
    }
  }
}

/// A JWT `aud` (audience) claim that may be either a single string or an array of strings.
public enum AudienceClaim: Codable, Hashable, Sendable {
  /// A single audience string.
  case string(String)

  /// Multiple audience strings.
  case array([String])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([String].self) {
      self = .array(array)
    } else {
      throw DecodingError.typeMismatch(
        AudienceClaim.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Expected String or [String] for audience claim"
        )
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    }
  }
}

private struct AnyCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(intValue: Int) {
    stringValue = "\(intValue)"
    self.intValue = intValue
  }
}

/// The result returned by ``AuthClient/getClaims(jwt:options:)``.
public struct JWTClaimsResponse: Sendable {
  /// The decoded JWT claims.
  public let claims: JWTClaims

  /// The decoded JWT header.
  public let header: JWTHeader

  /// The raw JWT signature bytes.
  public let signature: Data
}

/// Options for ``AuthClient/getClaims(jwt:options:)``.
public struct GetClaimsOptions: Sendable {
  /// When `true`, the `exp` claim is not validated against the current time, allowing expired tokens to be decoded.
  public let allowExpired: Bool

  /// When set, this JSON Web Key Set takes precedence over any cached JWKS from the server.
  public let jwks: JWKS?

  /// Creates claim-decoding options.
  ///
  /// - Parameters:
  ///   - allowExpired: Pass `true` to skip expiration validation.
  ///   - jwks: An explicit JWKS to use instead of the cached server JWKS.
  public init(allowExpired: Bool = false, jwks: JWKS? = nil) {
    self.allowExpired = allowExpired
    self.jwks = jwks
  }
}
