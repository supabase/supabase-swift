public import Foundation

/// An event emitted when the authentication state of the current user changes.
///
/// The name that the next major version uses for ``AuthChangeEvent``.
public typealias AuthEvent = AuthChangeEvent

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
  @available(*, deprecated, message: "The client never emits this event.")
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
  @available(*, deprecated, message: "Use isExpired(at:leeway:) instead.")
  public var isExpired: Bool {
    let expiresAt = Date(timeIntervalSince1970: expiresAt)
    return expiresAt.timeIntervalSinceNow < defaultExpiryMargin
  }

  /// Whether the access token is expired at `date`, or expires within `leeway` after it.
  ///
  /// The leeway accounts for network latency. The expiry is ``expiresAt``.
  ///
  /// - Parameters:
  ///   - date: The time to judge the session at. Defaults to now.
  ///   - leeway: How long before the expiry the session counts as expired. Defaults to 30 seconds.
  /// - Returns: `true` when less than `leeway` of the session's lifetime remains at `date`.
  public func isExpired(at date: Date = .now, leeway: Duration = .seconds(30)) -> Bool {
    let remaining = Date(timeIntervalSince1970: expiresAt).timeIntervalSince(date)
    let (seconds, attoseconds) = leeway.components
    return remaining < TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
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
  public var audience: String

  /// The audience claim (`aud`) of the user's JWT.
  @available(*, deprecated, message: "Use audience instead.")
  public var aud: String {
    get { audience }
    set { audience = newValue }
  }

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
    self.audience = aud
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

  enum CodingKeys: String, CodingKey {
    case id
    case appMetadata
    case userMetadata
    case audience = "aud"
    case confirmationSentAt
    case recoverySentAt
    case emailChangeSentAt
    case newEmail
    case invitedAt
    case actionLink
    case email
    case phone
    case createdAt
    case confirmedAt
    case emailConfirmedAt
    case phoneConfirmedAt
    case lastSignInAt
    case role
    case updatedAt
    case identities
    case isAnonymous
    case factors
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    appMetadata = try container.decodeIfPresent([String: AnyJSON].self, forKey: .appMetadata) ?? [:]
    userMetadata =
      try container.decodeIfPresent([String: AnyJSON].self, forKey: .userMetadata) ?? [:]
    audience = try container.decode(String.self, forKey: .audience)
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
  public var userID: UUID

  /// The user this identity belongs to.
  @available(*, deprecated, message: "Use userID instead.")
  public var userId: UUID {
    get { userID }
    set { userID = newValue }
  }

  /// The ID the provider gives this user, such as the `sub` of an OAuth identity. The same
  /// value as ``id``.
  public var providerUserID: String {
    get { id }
    set { id = newValue }
  }

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
    self.userID = userId
    self.identityData = identityData
    self.provider = provider
    self.createdAt = createdAt
    self.lastSignInAt = lastSignInAt
    self.updatedAt = updatedAt
  }

  enum CodingKeys: String, CodingKey {
    case id
    case identityId
    case userID = "userId"
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
    userID = try container.decode(UUID.self, forKey: .userID)
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
    try container.encode(userID, forKey: .userID)
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

/// An ID token from a third-party identity provider, and the values the server needs to check
/// it, for ``AuthClient/signInWithIDToken(_:)`` and ``AuthClient/linkIdentity(idToken:)``.
///
/// When the provider takes a nonce, pass the hashed nonce to the provider and the raw nonce
/// here. The server hashes `nonce` and compares the result with the token's `nonce` claim.
public struct IDTokenCredentials: Sendable, Hashable {
  /// The provider that issued the token, such as ``Provider/apple`` or ``Provider/google``.
  public var provider: Provider

  /// The ID token the provider issued. Its `iss` claim must match ``provider``.
  public var idToken: String

  /// The raw nonce used to request the token. Required when the token has a `nonce` claim.
  public var nonce: String?

  /// The provider's access token. Required when the token has an `at_hash` claim.
  public var accessToken: String?

  /// The token the user received for completing a captcha.
  public var captchaToken: String?

  /// Creates ID token credentials.
  ///
  /// - Parameters:
  ///   - provider: The provider that issued the token.
  ///   - idToken: The ID token the provider issued.
  ///   - nonce: The raw nonce used to request the token.
  ///   - accessToken: The provider's access token.
  ///   - captchaToken: The token the user received for completing a captcha.
  public init(
    provider: Provider,
    idToken: String,
    nonce: String? = nil,
    accessToken: String? = nil,
    captchaToken: String? = nil
  ) {
    self.provider = provider
    self.idToken = idToken
    self.nonce = nonce
    self.accessToken = accessToken
    self.captchaToken = captchaToken
  }
}

struct IDTokenGrantBody: Encodable {
  var provider: String
  var idToken: String
  var accessToken: String?
  var nonce: String?
  var gotrueMetaSecurity: AuthMetaSecurity?
  var linkIdentity: Bool

  init(_ credentials: IDTokenCredentials, linkIdentity: Bool = false) {
    provider = credentials.provider.rawValue
    idToken = credentials.idToken
    accessToken = credentials.accessToken
    nonce = credentials.nonce
    gotrueMetaSecurity = credentials.captchaToken.map(AuthMetaSecurity.init(captchaToken:))
    self.linkIdentity = linkIdentity
  }
}

/// Credentials for signing in with an OpenID Connect (OIDC) ID token issued by a third-party.
@available(*, deprecated, message: "Use IDTokenCredentials instead.")
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

/// A Web3 chain supported by Sign in with Web3.
public struct Web3Chain: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  /// Creates a ``Web3Chain`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``Web3Chain`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The Ethereum chain, authenticated via Sign in with Ethereum (EIP-4361).
  public static let ethereum: Web3Chain = "ethereum"

  /// The Solana chain, authenticated via Sign in with Solana.
  public static let solana: Web3Chain = "solana"
}

/// Credentials for signing in with a Web3 wallet (Sign in with Ethereum / Sign in with Solana).
///
/// The caller is responsible for constructing a spec-compliant SIWE (EIP-4361) or SIWS message and
/// obtaining a signature over it from the user's wallet (e.g. via WalletConnect or a native wallet
/// SDK) — this type only carries the already-signed result to the server for verification.
public struct Web3Credentials: Codable, Hashable, Sendable {
  public var chain: Web3Chain

  /// The SIWE- or SIWS-formatted message that was signed.
  public var message: String

  /// The signature over `message`.
  /// - Ethereum: `0x`-prefixed 65-byte secp256k1 signature, hex-encoded (130 hex chars after `0x`).
  /// - Solana: base64 (standard or URL-safe, padded or not) encoding of the 64-byte Ed25519 signature.
  public var signature: String

  /// Verification token received when the user completes the captcha on the site.
  public var gotrueMetaSecurity: AuthMetaSecurity?

  /// Creates Web3 credentials for sign-in.
  ///
  /// - Parameters:
  ///   - chain: The Web3 chain the message was signed for.
  ///   - message: The SIWE/SIWS-formatted message that was signed.
  ///   - signature: The signature over `message`.
  ///   - captchaToken: Optional captcha verification token.
  public init(
    chain: Web3Chain,
    message: String,
    signature: String,
    captchaToken: String? = nil
  ) {
    self.chain = chain
    self.message = message
    self.signature = signature
    self.gotrueMetaSecurity = captchaToken.map(AuthMetaSecurity.init(captchaToken:))
  }

  /// The token the user received for completing a captcha. The same value as
  /// ``gotrueMetaSecurity``.
  public var captchaToken: String? {
    get { gotrueMetaSecurity?.captchaToken }
    set { gotrueMetaSecurity = newValue.map(AuthMetaSecurity.init(captchaToken:)) }
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

/// The OTP type used when verifying a phone (SMS/WhatsApp) one-time password.
///
/// The name that the next major version uses for ``MobileOTPType``.
public typealias PhoneOTPType = MobileOTPType

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

/// The changes a user can make to their own account, for ``AuthClient/updateUser(_:redirectTo:)``.
public struct UpdateUser: Encodable, Hashable, Sendable {
  /// The user's email.
  public var email: String?

  /// The user's phone.
  public var phone: String?

  /// The user's password.
  public var password: String?

  /// The user's current password.
  ///
  /// Set it with ``password`` when the project requires the current password to change the
  /// password.
  public var currentPassword: String?

  /// The nonce sent for reauthentication if the user's password is to be updated.
  ///
  /// > Note: Call ``AuthClient/reauthenticate()`` to obtain the nonce first.
  public var nonce: String?

  /// Data to merge into the user's metadata, in the `auth.users.raw_user_meta_data` column. The
  /// user can change it, so do not use it for authorization.
  public var userMetadata: JSONObject?

  var codeChallenge: String?
  var codeChallengeMethod: String?

  private enum CodingKeys: String, CodingKey {
    case email
    case phone
    case password
    case currentPassword = "current_password"
    case nonce
    case codeChallenge = "code_challenge"
    case codeChallengeMethod = "code_challenge_method"
    case userMetadata = "data"
  }

  /// Creates the changes for ``AuthClient/updateUser(_:redirectTo:)``.
  ///
  /// - Parameters:
  ///   - email: New email address.
  ///   - phone: New phone number.
  ///   - password: New password.
  ///   - currentPassword: Current password, required when the project requires it to change the
  ///     password.
  ///   - nonce: Reauthentication nonce, required when updating the password.
  ///   - userMetadata: Data to merge into the user's metadata.
  public init(
    email: String? = nil,
    phone: String? = nil,
    password: String? = nil,
    currentPassword: String? = nil,
    nonce: String? = nil,
    userMetadata: JSONObject? = nil
  ) {
    self.email = email
    self.phone = phone
    self.password = password
    self.currentPassword = currentPassword
    self.nonce = nonce
    self.userMetadata = userMetadata
  }
}

/// Options for ``AuthClient/resetPassword(email:options:)``.
public struct ResetPasswordOptions: Sendable, Hashable {
  /// The URL the link redirects to. When `nil`, the client uses
  /// ``AuthClient/Configuration/redirectToURL``.
  public var redirectTo: URL?

  /// The captcha verification token.
  public var captchaToken: String?

  /// Creates password reset options.
  ///
  /// - Parameters:
  ///   - redirectTo: The URL the link redirects to.
  ///   - captchaToken: The captcha verification token.
  public init(redirectTo: URL? = nil, captchaToken: String? = nil) {
    self.redirectTo = redirectTo
    self.captchaToken = captchaToken
  }
}

/// Attributes that a user can update for their own account.
@available(*, deprecated, message: "Use UpdateUser instead.")
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

/// The new user for ``AuthAdmin/createUser(_:)``.
public struct AdminCreateUser: Encodable, Hashable, Sendable {
  /// The user's ID. `nil` lets the server pick one.
  public var id: UUID?

  /// The user's email.
  public var email: String?

  /// The user's phone.
  public var phone: String?

  /// The user's password. Leave it `nil` with ``passwordHash`` to import a hashed password.
  public var password: String?

  /// A password hash to import, in bcrypt or Argon2 format. Do not set it with ``password``.
  public var passwordHash: String?

  /// Confirms the user's email address if set to `true`.
  public var confirmsEmail: Bool?

  /// Confirms the user's phone number if set to `true`.
  public var confirmsPhone: Bool?

  /// The role claim set in the user's access token JWT.
  public var role: String?

  /// Data for the user's metadata, in the `auth.users.raw_user_meta_data` column. The user can
  /// change it, so do not use it for authorization.
  public var userMetadata: JSONObject?

  /// Data for the user's application metadata, in the `auth.users.raw_app_meta_data` column.
  public var appMetadata: JSONObject?

  /// How long to ban the user, counted from the time of the request.
  public var banDuration: Duration?

  private enum CodingKeys: String, CodingKey {
    case id
    case email
    case phone
    case password
    case passwordHash = "password_hash"
    case confirmsEmail = "email_confirm"
    case confirmsPhone = "phone_confirm"
    case role
    case userMetadata = "user_metadata"
    case appMetadata = "app_metadata"
    case banDuration = "ban_duration"
  }

  /// Creates the new user for ``AuthAdmin/createUser(_:)``.
  ///
  /// - Parameters:
  ///   - id: The user's ID. `nil` lets the server pick one.
  ///   - email: The user's email address.
  ///   - phone: The user's phone number.
  ///   - password: Plain-text password.
  ///   - passwordHash: Pre-hashed password to import.
  ///   - confirmsEmail: Whether to mark the email as confirmed.
  ///   - confirmsPhone: Whether to mark the phone as confirmed.
  ///   - role: The JWT role claim.
  ///   - userMetadata: User-supplied metadata.
  ///   - appMetadata: Application-level metadata.
  ///   - banDuration: How long to ban the user.
  public init(
    id: UUID? = nil,
    email: String? = nil,
    phone: String? = nil,
    password: String? = nil,
    passwordHash: String? = nil,
    confirmsEmail: Bool? = nil,
    confirmsPhone: Bool? = nil,
    role: String? = nil,
    userMetadata: JSONObject? = nil,
    appMetadata: JSONObject? = nil,
    banDuration: Duration? = nil
  ) {
    self.id = id
    self.email = email
    self.phone = phone
    self.password = password
    self.passwordHash = passwordHash
    self.confirmsEmail = confirmsEmail
    self.confirmsPhone = confirmsPhone
    self.role = role
    self.userMetadata = userMetadata
    self.appMetadata = appMetadata
    self.banDuration = banDuration
  }

  /// Encodes the fields that are set. Writes ``banDuration`` in the format the server reads.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encodeIfPresent(email, forKey: .email)
    try container.encodeIfPresent(phone, forKey: .phone)
    try container.encodeIfPresent(password, forKey: .password)
    try container.encodeIfPresent(passwordHash, forKey: .passwordHash)
    try container.encodeIfPresent(confirmsEmail, forKey: .confirmsEmail)
    try container.encodeIfPresent(confirmsPhone, forKey: .confirmsPhone)
    try container.encodeIfPresent(role, forKey: .role)
    try container.encodeIfPresent(userMetadata, forKey: .userMetadata)
    try container.encodeIfPresent(appMetadata, forKey: .appMetadata)
    try container.encodeIfPresent(banDuration?.goBanDurationString, forKey: .banDuration)
  }
}

/// The changes for ``AuthAdmin/updateUser(id:_:)``. The server changes only the fields
/// you set.
public struct AdminUpdateUser: Encodable, Hashable, Sendable {
  /// The user's new email.
  public var email: String?

  /// The user's new phone.
  public var phone: String?

  /// The user's new password.
  public var password: String?

  /// Confirms the user's email address if set to `true`.
  public var confirmsEmail: Bool?

  /// Confirms the user's phone number if set to `true`.
  public var confirmsPhone: Bool?

  /// The role claim set in the user's access token JWT.
  public var role: String?

  /// Data to merge into the user's metadata, in the `auth.users.raw_user_meta_data` column. The
  /// user can change it, so do not use it for authorization.
  public var userMetadata: JSONObject?

  /// Data to merge into the user's application metadata, in the `auth.users.raw_app_meta_data`
  /// column.
  public var appMetadata: JSONObject?

  /// How long to ban the user, counted from the time of the request.
  ///
  /// Pass `.zero` to lift an existing ban. `nil` leaves the ban as it is.
  public var banDuration: Duration?

  private enum CodingKeys: String, CodingKey {
    case email
    case phone
    case password
    case confirmsEmail = "email_confirm"
    case confirmsPhone = "phone_confirm"
    case role
    case userMetadata = "user_metadata"
    case appMetadata = "app_metadata"
    case banDuration = "ban_duration"
  }

  /// Creates the changes for ``AuthAdmin/updateUser(id:_:)``.
  ///
  /// - Parameters:
  ///   - email: The user's new email address.
  ///   - phone: The user's new phone number.
  ///   - password: The new plain-text password.
  ///   - confirmsEmail: Whether to mark the email as confirmed.
  ///   - confirmsPhone: Whether to mark the phone as confirmed.
  ///   - role: The JWT role claim.
  ///   - userMetadata: User-supplied metadata to merge.
  ///   - appMetadata: Application-level metadata to merge.
  ///   - banDuration: How long to ban the user. Pass `.zero` to lift a ban.
  public init(
    email: String? = nil,
    phone: String? = nil,
    password: String? = nil,
    confirmsEmail: Bool? = nil,
    confirmsPhone: Bool? = nil,
    role: String? = nil,
    userMetadata: JSONObject? = nil,
    appMetadata: JSONObject? = nil,
    banDuration: Duration? = nil
  ) {
    self.email = email
    self.phone = phone
    self.password = password
    self.confirmsEmail = confirmsEmail
    self.confirmsPhone = confirmsPhone
    self.role = role
    self.userMetadata = userMetadata
    self.appMetadata = appMetadata
    self.banDuration = banDuration
  }

  /// Encodes the fields that are set. Writes ``banDuration`` in the format the server reads.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(email, forKey: .email)
    try container.encodeIfPresent(phone, forKey: .phone)
    try container.encodeIfPresent(password, forKey: .password)
    try container.encodeIfPresent(confirmsEmail, forKey: .confirmsEmail)
    try container.encodeIfPresent(confirmsPhone, forKey: .confirmsPhone)
    try container.encodeIfPresent(role, forKey: .role)
    try container.encodeIfPresent(userMetadata, forKey: .userMetadata)
    try container.encodeIfPresent(appMetadata, forKey: .appMetadata)
    try container.encodeIfPresent(banDuration?.goBanDurationString, forKey: .banDuration)
  }
}

extension Duration {
  /// The ban duration in the format the server reads: `"none"` lifts a ban, any other value is a
  /// Go duration.
  fileprivate var goBanDurationString: String {
    self == .zero ? "none" : goDurationString
  }
}

extension Duration {
  /// The duration in the format of Go's `time.ParseDuration`.
  var goDurationString: String {
    let (seconds, attoseconds) = components
    let (scaled, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
    if attoseconds == 0, !overflow { return "\(seconds)s" }
    let (sum, sumOverflow) = scaled.addingReportingOverflow(attoseconds / 1_000_000_000)
    // Go's Duration is an Int64 count of nanoseconds, and ParseDuration rejects a larger value,
    // so a longer duration saturates at about 292 years.
    var nanoseconds = overflow || sumOverflow ? (self > .zero ? Int64.max : Int64.min) : sum
    // A non-zero duration under 1 ns must not become 0, which GoTrue reads as "no ban".
    if nanoseconds == 0 { nanoseconds = self > .zero ? 1 : -1 }
    return "\(nanoseconds)ns"
  }
}

/// Attributes that an administrator can set when creating or updating a user.
@available(*, deprecated, message: "Use AdminCreateUser or AdminUpdateUser instead.")
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
  public var id: String

  /// Friendly name of the factor, useful to disambiguate between multiple factors.
  public var friendlyName: String?

  /// Type of factor. `totp` and `phone` supported with this version.
  public var factorType: FactorType

  /// Factor's status.
  public var status: FactorStatus

  /// Timestamp when the factor was created.
  public var createdAt: Date

  /// Timestamp when the factor was last updated.
  public var updatedAt: Date
}

/// The protocol that MFA enrollment parameter types must conform to.
public protocol MFAEnrollParamsType: Encodable, Hashable, Sendable {
  /// The factor type identifier (e.g. `"totp"`, `"phone"`, `"webauthn"`).
  var factorType: FactorType { get }
}

/// Parameters for enrolling a TOTP (Time-based One-Time Password) MFA factor.
@available(
  *, deprecated,
  message:
    "Use AuthMFA.enrollTOTP(issuer:friendlyName:) or AuthMFA.enrollPhone(_:friendlyName:) instead."
)
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

@available(
  *, deprecated,
  message:
    "Use AuthMFA.enrollTOTP(issuer:friendlyName:) or AuthMFA.enrollPhone(_:friendlyName:) instead."
)
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
@available(
  *, deprecated,
  message:
    "Use AuthMFA.enrollTOTP(issuer:friendlyName:) or AuthMFA.enrollPhone(_:friendlyName:) instead."
)
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

@available(
  *, deprecated,
  message:
    "Use AuthMFA.enrollTOTP(issuer:friendlyName:) or AuthMFA.enrollPhone(_:friendlyName:) instead."
)
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
@available(*, deprecated, message: "Use AuthMFA.unenroll(factorID:) instead.")
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
@available(*, deprecated, message: "Use AuthMFA.challengeAndVerify(factorID:code:) instead.")
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
@available(*, deprecated, message: "Use Session instead.")
public typealias AuthMFAVerifyResponse = Session

/// The response returned after successfully unenrolling an MFA factor.
public struct AuthMFAUnenrollResponse: Decodable, Hashable, Sendable {
  /// ID of the factor that was successfully unenrolled.
  public let id: String
}

/// The response returned by ``AuthMFA/listFactors()``.
@available(*, deprecated, message: "Use MFAFactors instead.")
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

/// A TOTP factor created by ``AuthMFA/enrollTOTP(issuer:friendlyName:)``.
///
/// The factor is `unverified` until the user enters a code from their authenticator app in
/// ``AuthMFA/challengeAndVerify(factorID:code:)``.
public struct TOTPEnrollment: Identifiable, Hashable, Sendable {
  /// ID of the new factor.
  public var id: UUID

  /// Friendly name of the factor, useful to tell several factors apart.
  public var friendlyName: String?

  /// A QR code that encodes ``uri``, as an SVG document. Display it by prefixing
  /// `data:image/svg+xml;utf-8,`. Avoid logging this value.
  public var qrCode: String

  /// The TOTP secret, also encoded in the QR code. Show it in a password-style field for users who
  /// cannot scan the QR code. Avoid logging this value.
  public var secret: String

  /// The `otpauth://` URI encoded in the QR code. Avoid logging this value.
  public var uri: String

  /// Creates a ``TOTPEnrollment``.
  public init(
    id: UUID,
    friendlyName: String? = nil,
    qrCode: String,
    secret: String,
    uri: String
  ) {
    self.id = id
    self.friendlyName = friendlyName
    self.qrCode = qrCode
    self.secret = secret
    self.uri = uri
  }
}

extension TOTPEnrollment: Decodable {
  // Camel case names: the client's decoder converts snake case keys before it matches them.
  private enum CodingKeys: String, CodingKey {
    case id
    case friendlyName
    case totp
  }

  private struct TOTP: Decodable {
    let qrCode: String
    let secret: String
    let uri: String
  }

  /// Decodes an enrollment. Reads the QR code, the secret, and the URI from the nested `totp`
  /// object.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let totp = try container.decode(TOTP.self, forKey: .totp)
    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      friendlyName: try container.decodeIfPresent(String.self, forKey: .friendlyName),
      qrCode: totp.qrCode,
      secret: totp.secret,
      uri: totp.uri
    )
  }
}

