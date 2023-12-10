import Foundation
@_spi(Internal) import _Helpers

public typealias AnyJSON = _Helpers.AnyJSON

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

public struct UserCredentials: Codable, Hashable, Sendable {
  public var email: String?
  public var password: String?
  public var phone: String?
  public var refreshToken: String?

  public init(
    email: String? = nil,
    password: String? = nil,
    phone: String? = nil,
    refreshToken: String? = nil
  ) {
    self.email = email
    self.password = password
    self.phone = phone
    self.refreshToken = refreshToken
  }
}

struct SignUpRequest: Codable, Hashable, Sendable {
  var email: String?
  var password: String?
  var phone: String?
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
  public var expiresAt: TimeInterval?

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
    expiresAt: TimeInterval?,
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

  static let empty = Session(
    accessToken: "",
    tokenType: "",
    expiresIn: 0,
    expiresAt: nil,
    refreshToken: "",
    user: User(
      id: UUID(),
      appMetadata: [:],
      userMetadata: [:],
      aud: "",
      createdAt: Date(),
      updatedAt: Date()
    )
  )
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
    self.factors = factors
  }
}

public struct UserIdentity: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var userId: UUID
  public var identityData: [String: AnyJSON]?
  public var provider: String
  public var createdAt: Date
  public var lastSignInAt: Date
  public var updatedAt: Date

  public init(
    id: String,
    userId: UUID,
    identityData: [String: AnyJSON],
    provider: String,
    createdAt: Date,
    lastSignInAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.userId = userId
    self.identityData = identityData
    self.provider = provider
    self.createdAt = createdAt
    self.lastSignInAt = lastSignInAt
    self.updatedAt = updatedAt
  }
}

public enum Provider: String, Codable, CaseIterable, Sendable {
  case apple
  case azure
  case bitbucket
  case discord
  case email
  case facebook
  case github
  case gitlab
  case google
  case keycloak
  case linkedin
  case notion
  case slack
  case spotify
  case twitch
  case twitter
  case workos
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
  var data: [String: AnyJSON]?
  var gotrueMetaSecurity: AuthMetaSecurity?
  var codeChallenge: String?
  var codeChallengeMethod: String?
}

enum VerifyOTPParams: Encodable {
  case email(VerifyEmailOTPParams)
  case mobile(VerifyMobileOTPParams)

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .email(value):
      try container.encode(value)
    case let .mobile(value):
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

  public init(from decoder: Decoder) throws {
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

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .session(value): try container.encode(value)
    case let .user(value): try container.encode(value)
    }
  }

  public var user: User {
    switch self {
    case let .session(session): return session.user
    case let .user(user): return user
    }
  }

  public var session: Session? {
    if case let .session(session) = self { return session }
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
  /// An email change token.
  public var emailChangeToken: String?
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
    emailChangeToken: String? = nil,
    data: [String: AnyJSON]? = nil
  ) {
    self.email = email
    self.phone = phone
    self.password = password
    self.emailChangeToken = emailChangeToken
    self.data = data
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

  /// Type of factor. Only `totp` supported with this version but may change in future versions.
  public let factorType: String

  /// Factor's status.
  public let status: FactorStatus

  public let createdAt: Date
  public let updatedAt: Date
}

public struct MFAEnrollParams: Encodable, Hashable, Sendable {
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

public struct AuthMFAEnrollResponse: Decodable, Hashable, Sendable {
  /// ID of the factor that was just enrolled (in an unverified state).
  public let id: String

  /// Type of MFA factor. Only `totp` supported for now.
  public let type: FactorType

  /// TOTP enrollment information.
  public var totp: TOTP?

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

  public init(factorId: String) {
    self.factorId = factorId
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
  /// List of reasons the password is too weak, could be any of `length`, `characters`, or
  /// `pwned`.
  public let reasons: [String]
}
