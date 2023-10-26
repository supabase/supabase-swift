import Foundation

public enum AuthChangeEvent: String, Sendable {
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
  var gotrueMetaSecurity: GoTrueMetaSecurity?
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
  /// The access token jwt. It is recommended to set the JWT_EXPIRY to a shorter expiry value.
  public var accessToken: String
  public var tokenType: String
  /// The number of seconds until the token expires (since it was issued). Returned when a login is
  /// confirmed.
  public var expiresIn: Double
  /// A one-time used refresh token that never expires.
  public var refreshToken: String
  public var user: User

  public init(
    providerToken: String? = nil,
    providerRefreshToken: String? = nil,
    accessToken: String,
    tokenType: String,
    expiresIn: Double,
    refreshToken: String,
    user: User
  ) {
    self.providerToken = providerToken
    self.providerRefreshToken = providerRefreshToken
    self.accessToken = accessToken
    self.tokenType = tokenType
    self.expiresIn = expiresIn
    self.refreshToken = refreshToken
    self.user = user
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
  public var provider: Provider?

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
  public var gotrueMetaSecurity: GoTrueMetaSecurity?

  public init(
    provider: Provider? = nil,
    idToken: String,
    accessToken: String? = nil,
    nonce: String? = nil,
    gotrueMetaSecurity: GoTrueMetaSecurity? = nil
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

public struct GoTrueMetaSecurity: Codable, Hashable, Sendable {
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
  var gotrueMetaSecurity: GoTrueMetaSecurity?
  var codeChallenge: String?
  var codeChallengeMethod: String?
}

struct VerifyOTPParams: Codable, Hashable, Sendable {
  var email: String?
  var phone: String?
  var token: String
  var type: OTPType
  var gotrueMetaSecurity: GoTrueMetaSecurity?
}

public enum OTPType: String, Codable, CaseIterable, Sendable {
  case sms
  case phoneChange = "phone_change"
  case signup
  case invite
  case magiclink
  case recovery
  case emailChange = "email_change"
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
  var gotrueMetaSecurity: GoTrueMetaSecurity?
}

public enum AuthFlowType {
  case implicit
  case pkce
}

public enum FactorType: String, Codable, Sendable {
  case totp
}

public enum FactorStatus: String, Codable, Sendable {
  case verified
  case unverified
}

/// An MFA Factor.
public struct Factor: Codable, Hashable, Sendable {
  /// ID of the factor.
  public let id: String

  /// Friendly name of the factor, useful to disambiguate between multiple factors.
  public let friendlyMame: String?

  /// Type of factor. Only `totp` supported with this version but may change in future versions.
  public let factorType: FactorType

  /// Factor's status.
  public let status: FactorStatus

  public let createdAt: Date
  public let updatedAt: Date
}

public struct MFAEnrollParams: Encodable, Hashable {
  public let factorType: FactorType = .totp
  /// Domain which the user is enrolled with.
  public let issuer: String?
  /// Human readable name assigned to the factor.
  public let friendlyName: String?

  public init(issuer: String?, friendlyName: String?) {
    self.issuer = issuer
    self.friendlyName = friendlyName
  }
}

public struct AuthMFAEnrollResponse: Decodable, Hashable {
  /// ID of the factor that was just enrolled (in an unverified state).
  public let id: String

  /// Type of MFA factor. Only `totp` supported for now.
  public let type: FactorType

  /// TOTP enrollment information.
  public var totp: TOTP?

  public struct TOTP: Decodable, Hashable {
    /// Contains a QR code encoding the authenticator URI. You can convert it to a URL by prepending `data:image/svg+xml;utf-8,` to the value. Avoid logging this value to the console.
    public var qrCode: String

    /// The TOTP secret (also encoded in the QR code). Show this secret in a password-style field to the user, in case they are unable to scan the QR code. Avoid logging this value to the console.
    public let secret: String

    /// The authenticator URI encoded within the QR code, should you need to use it. Avoid loggin this value to the console.
    public let url: String
  }
}

public struct MFAChallengeParams: Encodable, Hashable {
  /// ID of the factor to be challenged. Returned in ``GoTrueMFA.enroll(params:)``.
  public let factorId: String
}

public struct MFAVerifyParams: Encodable, Hashable {
  /// ID of the factor being verified. Returned in ``GoTrueMFA.enroll(params:)``.
  public let factorId: String

  /// ID of the challenge being verified. Returned in challenge().
  public let challengeId: String

  /// Verification code provided by the user.
  public let code: String
}

public struct MFAUnenrollParams: Encodable, Hashable {
  /// ID of the factor to unenroll. Returned in ``GoTrueMFA.enroll(params:)``.
  public let factorId: String
}

public struct MFAChallengeAndVerifyParams: Encodable, Hashable {
  /// ID of the factor to be challenged. Returned in ``GoTrueMFA.enroll(params:)``.
  public let factorId: String

  /// Verification code provided by the user.
  public let code: String
}

public struct AuthMFAChallengeResponse: Decodable, Hashable {
  /// ID of the newly created challenge.
  public let id: String

  /// Timestamp in UNIX seconds when this challenge will no longer be usable.
  public let expiresAt: TimeInterval
}

public typealias AuthMFAVerifyResponse = Session

public struct AuthMFAUnenrollResponse: Decodable, Hashable {
  /// ID of the factor that was successfully unenrolled.
  public let factorId: String
}

public struct AuthMFAListFactorsResponse: Decodable, Hashable {
  /// All available factors (verified and unverified).
  public let all: [Factor]

  /// Only verified TOTP factors. (A subset of `all`.)
  public let totp: [Factor]
}

public enum AuthenticatorAssuranceLevels: String, Codable {
  case aal1
  case aal2
}

/// An authentication method reference (AMR) entry.
///
/// An entry designates what method was used by the user to verify their identity and at what time.
public struct AMREntry: Decodable, Hashable {
  /// Authentication method name.
  public let method: Method

  /// Timestamp when the method was successfully used.
  public let timestamp: TimeInterval

  public enum Method: String, Decodable {
    case password
    case otp
    case oauth
    case mfaTOTP = "mfa/totp"
  }
}

extension AMREntry {
  init?(value: Any) {
    guard let dict = value as? [String: Any],
      let method = dict["method"].flatMap({ $0 as? String }).flatMap(Method.init),
      let timestamp = dict["timestamp"].flatMap({ $0 as? TimeInterval })
    else {
      return nil
    }

    self.method = method
    self.timestamp = timestamp
  }
}

public struct AuthMFAGetAuthenticatorAssuranceLevelResponse: Decodable, Hashable {
  /// Current AAL level of the session.
  public let currentLevel: AuthenticatorAssuranceLevels?

  /// Next possible AAL level for the session. If the next level is higher than the current one, the user should go through MFA.
  public let nextLevel: AuthenticatorAssuranceLevels?

  /// A list of all authentication methods attached to this session. Use the information here to detect the last time a user verified a factor, for example if implementing a step-up scenario.
  public let currentAuthenticationMethods: [AMREntry]
}

// MARK: - Encodable & Decodable

private let dateFormatterWithFractionalSeconds = { () -> ISO8601DateFormatter in
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter
}()

private let dateFormatter = { () -> ISO8601DateFormatter in
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()

extension JSONDecoder {
  public static let goTrue = { () -> JSONDecoder in
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)

      let supportedFormatters = [dateFormatterWithFractionalSeconds, dateFormatter]

      for formatter in supportedFormatters {
        if let date = formatter.date(from: string) {
          return date
        }
      }

      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid date format: \(string)"
      )
    }
    return decoder
  }()
}

extension JSONEncoder {
  public static let goTrue = { () -> JSONEncoder in
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let string = dateFormatter.string(from: date)
      try container.encode(string)
    }
    return encoder
  }()
}