/// A phone factor created by ``AuthMFA/enrollPhone(_:friendlyName:)``.
///
/// The factor is `unverified` until the user enters the code from
/// ``AuthMFA/challenge(factorID:channel:)`` in ``AuthMFA/verify(factorID:challengeID:code:)``.
public struct PhoneEnrollment: Identifiable, Decodable, Hashable, Sendable {
  /// ID of the new factor.
  public var id: UUID

  /// Friendly name of the factor, useful to tell several factors apart.
  public var friendlyName: String?

  /// The phone number of the factor, in E.164 format.
  public var phone: String

  /// Creates a ``PhoneEnrollment``.
  public init(
    id: UUID,
    friendlyName: String? = nil,
    phone: String
  ) {
    self.id = id
    self.friendlyName = friendlyName
    self.phone = phone
  }
}

/// A challenge created by ``AuthMFA/challenge(factorID:channel:)``.
public struct MFAChallenge: Identifiable, Hashable, Sendable {
  /// ID of the challenge. Pass it to ``AuthMFA/verify(factorID:challengeID:code:)``.
  public var id: UUID

  /// The type of the factor that was challenged.
  public var factorType: FactorType

  /// The time after which the challenge can no longer be verified.
  public var expiresAt: Date

  /// Creates a ``MFAChallenge``.
  public init(
    id: UUID,
    factorType: FactorType,
    expiresAt: Date
  ) {
    self.id = id
    self.factorType = factorType
    self.expiresAt = expiresAt
  }
}

