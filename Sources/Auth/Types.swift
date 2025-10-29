import Foundation

public enum AuthChangeEvent: String, Sendable {
  case initialSession = "INITIAL_SESSION"
  case passwordRecovery = "PASSWORD_RECOVERY"
  case signedIn = "SIGNED_IN"
  case signedOut = "SIGNED_OUT"
  case tokenRefreshed = "TOKEN_REFRESHED"
  case userUpdated = "USER_UPDATED"
  case userDeleted = "USER_DELETED"
  case mfaChallengeVerified = "MFA_CHALLENGE_VERIFIED"
}

struct UserCredentials: Codable, Hashable, Sendable {
  var email: String?
  var password: String?
  var phone: String?
  var refreshToken: String?
  var gotrueMetaSecurity: AuthMetaSecurity?
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

public struct Session: Codable, Hashable, Sendable {
  /// The oauth provider token. If present, this can be used to make external API requests to the
  /// oauth provider used.
  public var providerToken: String?

  /// The oauth provider refresh token. If present, this can be used to refresh the provider_token
  /// via the oauth provider's API. Not all oauth providers return a provider refresh token. If the
  /// provider_refresh_token is missing, please refer to the oauth provider's documentation for
  /// information on how to obtain the provider refresh token.
  public var providerRefreshToken: String?

  /// A valid JWT that will expire in ``Session/expiresIn`` seconds.
  /// It is recommended to set the `JWT_EXPIRY` to a shorter expiry value.
  public var accessToken: String

  /// What type of token this is. Only `bearer` returned, may change in the future.
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

  public var user: User

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

  /// Returns `true` if the token is expired or will expire in the next 30 seconds.
  ///
  /// The 30 second buffer is to account for latency issues.
  public var isExpired: Bool {
    let expiresAt = Date(timeIntervalSince1970: expiresAt)
    return expiresAt.timeIntervalSinceNow < defaultExpiryMargin
  }
}

public struct User: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID
  public var appMetadata: [String: AnyJSON]
  public var userMetadata: [String: AnyJSON]
  public var aud: String
  public var confirmationSentAt: Date?
  public var recoverySentAt: Date?
  public var emailChangeSentAt: Date?
  public var newEmail: String?
  public var invitedAt: Date?
  public var actionLink: String?
  public var email: String?
  public var phone: String?
  public var createdAt: Date
  public var confirmedAt: Date?
  public var emailConfirmedAt: Date?
  public var phoneConfirmedAt: Date?
  public var lastSignInAt: Date?
  public var role: String?
  public var updatedAt: Date
  public var identities: [UserIdentity]?
  public var isAnonymous: Bool
  public var factors: [Factor]?

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

public struct UserIdentity: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var identityId: UUID
  public var userId: UUID
  public var identityData: [String: AnyJSON]?
  public var provider: String
  public var createdAt: Date?
  public var lastSignInAt: Date?
  public var updatedAt: Date?

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
  case twitter
  case workos
  case zoom
  case fly

  public var id: RawValue { rawValue }
}

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

  public enum Provider: String, Codable, Hashable, Sendable {
    case google, apple, azure, facebook
  }
}

public struct AuthMetaSecurity: Codable, Hashable, Sendable {
  public var captchaToken: String

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

public enum MobileOTPType: String, Encodable, Sendable {
  case sms
  case phoneChange = "phone_change"
}

public enum EmailOTPType: String, Encodable, CaseIterable, Sendable {
  case signup
  case invite
  case magiclink
  case recovery
  case emailChange = "email_change"
  case email
}

public enum AuthResponse: Codable, Hashable, Sendable {
  case session(Session)
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

  public var user: User {
    switch self {
    case .session(let session): session.user
    case .user(let user): user
    }
  }

  public var session: Session? {
    if case .session(let session) = self { return session }
    return nil
  }
}

public struct UserAttributes: Codable, Hashable, Sendable {
  /// The user's email.
  public var email: String?
  /// The user's phone.
  public var phone: String?
  /// The user's password.
  public var password: String?

