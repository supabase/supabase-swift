import Foundation

public enum AuthChangeEvent: String, Sendable {
  case passwordRecovery = "PASSWORD_RECOVERY"
  case signedIn = "SIGNED_IN"
  case signedOut = "SIGNED_OUT"
  case tokenRefreshed = "TOKEN_REFRESHED"
  case userUpdated = "USER_UPDATED"
  case userDeleted = "USER_DELETED"
}

public enum AnyJSON: Hashable, Codable, Sendable {
  case string(String)
  case number(Double)
  case object([String: AnyJSON])
  case array([AnyJSON])
  case bool(Bool)
  case null

  public var value: Any? {
    switch self {
    case let .string(string): return string
    case let .number(double): return double
    case let .object(dictionary): return dictionary
    case let .array(array): return array
    case let .bool(bool): return bool
    case .null: return nil
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .array(array): try container.encode(array)
    case let .object(object): try container.encode(object)
    case let .string(string): try container.encode(string)
    case let .number(number): try container.encode(number)
    case let .bool(bool): try container.encode(bool)
    case .null: try container.encodeNil()
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let object = try? container.decode([String: AnyJSON].self) {
      self = .object(object)
    } else if let array = try? container.decode([AnyJSON].self) {
      self = .array(array)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if container.decodeNil() {
      self = .null
    } else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid JSON value.")
      )
    }
  }
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

  public enum CodingKeys: String, CodingKey {
    case email
    case password
    case phone
    case refreshToken = "refresh_token"
  }
}

public struct SignUpRequest: Codable, Hashable, Sendable {
  public var email: String?
  public var password: String?
  public var phone: String?
  public var data: [String: AnyJSON]?
  public var gotrueMetaSecurity: GoTrueMetaSecurity?

  public init(
    email: String? = nil,
    password: String? = nil,
    phone: String? = nil,
    data: [String: AnyJSON]? = nil,
    gotrueMetaSecurity: GoTrueMetaSecurity? = nil
  ) {
    self.email = email
    self.password = password
    self.phone = phone
    self.data = data
    self.gotrueMetaSecurity = gotrueMetaSecurity
  }

  public enum CodingKeys: String, CodingKey {
    case email
    case password
    case phone
    case data
    case gotrueMetaSecurity = "gotrue_meta_security"
  }
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

  public enum CodingKeys: String, CodingKey {
    case providerToken = "provider_token"
    case providerRefreshToken = "provider_refresh_token"
    case accessToken = "access_token"
    case tokenType = "token_type"
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
    case user
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
    identities: [UserIdentity]? = nil
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
  }

  public enum CodingKeys: String, CodingKey {
    case id
    case appMetadata = "app_metadata"
    case userMetadata = "user_metadata"
    case aud
    case confirmationSentAt = "confirmation_sent_at"
    case recoverySentAt = "recovery_sent_at"
    case emailChangeSentAt = "email_change_sent_at"
    case newEmail = "new_email"
    case invitedAt = "invited_at"
    case actionLink = "action_link"
    case email
    case phone
    case createdAt = "created_at"
    case confirmedAt = "confirmed_at"
    case emailConfirmedAt = "email_confirmed_at"
    case phoneConfirmedAt = "phone_confirmed_at"
    case lastSignInAt = "last_sign_in_at"
    case role
    case updatedAt = "updated_at"
    case identities
  }
}

public struct UserIdentity: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var userID: UUID
  public var identityData: [String: AnyJSON]
  public var provider: String
  public var createdAt: Date
  public var lastSignInAt: Date
  public var updatedAt: Date

  public init(
    id: String,
    userID: UUID,
    identityData: [String: AnyJSON],
    provider: String,
    createdAt: Date,
    lastSignInAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.userID = userID
    self.identityData = identityData
    self.provider = provider
    self.createdAt = createdAt
    self.lastSignInAt = lastSignInAt
    self.updatedAt = updatedAt
  }

  public enum CodingKeys: String, CodingKey {
    case id
    case userID = "user_id"
    case identityData = "identity_data"
    case provider
    case createdAt = "created_at"
    case lastSignInAt = "last_sign_in_at"
    case updatedAt = "updated_at"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    userID = try container.decode(UUID.self, forKey: .userID)
    identityData =
      try container
      .decodeIfPresent([String: AnyJSON].self, forKey: .identityData) ?? [:]
    provider = try container.decode(String.self, forKey: .provider)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    lastSignInAt = try container.decode(Date.self, forKey: .lastSignInAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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

  public enum CodingKeys: String, CodingKey {
    case provider
    case idToken = "id_token"
    case accessToken = "access_token"
    case nonce
    case gotrueMetaSecurity = "gotrue_meta_security"
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

  public enum CodingKeys: String, CodingKey {
    case captchaToken = "captcha_token"
  }
}

public struct OTPParams: Codable, Hashable, Sendable {
  public var email: String?
  public var phone: String?
  public var createUser: Bool
  public var data: [String: AnyJSON]?
  public var gotrueMetaSecurity: GoTrueMetaSecurity?

  public init(
    email: String? = nil,
    phone: String? = nil,
    createUser: Bool? = nil,
    data: [String: AnyJSON]? = nil,
    gotrueMetaSecurity: GoTrueMetaSecurity? = nil
  ) {
    self.email = email
    self.phone = phone
    self.createUser = createUser ?? true
    self.data = data
    self.gotrueMetaSecurity = gotrueMetaSecurity
  }

  public enum CodingKeys: String, CodingKey {
    case email
    case phone
    case createUser = "create_user"
    case data
    case gotrueMetaSecurity = "gotrue_meta_security"
  }
}

public struct VerifyOTPParams: Codable, Hashable, Sendable {
  public var email: String?
  public var phone: String?
  public var token: String
  public var type: OTPType
  public var gotrueMetaSecurity: GoTrueMetaSecurity?

  public init(
    email: String? = nil,
    phone: String? = nil,
    token: String,
    type: OTPType,
    gotrueMetaSecurity: GoTrueMetaSecurity? = nil
  ) {
    self.email = email
    self.phone = phone
    self.token = token
    self.type = type
    self.gotrueMetaSecurity = gotrueMetaSecurity
  }

  public enum CodingKeys: String, CodingKey {
    case email
    case phone
    case token
    case type
    case gotrueMetaSecurity = "gotrue_meta_security"
  }
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

  public enum CodingKeys: String, CodingKey {
    case email
    case phone
    case password
    case emailChangeToken = "email_change_token"
    case data
  }
}

public struct RecoverParams: Codable, Hashable, Sendable {
  public var email: String
  public var gotrueMetaSecurity: GoTrueMetaSecurity?

  public init(email: String, gotrueMetaSecurity: GoTrueMetaSecurity? = nil) {
    self.email = email
    self.gotrueMetaSecurity = gotrueMetaSecurity
  }

  public enum CodingKeys: String, CodingKey {
    case email
    case gotrueMetaSecurity = "gotrue_meta_security"
  }
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
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let string = dateFormatter.string(from: date)
      try container.encode(string)
    }
    return encoder
  }()
}