extension MFAChallenge: Decodable {
  private enum CodingKeys: String, CodingKey {
    case id
    case type
    case expiresAt
  }

  /// Decodes a challenge. Reads ``factorType`` from `type` and `expires_at` as a Unix timestamp.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      factorType: try container.decode(FactorType.self, forKey: .type),
      expiresAt: Date(
        timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .expiresAt))
    )
  }
}

/// The user's MFA factors, returned by ``AuthMFA/factors()``.
public struct MFAFactors: Hashable, Sendable {
  /// Factors the user has verified. Only these count toward reaching `aal2`.
  public var verified: [Factor]

  /// Factors the user has enrolled but not verified yet.
  public var unverified: [Factor]

  /// Creates a ``MFAFactors``.
  public init(
    verified: [Factor],
    unverified: [Factor]
  ) {
    self.verified = verified
    self.unverified = unverified
  }

  /// Every factor: ``verified`` first, then ``unverified``.
  public var all: [Factor] { verified + unverified }
}

extension MFAFactors {
  /// Splits `factors` by status. A status other than ``FactorStatus/verified`` counts as
  /// unverified, because only a verified factor can raise the assurance level.
  init(_ factors: [Factor]) {
    self.init(
      verified: factors.filter { $0.status == .verified },
      unverified: factors.filter { $0.status != .verified }
    )
  }
}