  /// The nonce sent for reauthentication if the user's password is to be updated.
  ///
  /// Note: Call ``AuthClient/reauthenticate()`` to obtain the nonce first.
  public var nonce: String?

  /// A custom data object to store the user's metadata. This maps to the `auth.users.user_metadata`
  /// column. The `data` should be a JSON object that includes user-specific info, such as their
  /// first and last name.
  public var data: [String: AnyJSON]?

  var codeChallenge: String?
  var codeChallengeMethod: String?

  public init(
    email: String? = nil,
    phone: String? = nil,
    password: String? = nil,
    nonce: String? = nil,
    data: [String: AnyJSON]? = nil
  ) {
    self.email = email
    self.phone = phone
    self.password = password
    self.nonce = nonce
    self.data = data
  }
}

public struct AdminUserAttributes: Encodable, Hashable, Sendable {

  /// A custom data object to store the user's application specific metadata. This maps to the `auth.users.app_metadata` column.
  public var appMetadata: [String: AnyJSON]?

  /// Determines how long a user is banned for.
  public var banDuration: String?

  /// The user's email.
  public var email: String?

  /// Confirms the user's email address if set to true.
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

  /// Confirms the user's phone number if set to true.
  public var phoneConfirm: Bool?

  /// The role claim set in the user's access token JWT.
  public var role: String?

  /// A custom data object to store the user's metadata. This maps to the `auth.users.raw_user_meta_data` column.
  public var userMetadata: [String: AnyJSON]?

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

public enum AuthFlowType: Sendable {
  case implicit
  case pkce
}

public typealias FactorType = String

public enum FactorStatus: String, Codable, Sendable {
  case verified
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

  public let createdAt: Date
  public let updatedAt: Date
}

public protocol MFAEnrollParamsType: Encodable, Hashable, Sendable {
  var factorType: FactorType { get }
}

public struct MFATotpEnrollParams: MFAEnrollParamsType {
  public let factorType: FactorType = "totp"
  /// Domain which the user is enrolled with.
  public let issuer: String?
  /// Human readable name assigned to the factor.
  public let friendlyName: String?

  public init(issuer: String? = nil, friendlyName: String? = nil) {
    self.issuer = issuer
    self.friendlyName = friendlyName
  }
}

extension MFAEnrollParamsType where Self == MFATotpEnrollParams {
  public static func totp(issuer: String? = nil, friendlyName: String? = nil) -> Self {
    MFATotpEnrollParams(issuer: issuer, friendlyName: friendlyName)
  }
}

public struct MFAPhoneEnrollParams: MFAEnrollParamsType {
  public let factorType: FactorType = "phone"

  /// Human readable name assigned to the factor.
  public let friendlyName: String?

  /// Phone number to be enrolled. Number should conform to E.164 standard.
  public let phone: String

  public init(friendlyName: String? = nil, phone: String) {
    self.friendlyName = friendlyName
    self.phone = phone
  }
}

extension MFAEnrollParamsType where Self == MFAPhoneEnrollParams {
  public static func phone(friendlyName: String? = nil, phone: String) -> Self {
    MFAPhoneEnrollParams(friendlyName: friendlyName, phone: phone)
  }
}

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

public struct MFAChallengeParams: Encodable, Hashable {
  /// ID of the factor to be challenged. Returned in ``AuthMFA/enroll(params:)``.
  public let factorId: String

  /// Messaging channel to use (e.g. `whatsapp` or `sms`). Only relevant for phone factors.
  public let channel: MessagingChannel?

  public init(factorId: String, channel: MessagingChannel? = nil) {
    self.factorId = factorId
    self.channel = channel
  }
}

public struct MFAVerifyParams: Encodable, Hashable {
  /// ID of the factor being verified. Returned in ``AuthMFA/enroll(params:)``.
  public let factorId: String

  /// ID of the challenge being verified. Returned in challenge().
  public let challengeId: String