/// The assurance level of the current session, returned by ``AuthMFA/assuranceLevel()``.
public struct AssuranceLevelInfo: Hashable, Sendable {
  /// The assurance level of the current access token. `nil` when the token has no `aal` claim.
  public var currentLevel: AuthenticatorAssuranceLevel?

  /// The highest level the user can reach. When it is above ``currentLevel``, ask the user to
  /// verify a factor.
  public var nextLevel: AuthenticatorAssuranceLevel?

  /// The methods attached to the session. Use them to find when the user last verified a factor,
  /// for example in a step-up flow.
  public var currentAuthenticationMethods: [AMREntry]

  /// Creates an ``AssuranceLevelInfo``.
  public init(
    currentLevel: AuthenticatorAssuranceLevel? = nil,
    nextLevel: AuthenticatorAssuranceLevel? = nil,
    currentAuthenticationMethods: [AMREntry]
  ) {
    self.currentLevel = currentLevel
    self.nextLevel = nextLevel
    self.currentAuthenticationMethods = currentAuthenticationMethods
  }
}

/// A string representing an Authenticator Assurance Level (`aal1` or `aal2`).
@available(*, deprecated, message: "Use AuthenticatorAssuranceLevel instead.")
public typealias AuthenticatorAssuranceLevels = String

/// An Authenticator Assurance Level (AAL), the `aal` claim of an access token.
public struct AuthenticatorAssuranceLevel: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The level as the `aal` claim holds it, such as `"aal1"`.
  public let rawValue: String

  /// Creates an ``AuthenticatorAssuranceLevel`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``AuthenticatorAssuranceLevel`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The user proved one factor, such as a password, a one-time code, or an OAuth sign-in.
  public static let aal1: AuthenticatorAssuranceLevel = "aal1"
  /// The user also verified a second factor.
  public static let aal2: AuthenticatorAssuranceLevel = "aal2"
}

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
@available(*, deprecated, message: "Use AssuranceLevelInfo instead.")
public struct AuthMFAGetAuthenticatorAssuranceLevelResponse: Decodable, Hashable, Sendable {
  /// Current AAL level of the session.
  public let currentLevel: String?

  /// Next possible AAL level for the session. If the next level is higher than the current one, the
  /// user should go through MFA.
  public let nextLevel: String?

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
  let codeChallenge: String?
  let codeChallengeMethod: String?
}

/// The type of phone OTP to resend.
///
/// The name that the next major version uses for ``ResendMobileType``.
public typealias ResendPhoneType = ResendMobileType

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

/// Options for ``AuthClient/signInWithOTP(email:options:)``.
public struct EmailOTPOptions: Sendable, Hashable {
  /// Whether the server creates a user when none exists for the email. The default is `true`.
  /// When `false`, the call fails for an unknown user.
  public var shouldCreateUser: Bool

  /// Data to store on the user if the call creates one.
  public var userMetadata: JSONObject

  /// The URL the email link redirects to. When `nil`, the client uses
  /// ``AuthClient/Configuration/redirectToURL``.
  public var redirectTo: URL?

  /// The captcha verification token.
  public var captchaToken: String?

  /// Creates email OTP options.
  ///
  /// - Parameters:
  ///   - shouldCreateUser: Whether the server creates a user when none exists.
  ///   - userMetadata: Data to store on the user if the call creates one.
  ///   - redirectTo: The URL the email link redirects to.
  ///   - captchaToken: The captcha verification token.
  public init(
    shouldCreateUser: Bool = true,
    userMetadata: JSONObject = [:],
    redirectTo: URL? = nil,
    captchaToken: String? = nil
  ) {
    self.shouldCreateUser = shouldCreateUser
    self.userMetadata = userMetadata
    self.redirectTo = redirectTo
    self.captchaToken = captchaToken
  }
}

/// Options for ``AuthClient/signInWithOTP(phone:options:)``.
public struct PhoneOTPOptions: Sendable, Hashable {
  /// Whether the server creates a user when none exists for the phone number. The default is
  /// `true`. When `false`, the call fails for an unknown user.
  public var shouldCreateUser: Bool

  /// Data to store on the user if the call creates one.
  public var userMetadata: JSONObject

  /// The channel that delivers the code. The default is ``MessagingChannel/sms``.
  ///
  /// - Note: The ``MessagingChannel/whatsapp`` channel needs a WhatsApp sender on Twilio.
  public var channel: MessagingChannel

  /// The captcha verification token.
  public var captchaToken: String?

  /// Creates phone OTP options.
  ///
  /// - Parameters:
  ///   - shouldCreateUser: Whether the server creates a user when none exists.
  ///   - userMetadata: Data to store on the user if the call creates one.
  ///   - channel: The channel that delivers the code.
  ///   - captchaToken: The captcha verification token.
  public init(
    shouldCreateUser: Bool = true,
    userMetadata: JSONObject = [:],
    channel: MessagingChannel = .sms,
    captchaToken: String? = nil
  ) {
    self.shouldCreateUser = shouldCreateUser
    self.userMetadata = userMetadata
    self.channel = channel
    self.captchaToken = captchaToken
  }
}

/// The ID that the SMS provider gave a message. Use it to track delivery problems.
public struct MessageID: RawRepresentable, Decodable, Hashable, Sendable {
  /// The ID as the SMS provider wrote it.
  public let rawValue: String

  /// Creates a ``MessageID`` from the provider's ID.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

/// The result of ``AuthClient/signUp(email:password:options:)`` and
/// ``AuthClient/signUp(phone:password:options:)``.
///
/// Switch on the result to learn whether the user is signed in:
///
/// ```swift
/// switch try await client.auth.signUp(email: email, password: password, options: .init()) {
/// case .signedIn(let session):
///   showHome(for: session.user)
/// case .confirmationRequired(let user):
///   showCheckYourInbox(for: user)
/// }
/// ```
public enum SignUpResult: Decodable, Hashable, Sendable {
  /// The account is active and the user is signed in. The client stored the session and emitted
  /// ``AuthChangeEvent/signedIn``.
  case signedIn(Session)

  /// The server sent a confirmation email or SMS. The user is not signed in until they confirm.
  ///
  /// When email confirmation is on and the email or phone number already belongs to a confirmed
  /// account, the server does not say so. It returns a fake user with an empty `identities`
  /// list instead, and sends no message. A real new user has one identity. The SDK returns
  /// either user as is.
  case confirmationRequired(User)

  /// Decodes ``signedIn(_:)`` from a session body, and ``confirmationRequired(_:)`` from a user
  /// body.
  public init(from decoder: any Decoder) throws {
    self.init(try AuthResponse(from: decoder))
  }

  init(_ response: AuthResponse) {
    switch response {
    case .session(let session): self = .signedIn(session)
    case .user(let user): self = .confirmationRequired(user)
    }
  }

  /// The user in either case.
  public var user: User {
    switch self {
    case .signedIn(let session): session.user
    case .confirmationRequired(let user): user
    }
  }

  /// The session, or `nil` when the user must confirm first.
  public var session: Session? {
    if case .signedIn(let session) = self { return session }
    return nil
  }
}

/// Options for ``AuthClient/signUp(email:password:options:)`` and
/// ``AuthClient/signUp(phone:password:options:)``.
public struct SignUpOptions: Sendable, Hashable {
  /// Data to store on the user, in the `auth.users.raw_user_meta_data` column. The user can
  /// change it later, so do not use it for authorization.
  public var userMetadata: JSONObject

  /// The URL the confirmation link sends the user to. Applies to email sign-up only. When `nil`,
  /// the client uses ``AuthClient/Configuration/redirectToURL``.
  public var redirectTo: URL?

  /// The channel that delivers the confirmation code. Applies to phone sign-up only.
  public var channel: MessagingChannel

  /// The token the user received for completing a captcha.
  public var captchaToken: String?

  /// Creates sign-up options.
  ///
  /// - Parameters:
  ///   - userMetadata: Data to store on the user.
  ///   - redirectTo: The URL the confirmation link sends the user to. Email sign-up only.
  ///   - channel: The channel that delivers the confirmation code. Phone sign-up only.
  ///   - captchaToken: The token the user received for completing a captcha.
  public init(
    userMetadata: JSONObject = [:],
    redirectTo: URL? = nil,
    channel: MessagingChannel = .sms,
    captchaToken: String? = nil
  ) {
    self.userMetadata = userMetadata
    self.redirectTo = redirectTo
    self.channel = channel
    self.captchaToken = captchaToken
  }
}

/// The result of ``AuthClient/verifyOTP(email:token:type:)``.
///
/// ```swift
/// let result: VerifyOTPResult = try await client.auth.verifyOTP(
///   email: email, token: code, type: .email)
/// switch result {
/// case .signedIn(let session):
///   showHome(for: session.user)
/// case .emailChangePending(let message):
///   showMessage(message)
/// }
/// ```
public enum VerifyOTPResult: Sendable, Hashable {
  /// The code was valid and the user is signed in. The client stored the session and emitted
  /// ``AuthChangeEvent/signedIn``.
  case signedIn(Session)

  /// The first of the two confirmations of a secure email change. The other address must confirm
  /// its link too before the change takes effect. The client stored no session and emitted no
  /// event. `message` comes from the server and is meant for display.
  case emailChangePending(message: String)
}

/// A `/verify` response body: a session, or the `{"msg": …}` body of the first half of a secure
/// email change.
struct VerifyOTPBody: Decodable {
  let result: VerifyOTPResult

  // Camel case names: the client's decoder converts snake case keys before it matches them.
  private enum CodingKeys: String, CodingKey {
    case accessToken
    case refreshToken
    case expiresIn
    case message = "msg"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let isSession =
      container.contains(.accessToken) && container.contains(.refreshToken)
      && container.contains(.expiresIn)
    result =
      try isSession
      ? .signedIn(Session(from: decoder))
      : .emailChangePending(message: container.decode(String.self, forKey: .message))
  }
}

/// The `{"message_id": …}` body of a phone `/otp` or `/resend` response.
struct MessageIDBody: Decodable {
  let messageId: MessageID?
}

/// Options for ``AuthClient/resend(email:type:options:)``.
public struct ResendEmailOptions: Sendable, Hashable {
  /// The URL the link redirects to. When `nil`, the client uses
  /// ``AuthClient/Configuration/redirectToURL``.
  public var redirectTo: URL?

  /// The captcha verification token.
  public var captchaToken: String?