  /// Verification code provided by the user.
  public let code: String

  public init(factorId: String, challengeId: String, code: String) {
    self.factorId = factorId
    self.challengeId = challengeId
    self.code = code
  }
}

public struct MFAUnenrollParams: Encodable, Hashable, Sendable {
  /// ID of the factor to unenroll. Returned in ``AuthMFA/enroll(params:)``.
  public let factorId: String

  public init(factorId: String) {
    self.factorId = factorId
  }
}

public struct MFAChallengeAndVerifyParams: Encodable, Hashable, Sendable {
  /// ID of the factor to be challenged. Returned in ``AuthMFA/enroll(params:)``.
  public let factorId: String

  /// Verification code provided by the user.
  public let code: String

  public init(factorId: String, code: String) {
    self.factorId = factorId
    self.code = code
  }
}

public struct AuthMFAChallengeResponse: Decodable, Hashable, Sendable {
  /// ID of the newly created challenge.
  public let id: String

  /// Factor type which generated the challenge.
  public let type: FactorType

  /// Timestamp in UNIX seconds when this challenge will no longer be usable.
  public let expiresAt: TimeInterval
}

public typealias AuthMFAVerifyResponse = Session

public struct AuthMFAUnenrollResponse: Decodable, Hashable, Sendable {
  /// ID of the factor that was successfully unenrolled.
  public let factorId: String
}

public struct AuthMFAListFactorsResponse: Decodable, Hashable, Sendable {
  /// All available factors (verified and unverified).
  public let all: [Factor]

  /// Only verified TOTP factors. (A subset of `all`.)
  public let totp: [Factor]

  /// Only verified phone factors. (A subset of `all`.)
  public let phone: [Factor]
}

public typealias AuthenticatorAssuranceLevels = String

/// An authentication method reference (AMR) entry.
///
/// An entry designates what method was used by the user to verify their identity and at what time.
public struct AMREntry: Decodable, Hashable, Sendable {
  /// Authentication method name.
  public let method: Method

  /// Timestamp when the method was successfully used.
  public let timestamp: TimeInterval

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

public enum ResendEmailType: String, Hashable, Sendable, Encodable {
  case signup
  case emailChange = "email_change"
}

struct ResendEmailParams: Encodable {
  let type: ResendEmailType
  let email: String
  let gotrueMetaSecurity: AuthMetaSecurity?
}

public enum ResendMobileType: String, Hashable, Sendable, Encodable {
  case sms
  case phoneChange = "phone_change"
}

struct ResendMobileParams: Encodable {
  let type: ResendMobileType
  let phone: String
  let gotrueMetaSecurity: AuthMetaSecurity?
}

public struct ResendMobileResponse: Decodable, Hashable, Sendable {
  /// Unique ID of the message as reported by the SMS sending provider. Useful for tracking
  /// deliverability problems.
  public let messageId: String?

  public init(messageId: String?) {
    self.messageId = messageId
  }
}

public struct WeakPassword: Codable, Hashable, Sendable {
  /// List of reasons the password is too weak, could be any of `length`, `characters`, or `pwned`.
  public let reasons: [String]
}

struct DeleteUserRequest: Encodable {
  let shouldSoftDelete: Bool
}

public enum MessagingChannel: String, Codable, Sendable {
  case sms
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

public struct SSOResponse: Codable, Hashable, Sendable {
  /// URL to open in a browser which will complete the sign-in flow by taking the user to the
  /// identity provider's authentication flow.
  public let url: URL
}

public struct OAuthResponse: Codable, Hashable, Sendable {
  public let provider: Provider
  public let url: URL
}

public struct PageParams {
  /// The page number.
  public let page: Int?
  /// Number of items returned per page.
  public let perPage: Int?

  public init(page: Int? = nil, perPage: Int? = nil) {
    self.page = page
    self.perPage = perPage
  }
}

public struct ListUsersPaginatedResponse: Hashable, Sendable {
  public let users: [User]
  public let aud: String
  public var nextPage: Int?
  public var lastPage: Int
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
//  /// The raw ramil OTP.
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
  public let rawValue: String
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public static let authorizationCode: OAuthClientGrantType = "authorization_code"
  public static let refreshToken: OAuthClientGrantType = "refresh_token"
}

/// OAuth client response types supported by the OAuth 2.1 server.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthClientResponseType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public static let code: OAuthClientResponseType = "code"
}

/// OAuth client type indicating whether the client can keep credentials confidential.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthClientType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
  public static let `public`: OAuthClientType = "public"
  public static let confidential: OAuthClientType = "confidential"
}

/// OAuth client registration type.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthClientRegistrationType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }
  public static let dynamic: OAuthClientRegistrationType = "dynamic"
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

/// Response type for listing OAuth clients.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct ListOAuthClientsPaginatedResponse: Hashable, Sendable {
  public let clients: [OAuthClient]
  public let aud: String
  public var nextPage: Int?
  public var lastPage: Int
  public var total: Int
}

// MARK: - JWT Claims

/// JSON Web Key (JWK) representation
public struct JWK: Codable, Hashable, Sendable {
  /// Key type (e.g., "RSA", "EC", "oct")
  public let kty: String
  /// Key operations (e.g., ["sign", "verify"])
  public let keyOps: [String]?
  /// Algorithm (e.g., "RS256", "ES256", "HS256")
  public let alg: String?
  /// Key ID
  public let kid: String?

  // RSA-specific fields
  /// RSA modulus (base64url-encoded)
  public let n: String?
  /// RSA exponent (base64url-encoded)
  public let e: String?

  // EC-specific fields
  /// EC curve name (e.g., "P-256")
  public let crv: String?
  /// EC x coordinate (base64url-encoded)
  public let x: String?
  /// EC y coordinate (base64url-encoded)
  public let y: String?

  // Symmetric key field
  /// Symmetric key value (base64url-encoded)
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

/// JSON Web Key Set (JWKS)
public struct JWKS: Codable, Hashable, Sendable {
  public let keys: [JWK]
}

/// JWT Header
public struct JWTHeader: Codable, Hashable, Sendable {
  /// Algorithm (e.g., "RS256", "ES256", "HS256")
  public let alg: String
  /// Key ID
  public let kid: String?
  /// Type (typically "JWT")
  public let typ: String?
}

/// JWT Claims
public struct JWTClaims: Codable, Hashable, Sendable {
  /// Issuer
  public let iss: String?
  /// Subject
  public let sub: String?
  /// Audience
  public let aud: AudienceClaim?
  /// Expiration time
  public let exp: TimeInterval?
  /// Issued at
  public let iat: TimeInterval?
  /// Not before
  public let nbf: TimeInterval?
  /// JWT ID
  public let jti: String?
  /// Role
  public let role: String?
  /// Authenticator Assurance Level
  public let aal: String?
  /// Session ID
  public let sessionId: String?
  /// Email
  public let email: String?
  /// Phone
  public let phone: String?
  /// App metadata
  public let appMetadata: [String: AnyJSON]?
  /// User metadata
  public let userMetadata: [String: AnyJSON]?
  /// Additional claims
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

/// Audience claim can be either a string or an array of strings
public enum AudienceClaim: Codable, Hashable, Sendable {
  case string(String)
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

/// Response from getClaims method
public struct JWTClaimsResponse: Sendable {
  public let claims: JWTClaims
  public let header: JWTHeader
  public let signature: Data
}

/// Options for the getClaims method
public struct GetClaimsOptions: Sendable {
  /// If set to `true` the `exp` claim will not be validated against the current time.
  public let allowExpired: Bool

  /// If set, this JSON Web Key Set is going to have precedence over the cached value available on the server.
  public let jwks: JWKS?

  public init(allowExpired: Bool = false, jwks: JWKS? = nil) {
    self.allowExpired = allowExpired
    self.jwks = jwks
  }
}