  /// Creates options to send an email again.
  ///
  /// - Parameters:
  ///   - redirectTo: The URL the link redirects to.
  ///   - captchaToken: The captcha verification token.
  public init(redirectTo: URL? = nil, captchaToken: String? = nil) {
    self.redirectTo = redirectTo
    self.captchaToken = captchaToken
  }
}

/// Options for ``AuthClient/resend(phone:type:options:)``.
public struct ResendPhoneOptions: Sendable, Hashable {
  /// The captcha verification token.
  public var captchaToken: String?

  /// Creates options to send a phone code again.
  ///
  /// - Parameter captchaToken: The captcha verification token.
  public init(captchaToken: String? = nil) {
    self.captchaToken = captchaToken
  }
}

/// The response returned when resending an SMS OTP.
@available(*, deprecated, message: "Use MessageID instead.")
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
  public var reasons: [String]

  /// Creates a ``WeakPassword``.
  public init(
    reasons: [String]
  ) {
    self.reasons = reasons
  }
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
  let skipHttpRedirect: Bool?
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
@available(*, deprecated, message: "Use AuthAdmin.listUsers(page:pageSize:) instead.")
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

/// One page of users, returned by ``AuthAdmin/listUsers(params:)``.
///
/// The name that the next major version uses for ``ListUsersPaginatedResponse``.
public typealias UserPage = ListUsersPaginatedResponse

/// A paginated list of users returned by ``AuthAdmin/listUsers(params:)``.
public struct ListUsersPaginatedResponse: Hashable, Sendable {
  /// The users on the current page.
  public var users: [User]

  /// The audience the users belong to.
  public var audience: String

  /// The audience the users belong to.
  @available(*, deprecated, message: "Use audience instead.")
  public var aud: String { audience }

  /// The page number of the next page, if one exists.
  public var nextPage: Int?

  /// The page number of the last page.
  public var lastPage: Int

  /// The total number of users matching the query.
  public var total: Int

  /// Creates a ``UserPage``.
  public init(
    users: [User],
    audience: String,
    nextPage: Int? = nil,
    lastPage: Int,
    total: Int
  ) {
    self.users = users
    self.audience = audience
    self.nextPage = nextPage
    self.lastPage = lastPage
    self.total = total
  }
}

/// The link to generate with ``AuthAdmin/generateLink(params:)``.
///
/// The name that the next major version uses for ``GenerateLinkParams``.
public typealias GenerateLink = GenerateLinkParams

/// The parameters for ``AuthAdmin/generateLink(params:)``.
public struct GenerateLinkParams: Sendable {
  struct Body: Encodable {
    var type: GenerateLinkType
    var email: String
    var password: String?
    var newEmail: String?
    var data: [String: AnyJSON]?
  }
  var body: Body
  var redirectTo: URL?

  /// Generates a signup link.
  @available(*, deprecated, message: "Use signUp(email:password:userMetadata:redirectTo:) instead.")
  @_disfavoredOverload
  public static func signUp(
    email: String,
    password: String,
    data: [String: AnyJSON]? = nil,
    redirectTo: URL? = nil
  ) -> GenerateLinkParams {
    GenerateLinkParams(
      body: .init(
        type: .signup,
        email: email,
        password: password,
        data: data
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates an invite link.
  @available(*, deprecated, message: "Use invite(email:userMetadata:redirectTo:) instead.")
  @_disfavoredOverload
  public static func invite(
    email: String,
    data: [String: AnyJSON]? = nil,
    redirectTo: URL? = nil
  ) -> GenerateLinkParams {
    GenerateLinkParams(
      body: .init(
        type: .invite,
        email: email,
        data: data
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates a magic link.
  @available(*, deprecated, message: "Use magicLink(email:userMetadata:redirectTo:) instead.")
  @_disfavoredOverload
  public static func magicLink(
    email: String,
    data: [String: AnyJSON]? = nil,
    redirectTo: URL? = nil
  ) -> GenerateLinkParams {
    GenerateLinkParams(
      body: .init(
        type: .magiclink,
        email: email,
        data: data
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates a recovery link.
  /// Generates a signup link.
  ///
  /// - Parameters:
  ///   - email: The user's email.
  ///   - password: The user's password.
  ///   - userMetadata: Data for the user's metadata.
  ///   - redirectTo: The URL the link redirects to.
  public static func signUp(
    email: String,
    password: String,
    userMetadata: JSONObject? = nil,
    redirectTo: URL? = nil
  ) -> GenerateLink {
    GenerateLink(
      body: .init(
        type: .signup,
        email: email,
        password: password,
        data: userMetadata
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates a invite link.
  ///
  /// - Parameters:
  ///   - email: The user's email.
  ///   - userMetadata: Data for the user's metadata.
  ///   - redirectTo: The URL the link redirects to.
  public static func invite(
    email: String,
    userMetadata: JSONObject? = nil,
    redirectTo: URL? = nil
  ) -> GenerateLink {
    GenerateLink(
      body: .init(
        type: .invite,
        email: email,
        data: userMetadata
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates a magic link.
  ///
  /// - Parameters:
  ///   - email: The user's email.
  ///   - userMetadata: Data for the user's metadata.
  ///   - redirectTo: The URL the link redirects to.
  public static func magicLink(
    email: String,
    userMetadata: JSONObject? = nil,
    redirectTo: URL? = nil
  ) -> GenerateLink {
    GenerateLink(
      body: .init(
        type: .magiclink,
        email: email,
        data: userMetadata
      ),
      redirectTo: redirectTo
    )
  }

  public static func recovery(
    email: String,
    redirectTo: URL? = nil
  ) -> GenerateLinkParams {
    GenerateLinkParams(
      body: .init(
        type: .recovery,
        email: email
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates a link to change the current email address of a user.
  public static func emailChangeCurrent(
    email: String,
    newEmail: String,
    redirectTo: URL? = nil
  ) -> GenerateLinkParams {
    GenerateLinkParams(
      body: .init(
        type: .emailChangeCurrent,
        email: email,
        newEmail: newEmail
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates a link to change the email address of a user to a new one.
  public static func emailChangeNew(
    email: String,
    newEmail: String,
    redirectTo: URL? = nil
  ) -> GenerateLinkParams {
    GenerateLinkParams(
      body: .init(
        type: .emailChangeNew,
        email: email,
        newEmail: newEmail
      ),
      redirectTo: redirectTo
    )
  }
}

/// The response from the ``AuthAdmin/generateLink(params:)`` function.
public struct GenerateLinkResponse: Hashable, Sendable, Decodable {
  /// The properties related to the email link generated.
  public let properties: GenerateLinkProperties
  /// The user that the email link is associated to.
  public let user: User

  public init(from decoder: any Decoder) throws {
    self.properties = try GenerateLinkProperties(from: decoder)
    self.user = try User(from: decoder)
  }
}

/// The properties related to the email link generated.
public struct GenerateLinkProperties: Decodable, Hashable, Sendable {
  /// The email link to send to the users.
  /// The action link follows the following format: auth/v1/verify?type={verification_type}&token={hashed_token}&redirect_to={redirect_to}
  public let actionLink: URL
  /// The raw email OTP.
  /// You should send this in the email if you want your users to verify using an OTP instead of the action link.
  public let emailOTP: String
  /// The hashed token appended to the action link.
  public let hashedToken: String
  /// The URL appended to the action link.
  public let redirectTo: URL
  /// The verification type that the emaillink is associated to.
  public let verificationType: GenerateLinkType

  private enum CodingKeys: String, CodingKey {
    case actionLink
    // The decoder's `.convertFromSnakeCase` strategy converts the JSON key
    // "email_otp" to "emailOtp" (not "emailOTP") before matching against this
    // raw value, since it doesn't know to capitalize the "OTP" acronym.
    case emailOTP = "emailOtp"
    case hashedToken
    case redirectTo
    case verificationType
  }
}

/// The type of link generated by ``AuthAdmin/generateLink(params:)``.
public struct GenerateLinkType: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let signup = GenerateLinkType(rawValue: "signup")
  public static let invite = GenerateLinkType(rawValue: "invite")
  public static let magiclink = GenerateLinkType(rawValue: "magiclink")
  public static let recovery = GenerateLinkType(rawValue: "recovery")
  public static let emailChangeCurrent = GenerateLinkType(rawValue: "email_change_current")
  public static let emailChangeNew = GenerateLinkType(rawValue: "email_change_new")
}

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
  public var clientID: UUID

  /// Unique identifier for the OAuth client
  @available(*, deprecated, message: "Use clientID instead.")
  public var clientId: UUID { clientID }

  /// Human-readable name of the OAuth client
  public var clientName: String

  /// Client secret (only returned on registration and regeneration)
  public var clientSecret: String?

  /// Type of OAuth client
  public var clientType: OAuthClientType

  /// Token endpoint authentication method
  public var tokenEndpointAuthMethod: String

  /// Registration type of the client
  public var registrationType: OAuthClientRegistrationType

  /// URI of the OAuth client
  public var clientURI: URL? {
    get { clientURIString.flatMap(URL.init(string:)) }
    set { clientURIString = newValue?.absoluteString }
  }

  /// URI of the OAuth client
  @available(*, deprecated, message: "Use clientURI instead.")
  public var clientUri: String? { clientURIString }

  var clientURIString: String?

  /// URL of the client application's logo
  public var logoURI: URL? {
    get { logoURIString.flatMap(URL.init(string:)) }
    set { logoURIString = newValue?.absoluteString }
  }

  /// URI of the OAuth client's logo
  @available(*, deprecated, message: "Use logoURI instead.")
  public var logoUri: String? { logoURIString }

  var logoURIString: String?

  /// Array of allowed redirect URIs
  public var redirectURIs: [URL]? {
    get { redirectURIStrings.compactMap(URL.init(string:)) }
    set { redirectURIStrings = newValue?.map(\.absoluteString) ?? [] }
  }

  /// Array of allowed redirect URIs
  @available(*, deprecated, message: "Use redirectURIs instead.")
  public var redirectUris: [String] { redirectURIStrings }

  var redirectURIStrings: [String]

  /// Array of allowed grant types
  public var grantTypes: [OAuthClientGrantType]

  /// Array of allowed response types
  public var responseTypes: [OAuthClientResponseType]

  /// Scope of the OAuth client
  public var scope: String?

  /// Timestamp when the client was created
  public var createdAt: Date

  /// Timestamp when the client was last updated
  public var updatedAt: Date

  private enum CodingKeys: String, CodingKey {
    case clientID = "clientId"
    case clientName
    case clientSecret
    case clientType
    case tokenEndpointAuthMethod
    case registrationType
    case clientURIString = "clientUri"
    case logoURIString = "logoUri"
    case redirectURIStrings = "redirectUris"
    case grantTypes
    case responseTypes
    case scope
    case createdAt
    case updatedAt
  }
}

/// A new OAuth client for ``AuthAdminOAuth/createClient(_:)``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct CreateOAuthClient: Encodable, Hashable, Sendable {
  /// Human-readable name of the OAuth client
  public var clientName: String

  /// URI of the OAuth client
  public var clientURI: URL?

  /// Array of allowed redirect URIs
  public var redirectURIs: [URL]

  /// Array of allowed grant types (optional, defaults to authorization_code and refresh_token)
  public var grantTypes: [OAuthClientGrantType]?

  /// Array of allowed response types (optional, defaults to code)
  public var responseTypes: [OAuthClientResponseType]?

  /// Scope of the OAuth client
  public var scope: String?

  private enum CodingKeys: String, CodingKey {
    case clientName = "client_name"
    case clientURI = "client_uri"
    case redirectURIs = "redirect_uris"
    case grantTypes = "grant_types"
    case responseTypes = "response_types"
    case scope
  }

  /// Creates a new OAuth client.
  ///
  /// - Parameters:
  ///   - clientName: Human-readable name for the client.
  ///   - clientURI: URI of the client application's homepage.
  ///   - redirectURIs: Allowed redirect URIs.
  ///   - grantTypes: Allowed grant types; defaults to `authorization_code` and `refresh_token`.
  ///   - responseTypes: Allowed response types; defaults to `code`.
  ///   - scope: Requested scope.
  public init(
    clientName: String,
    clientURI: URL? = nil,
    redirectURIs: [URL],
    grantTypes: [OAuthClientGrantType]? = nil,
    responseTypes: [OAuthClientResponseType]? = nil,
    scope: String? = nil
  ) {
    self.clientName = clientName
    self.clientURI = clientURI
    self.redirectURIs = redirectURIs
    self.grantTypes = grantTypes
    self.responseTypes = responseTypes
    self.scope = scope
  }
}

/// The changes to an OAuth client for ``AuthAdminOAuth/updateClient(id:_:)``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct UpdateOAuthClient: Encodable, Hashable, Sendable {
  /// Human-readable name of the client application
  public var clientName: String?

  /// URL of the client application's homepage
  public var clientURI: URL?

  /// URL of the client application's logo
  public var logoURI: URL?

  /// Array of redirect URIs used by the client
  public var redirectURIs: [URL]?

  /// OAuth grant types the client is authorized to use
  public var grantTypes: [OAuthClientGrantType]?

  private enum CodingKeys: String, CodingKey {
    case clientName = "client_name"
    case clientURI = "client_uri"
    case logoURI = "logo_uri"
    case redirectURIs = "redirect_uris"
    case grantTypes = "grant_types"
  }

  /// Creates the changes to an OAuth client.
  ///
  /// - Parameters:
  ///   - clientName: New human-readable name.
  ///   - clientURI: New URI for the client application.
  ///   - logoURI: New logo URI.
  ///   - redirectURIs: Replacement list of redirect URIs.
  ///   - grantTypes: Replacement list of grant types.
  public init(
    clientName: String? = nil,
    clientURI: URL? = nil,
    logoURI: URL? = nil,
    redirectURIs: [URL]? = nil,
    grantTypes: [OAuthClientGrantType]? = nil
  ) {
    self.clientName = clientName
    self.clientURI = clientURI
    self.logoURI = logoURI
    self.redirectURIs = redirectURIs
    self.grantTypes = grantTypes
  }
}

/// Parameters for creating a new OAuth client.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
@available(*, deprecated, message: "Use CreateOAuthClient instead.")
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
@available(*, deprecated, message: "Use UpdateOAuthClient instead.")
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
@available(
  *, deprecated, message: "Use AuthAdminOAuth.listClients() with a [OAuthClient] result instead."
)
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

// MARK: - OAuth Authorization Server Types

/// Details about the OAuth client requesting authorization.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthAuthorizationClient: Codable, Hashable, Sendable {
  /// Unique identifier for the OAuth client.
  public var id: UUID

  /// Human-readable name of the OAuth client.
  public var name: String

  /// URI of the OAuth client's homepage.
  public var uri: URL?

  /// URL of the OAuth client's logo.
  public var logoURI: URL?

  /// URL of the client's logo.
  @available(*, deprecated, message: "Use logoURI instead.")
  public var logoUri: URL? { logoURI }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case uri
    case logoURI = "logoUri"
  }
}

/// The authenticated user considering the authorization request.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthAuthorizationUser: Codable, Hashable, Sendable {
  /// Unique identifier for the user.
  public let id: UUID

  /// The user's email address.
  public let email: String
}

/// Details about a pending OAuth authorization request, returned by
/// ``AuthOAuthServer/getAuthorizationDetails(authorizationId:)`` when the
/// request still requires the user's consent.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthAuthorizationDetails: Codable, Hashable, Sendable {
  /// Opaque identifier for this authorization request.
  public var authorizationID: String

  /// The opaque identifier of the authorization request.
  @available(*, deprecated, message: "Use authorizationID instead.")
  public var authorizationId: String { authorizationID }

  /// The redirect URI the client registered for this request.
  public var redirectURI: URL

  /// The URI the user is sent back to after the decision.
  @available(*, deprecated, message: "Use redirectURI instead.")
  public var redirectUri: URL { redirectURI }

  /// The OAuth client requesting authorization.
  public var client: OAuthAuthorizationClient

  /// The user considering the request.
  public var user: OAuthAuthorizationUser

  /// The requested scope.
  public var scope: String

  private enum CodingKeys: String, CodingKey {
    case authorizationID = "authorizationId"
    case redirectURI = "redirectUri"
    case client
    case user
    case scope
  }
}

/// A redirect URL returned after approving or denying an OAuth authorization
/// request, or in place of ``OAuthAuthorizationDetails`` when the server
/// auto-approves a request the user has already consented to.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthRedirect: Codable, Hashable, Sendable {
  /// The URL the client app should be redirected to. On denial, this URL's
  /// query string carries an `error=access_denied` parameter (RFC 6749) —
  /// denial is a successful API call, not a thrown error.
  public let redirectURL: URL

  private enum CodingKeys: String, CodingKey {
    // The decoder's `.convertFromSnakeCase` strategy converts the JSON key
    // "redirect_url" to "redirectUrl" (not "redirectURL") before matching
    // against this raw value, since it doesn't know to capitalize the "URL"
    // acronym.
    case redirectURL = "redirectUrl"
  }
}

/// The result of ``AuthOAuthServer/getAuthorizationDetails(authorizationId:)``.
///
/// The name that the next major version uses for ``OAuthAuthorizationDetailsResponse``.
public typealias OAuthAuthorizationDetailsResult = OAuthAuthorizationDetailsResponse

/// The response from ``AuthOAuthServer/getAuthorizationDetails(authorizationId:)``.
///
/// The server auto-approves an authorization request if the user already has
/// an active consent covering the requested scopes for that client, returning
/// ``redirect(_:)`` instead of ``details(_:)``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public enum OAuthAuthorizationDetailsResponse: Hashable, Sendable {
  /// The authorization is pending; present these details to the user for consent.
  case details(OAuthAuthorizationDetails)

  /// The authorization was already approved automatically; redirect the user.
  case redirect(OAuthRedirect)
}

extension OAuthAuthorizationDetailsResponse: Decodable {
  public init(from decoder: any Decoder) throws {
    // Neither shape decoding failing surfaces both underlying errors, instead
    // of a naive try?/fallback silently discarding a genuine decoding
    // failure in .details (not just "this is the .redirect shape") in favor
    // of the (less useful) .redirect error.
    self = try decodeOneOf(
      { .details(try OAuthAuthorizationDetails(from: decoder)) },
      { .redirect(try OAuthRedirect(from: decoder)) }
    )
  }
}

/// An OAuth grant the user has given to a third-party client app, returned by
/// ``AuthOAuthServer/listGrants()``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthGrant: Codable, Hashable, Sendable {
  /// The OAuth client the grant was given to.
  public let client: OAuthAuthorizationClient

  /// The scopes granted to the client.
  public let scopes: [String]

  /// When the grant was given.
  public let grantedAt: Date
}

// MARK: - JWT Claims

/// JSON Web Key (JWK) representation.
public struct JWK: Codable, Hashable, Sendable {
  /// Key type (e.g., `"RSA"`, `"EC"`, `"oct"`).
  public var kty: String

  /// Key operations (e.g., `["sign", "verify"]`).
  public var keyOps: [String]?

  /// Algorithm (e.g., `"RS256"`, `"ES256"`, `"HS256"`).
  public var alg: String?

  /// Key ID.
  public var kid: String?

  // RSA-specific fields
  /// RSA modulus (base64url-encoded).
  public var n: String?

  /// RSA exponent (base64url-encoded).
  public var e: String?

  // EC-specific fields
  /// EC curve name (e.g., `"P-256"`).
  public var crv: String?

  /// EC x coordinate (base64url-encoded).
  public var x: String?

  /// EC y coordinate (base64url-encoded).
  public var y: String?

  // Symmetric key field
  /// Symmetric key value (base64url-encoded).
  public var k: String?

  /// Creates a ``JWK``.
  public init(
    kty: String,
    keyOps: [String]? = nil,
    alg: String? = nil,
    kid: String? = nil,
    n: String? = nil,
    e: String? = nil,
    crv: String? = nil,
    x: String? = nil,
    y: String? = nil,
    k: String? = nil
  ) {
    self.kty = kty
    self.keyOps = keyOps
    self.alg = alg
    self.kid = kid
    self.n = n
    self.e = e
    self.crv = crv
    self.x = x
    self.y = y
    self.k = k
  }

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
  public var keys: [JWK]

  /// Creates a ``JWKS``.
  public init(
    keys: [JWK]
  ) {
    self.keys = keys
  }
}

/// The header portion of a decoded JSON Web Token.
public struct JWTHeader: Codable, Hashable, Sendable {
  /// Algorithm (e.g., `"RS256"`, `"ES256"`, `"HS256"`).
  public var alg: String

  /// Key ID used to select the signing key.
  public var kid: String?

  /// Token type (typically `"JWT"`).
  public var typ: String?

  /// Creates a ``JWTHeader``.
  public init(
    alg: String,
    kid: String? = nil,
    typ: String? = nil
  ) {
    self.alg = alg
    self.kid = kid
    self.typ = typ
  }
}

/// The decoded claims from a JSON Web Token.
@available(*, deprecated, message: "Use VerifiedClaims instead.")
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
@available(*, deprecated, message: "Use VerifiedClaims instead.")
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
@available(*, deprecated, message: "Use VerifiedClaims instead.")
public struct JWTClaimsResponse: Sendable {
  /// The decoded JWT claims.
  public let claims: JWTClaims

  /// The decoded JWT header.
  public let header: JWTHeader

  /// The raw JWT signature bytes.
  public let signature: Data
}

/// Options for ``AuthClient/getClaims(jwt:options:)``.
@available(*, deprecated, message: "Use ClaimsOptions instead.")
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
