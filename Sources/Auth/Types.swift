public import Foundation
import Helpers

/// An event emitted when the authentication state of the current user changes.
///
/// New events can be added in a minor release, so a `switch` over this value needs a `default:`
/// case.
public struct AuthEvent: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  /// Creates an ``AuthEvent`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``AuthEvent`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Emitted when an initial session is loaded from local storage on startup.
  ///
  /// While storage cannot be read, for example after a launch into the background before the
  /// first unlock, this event waits. It fires once storage is read, or just before the first
  /// other event if that comes first.
  public static let initialSession: AuthEvent = "INITIAL_SESSION"

  /// Emitted when a password-recovery email link is clicked, making the session available.
  public static let passwordRecovery: AuthEvent = "PASSWORD_RECOVERY"

  /// Emitted when a user signs in or a new session is established.
  public static let signedIn: AuthEvent = "SIGNED_IN"

  /// Emitted when a user signs out.
  public static let signedOut: AuthEvent = "SIGNED_OUT"

  /// Emitted when the access token is refreshed.
  public static let tokenRefreshed: AuthEvent = "TOKEN_REFRESHED"

  /// Emitted when the user's data is updated.
  public static let userUpdated: AuthEvent = "USER_UPDATED"

  /// Emitted when an MFA challenge is successfully verified.
  public static let mfaChallengeVerified: AuthEvent = "MFA_CHALLENGE_VERIFIED"
}

struct UserCredentials: Encodable, Hashable, Sendable {
  var email: String?
  var password: String?
  var phone: String?
  var refreshToken: String?
  var gotrueMetaSecurity: AuthMetaSecurity?

  private enum CodingKeys: String, CodingKey {
    case email
    case password
    case phone
    case refreshToken = "refresh_token"
    case gotrueMetaSecurity = "gotrue_meta_security"
  }

  init(
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

struct SignUpRequest: Encodable, Hashable, Sendable {
  var email: String?
  var password: String?
  var phone: String?
  var channel: MessagingChannel?
  var data: JSONObject?
  var gotrueMetaSecurity: AuthMetaSecurity?
  var codeChallenge: String?
  var codeChallengeMethod: String?

  private enum CodingKeys: String, CodingKey {
    case email
    case password
    case phone
    case channel
    case data
    case gotrueMetaSecurity = "gotrue_meta_security"
    case codeChallenge = "code_challenge"
    case codeChallengeMethod = "code_challenge_method"
  }
}

struct IDTokenBody: Encodable, Hashable, Sendable {
  var provider: String
  var idToken: String
  var accessToken: String?
  var nonce: String?
  var gotrueMetaSecurity: AuthMetaSecurity?
  var linkIdentity: Bool

  private enum CodingKeys: String, CodingKey {
    case provider
    case idToken = "id_token"
    case accessToken = "access_token"
    case nonce
    case gotrueMetaSecurity = "gotrue_meta_security"
    case linkIdentity = "link_identity"
  }
}

struct Web3Body: Encodable, Hashable, Sendable {
  var chain: Web3Chain
  var message: String
  var signature: String
  var gotrueMetaSecurity: AuthMetaSecurity?

  private enum CodingKeys: String, CodingKey {
    case chain
    case message
    case signature
    case gotrueMetaSecurity = "gotrue_meta_security"
  }
}

extension JSONObject {
  /// `nil` for an empty object, so the request leaves the field out.
  var nilIfEmpty: JSONObject? { isEmpty ? nil : self }
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

  /// A valid JWT that will expire ``Session/expiresIn`` after the server issued it.
  ///
  /// It is recommended to set the `JWT_EXPIRY` to a shorter expiry value.
  public var accessToken: String

  /// The token type. Currently only `bearer` is returned; this may change in the future.
  public var tokenType: String

  /// How long after the server issued the session the ``Session/accessToken`` should be renewed
  /// by using the refresh token with the `refresh_token` grant type.
  public var expiresIn: Duration

  /// The time after which the ``Session/accessToken`` should be renewed by using the refresh
  /// token with the `refresh_token` grant type. This is the server's value, on the server's
  /// clock. ``isExpired(at:leeway:)`` judges expiry from ``receivedAt`` and ``expiresIn``.
  public var expiresAt: Date

  /// When this client received the session, on the device clock.
  ///
  /// The client refreshes the session ``expiresIn`` after this time, so a device clock that
  /// disagrees with the server's cannot move the refresh. A session you decode yourself has the
  /// time the server issued it, `expiresAt - expiresIn`.
  public var receivedAt: Date

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
  ///   - expiresIn: How long after the server issued the session the access token expires.
  ///   - expiresAt: The time at which the access token expires, on the server's clock.
  ///   - receivedAt: When the session was received. Defaults to now.
  ///   - refreshToken: Opaque refresh token string.
  ///   - weakPassword: Weak-password information returned by the server, if any.
  ///   - user: The authenticated user.
  public init(
    providerToken: String? = nil,
    providerRefreshToken: String? = nil,
    accessToken: String,
    tokenType: String,
    expiresIn: Duration,
    expiresAt: Date,
    receivedAt: Date = .now,
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
    self.receivedAt = receivedAt
    self.refreshToken = refreshToken
    self.weakPassword = weakPassword
    self.user = user
  }

  /// Returns `true` if the access token is expired or will expire within `leeway`.
  ///
  /// The leeway accounts for network latency. The expiry is ``receivedAt`` plus ``expiresIn`` on
  /// the device clock. A server ``expiresAt`` that is up to a minute earlier moves it earlier, to
  /// cover latency. A server value further off is on another clock, and is ignored.
  ///
  /// - Parameters:
  ///   - date: The time to judge the session at. Defaults to now.
  ///   - leeway: How long before the expiry the session counts as expired. Defaults to 30 seconds.
  public func isExpired(at date: Date = .now, leeway: Duration = .seconds(30)) -> Bool {
    remainingLifetime(at: date) < leeway
  }
}

extension Session {
  static let clockSkewTolerance: Duration = .seconds(60)

  /// When the access token expires, on the device clock.
  var expiryDate: Date {
    let local = localExpiryDate
    // Beyond the tolerance the server value is on another clock. Bounding by it would make a
    // device clock that runs ahead see every new token as expired and refresh in a loop.
    if expiresAt < local, local.duration(since: expiresAt) <= Self.clockSkewTolerance {
      return expiresAt
    }
    return local
  }

  var hasClockSkew: Bool {
    let skew = localExpiryDate.duration(since: expiresAt)
    return skew > Self.clockSkewTolerance || skew < .zero - Self.clockSkewTolerance
  }

  private var localExpiryDate: Date {
    receivedAt.adding(expiresIn)
  }

  func remainingLifetime(at date: Date) -> Duration {
    expiryDate.duration(since: date)
  }

  /// The session as the client received it at `date`.
  func received(at date: Date) -> Session {
    var session = self
    session.receivedAt = date
    return session
  }
}

extension KeyedDecodingContainer {
  /// A date that the server sends as seconds since 1970.
  func decodeUnixDate(forKey key: Key) throws -> Date {
    Date(timeIntervalSince1970: try decode(TimeInterval.self, forKey: key))
  }
}

extension Session {
  private enum CodingKeys: String, CodingKey {
    case providerToken = "provider_token"
    case providerRefreshToken = "provider_refresh_token"
    case accessToken = "access_token"
    case tokenType = "token_type"
    case expiresIn = "expires_in"
    case expiresAt = "expires_at"
    case receivedAt = "received_at"
    case refreshToken = "refresh_token"
    case weakPassword = "weak_password"
    case user
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let seconds = try container.decode(Double.self, forKey: .expiresIn)
    guard let expiresIn = Duration(validSeconds: seconds) else {
      throw DecodingError.dataCorruptedError(
        forKey: .expiresIn, in: container, debugDescription: "expires_in is out of range.")
    }
    let expiresAt = try container.decodeUnixDate(forKey: .expiresAt)
    let receivedAt =
      try container.decodeIfPresent(TimeInterval.self, forKey: .receivedAt)
      .map(Date.init(timeIntervalSince1970:))
      ?? expiresAt.adding(.zero - expiresIn)
    self.init(
      providerToken: try container.decodeIfPresent(String.self, forKey: .providerToken),
      providerRefreshToken: try container.decodeIfPresent(
        String.self, forKey: .providerRefreshToken),
      accessToken: try container.decode(String.self, forKey: .accessToken),
      tokenType: try container.decode(String.self, forKey: .tokenType),
      expiresIn: expiresIn,
      expiresAt: expiresAt,
      receivedAt: receivedAt,
      refreshToken: try container.decode(String.self, forKey: .refreshToken),
      weakPassword: try container.decodeIfPresent(WeakPassword.self, forKey: .weakPassword),
      user: try container.decode(User.self, forKey: .user)
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(providerToken, forKey: .providerToken)
    try container.encodeIfPresent(providerRefreshToken, forKey: .providerRefreshToken)
    try container.encode(accessToken, forKey: .accessToken)
    try container.encode(tokenType, forKey: .tokenType)
    try container.encode(expiresIn.timeInterval, forKey: .expiresIn)
    try container.encode(expiresAt.timeIntervalSince1970, forKey: .expiresAt)
    try container.encode(receivedAt.timeIntervalSince1970, forKey: .receivedAt)
    try container.encode(refreshToken, forKey: .refreshToken)
    try container.encodeIfPresent(weakPassword, forKey: .weakPassword)
    try container.encode(user, forKey: .user)
  }
}

extension Session: CustomStringConvertible {
  /// The user ID and the expiry of the session. It holds no token, so logging a session does
  /// not leak one.
  public var description: String {
    "Session(user_id: \(user.id), expires_at: \(expiresAt.timeIntervalSince1970))"
  }
}

/// A Supabase Auth user record.
public struct User: Codable, Hashable, Identifiable, Sendable {
  /// The unique identifier of the user.
  public var id: UUID

  /// Application-specific metadata stored by the administrator in `auth.users.app_metadata`.
  public var appMetadata: JSONObject

  /// User-supplied metadata stored in `auth.users.raw_user_meta_data`.
  public var userMetadata: JSONObject

  /// The audience claim (`aud`) of the user's JWT.
  public var audience: String

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
  public var actionLink: URL?

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
  ///   - audience: The JWT audience claim.
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
    appMetadata: JSONObject,
    userMetadata: JSONObject,
    audience: String,
    confirmationSentAt: Date? = nil,
    recoverySentAt: Date? = nil,
    emailChangeSentAt: Date? = nil,
    newEmail: String? = nil,
    invitedAt: Date? = nil,
    actionLink: URL? = nil,
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
    self.audience = audience
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

  private enum CodingKeys: String, CodingKey {
    case id
    case appMetadata = "app_metadata"
    case userMetadata = "user_metadata"
    case audience = "aud"
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
    case isAnonymous = "is_anonymous"
    case factors
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    appMetadata =
      try container.decodeIfPresent(JSONObject.self, forKey: .appMetadata) ?? [:]
    userMetadata =
      try container.decodeIfPresent(JSONObject.self, forKey: .userMetadata) ?? [:]
    audience = try container.decode(String.self, forKey: .audience)
    confirmationSentAt = try container.decodeIfPresent(Date.self, forKey: .confirmationSentAt)
    recoverySentAt = try container.decodeIfPresent(Date.self, forKey: .recoverySentAt)
    emailChangeSentAt = try container.decodeIfPresent(Date.self, forKey: .emailChangeSentAt)
    newEmail = try container.decodeIfPresent(String.self, forKey: .newEmail)
    invitedAt = try container.decodeIfPresent(Date.self, forKey: .invitedAt)
    actionLink = try container.decodeIfPresent(URL.self, forKey: .actionLink)
    // GoTrue sends `""`, never `null`, for a user without an email or phone.
    email = try container.decodeIfPresent(String.self, forKey: .email).flatMap {
      $0.isEmpty ? nil : $0
    }
    phone = try container.decodeIfPresent(String.self, forKey: .phone).flatMap {
      $0.isEmpty ? nil : $0
    }
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    confirmedAt = try container.decodeIfPresent(Date.self, forKey: .confirmedAt)
    emailConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .emailConfirmedAt)
    phoneConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .phoneConfirmedAt)
    lastSignInAt = try container.decodeIfPresent(Date.self, forKey: .lastSignInAt)
    role = try container.decodeIfPresent(String.self, forKey: .role)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    identities = try container.decodeIfPresent([UserIdentity].self, forKey: .identities)
    isAnonymous = try container.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? false
    // GoTrue omits `factors` when the user has none.
    factors = try container.decodeIfPresent([Factor].self, forKey: .factors) ?? []
  }
}

extension User {
  /// Decodes ``userMetadata`` into a type of your own.
  ///
  /// This method encodes ``userMetadata`` to JSON and decodes it with a plain `JSONDecoder`. The
  /// decoder uses the keys as stored. It does not convert snake case keys, so name the properties
  /// of `T` after the stored keys, or give `T` its own coding keys.
  ///
  /// ```swift
  /// struct Profile: Decodable {
  ///   let displayName: String
  ///
  ///   enum CodingKeys: String, CodingKey {
  ///     case displayName = "display_name"
  ///   }
  /// }
  ///
  /// let profile = try user.userMetadata(as: Profile.self)
  /// ```
  ///
  /// - Parameter type: The type to decode.
  /// - Returns: The decoded metadata.
  /// - Throws: `DecodingError` when the metadata does not match `T`.
  public func userMetadata<T: Decodable>(as type: T.Type = T.self) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(userMetadata))
  }
}

/// A third-party identity linked to a ``User``.
///
/// The properties are named for what they hold, not for the JSON keys of the Auth server. The
/// server sends the Supabase identity UUID as `identity_id` and the provider's user ID as `id`.
/// This type swaps them, so ``id`` is the identity UUID, as `Identifiable` and
/// ``AuthClient/unlinkIdentity(_:)`` expect:
///
/// | Property | JSON key | Value |
/// |---|---|---|
/// | ``id`` | `identity_id` | The Supabase identity UUID. |
/// | ``providerUserID`` | `id` | The user's ID at the provider. |
/// | ``userID`` | `user_id` | The UUID of the user. |
///
/// > Note: supabase-js keeps the JSON keys, so its `UserIdentity.id` is the provider's user ID.
/// > Use ``providerUserID`` for that value in Swift.
///
/// ```swift
/// let identities = try await supabase.auth.identities()
/// if let google = identities.first(where: { $0.provider == .google }) {
///   print(google.providerUserID)  // The user's Google account ID
///   try await supabase.auth.unlinkIdentity(google)  // Sends google.id
/// }
/// ```
public struct UserIdentity: Codable, Hashable, Identifiable, Sendable {
  /// The Supabase identity UUID, sent as `identity_id`.
  ///
  /// ``AuthClient/unlinkIdentity(_:)`` sends this value. It is not the provider's user ID; for
  /// that, read ``providerUserID``.
  public var id: UUID

  /// The user's ID at the provider, sent as `id`.
  ///
  /// For an OpenID Connect provider, it is the `sub` claim of the provider's ID token.
  public var providerUserID: String

  /// The UUID of the user that this identity belongs to, sent as `user_id`.
  public var userID: UUID

  /// The provider of this identity.
  public var provider: Provider

  /// Provider-specific identity data returned by the third party. Empty when the server sends
  /// none.
  public var identityData: JSONObject

  /// The email address of this identity, or `nil` when the server sends none.
  ///
  /// The Auth server takes it from the provider, so it can differ from ``User/email``.
  public var email: String?

  /// Timestamp when this identity was created.
  public var createdAt: Date?

  /// Timestamp of the last sign-in with this identity.
  public var lastSignInAt: Date?

  /// Timestamp when this identity record was last updated.
  public var updatedAt: Date?

  /// Creates a new user identity value.
  ///
  /// - Parameters:
  ///   - id: The Supabase identity UUID, the `identity_id` JSON key.
  ///   - providerUserID: The user's ID at the provider, the `id` JSON key.
  ///   - userID: The UUID of the user that owns the identity.
  ///   - provider: The provider of the identity.
  ///   - identityData: Provider-specific identity data.
  ///   - email: The email address of the identity.
  ///   - createdAt: Timestamp the identity was created.
  ///   - lastSignInAt: Timestamp of the last sign-in via this identity.
  ///   - updatedAt: Timestamp the identity was last updated.
  public init(
    id: UUID,
    providerUserID: String,
    userID: UUID,
    provider: Provider,
    identityData: JSONObject = [:],
    email: String? = nil,
    createdAt: Date? = nil,
    lastSignInAt: Date? = nil,
    updatedAt: Date? = nil
  ) {
    self.id = id
    self.providerUserID = providerUserID
    self.userID = userID
    self.provider = provider
    self.identityData = identityData
    self.email = email
    self.createdAt = createdAt
    self.lastSignInAt = lastSignInAt
    self.updatedAt = updatedAt
  }

  // The wire `identity_id` maps to `id`, and the wire `id` maps to `providerUserID`.
  enum CodingKeys: String, CodingKey {
    case id = "identity_id"
    case providerUserID = "id"
    case userID = "user_id"
    case provider
    case identityData = "identity_data"
    case email
    case createdAt = "created_at"
    case lastSignInAt = "last_sign_in_at"
    case updatedAt = "updated_at"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decode(UUID.self, forKey: .id)
    providerUserID = try container.decode(String.self, forKey: .providerUserID)
    userID = try container.decode(UUID.self, forKey: .userID)
    provider = try container.decode(Provider.self, forKey: .provider)
    // GoTrue omits `identity_data` when it is empty.
    identityData = try container.decodeIfPresent(JSONObject.self, forKey: .identityData) ?? [:]
    email = try container.decodeIfPresent(String.self, forKey: .email)
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    lastSignInAt = try container.decodeIfPresent(Date.self, forKey: .lastSignInAt)
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
  }
}

/// One of the providers supported by Auth.
///
/// A provider encodes and decodes as its ``rawValue`` string.
public struct Provider: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  /// Creates a ``Provider`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``Provider`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public static let apple: Provider = "apple"
  public static let azure: Provider = "azure"
  public static let bitbucket: Provider = "bitbucket"
  public static let discord: Provider = "discord"
  public static let email: Provider = "email"
  public static let facebook: Provider = "facebook"
  public static let figma: Provider = "figma"
  public static let github: Provider = "github"
  public static let gitlab: Provider = "gitlab"
  public static let google: Provider = "google"
  public static let kakao: Provider = "kakao"
  public static let keycloak: Provider = "keycloak"
  public static let linkedin: Provider = "linkedin"
  public static let linkedinOIDC: Provider = "linkedin_oidc"
  public static let notion: Provider = "notion"
  public static let slack: Provider = "slack"
  public static let slackOIDC: Provider = "slack_oidc"
  public static let spotify: Provider = "spotify"
  public static let twitch: Provider = "twitch"

  /// Uses OAuth 1.0a
  public static let twitter: Provider = "twitter"

  /// Uses OAuth 2.0
  public static let x: Provider = "x"

  public static let workos: Provider = "workos"
  public static let zoom: Provider = "zoom"
  public static let fly: Provider = "fly"
}

/// Credentials for signing in with an ID token that a third-party identity provider issued, such
/// as Sign in with Apple or Google Sign-In.
///
/// When the provider takes a nonce, pass ``Nonce/generate()``'s `hashed` value to the provider
/// and its `raw` value here. The server hashes `nonce` and compares the result with the token's
/// `nonce` claim.
public struct IDTokenCredentials: Sendable, Hashable {
  /// The provider that issued the token, such as ``Provider/apple`` or ``Provider/google``, or
  /// the token's `iss` value for a custom OIDC provider.
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

/// A captcha verification token, in the shape the server reads it.
struct AuthMetaSecurity: Encodable, Hashable, Sendable {
  var captchaToken: String

  private enum CodingKeys: String, CodingKey {
    case captchaToken = "captcha_token"
  }
}

/// A Web3 chain supported by Sign in with Web3.
public struct Web3Chain: RawRepresentable, Encodable, Hashable, Sendable, ExpressibleByStringLiteral
{
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
public struct Web3Credentials: Hashable, Sendable {
  /// The chain the message was signed for.
  public var chain: Web3Chain

  /// The SIWE- or SIWS-formatted message that was signed.
  public var message: String

  /// The signature over `message`.
  /// - Ethereum: `0x`-prefixed 65-byte secp256k1 signature, hex-encoded (130 hex chars after `0x`).
  /// - Solana: base64 (standard or URL-safe, padded or not) encoding of the 64-byte Ed25519 signature.
  public var signature: String

  /// The token the user received for completing a captcha.
  public var captchaToken: String?

  /// Creates Web3 credentials for sign-in.
  ///
  /// - Parameters:
  ///   - chain: The Web3 chain the message was signed for.
  ///   - message: The SIWE/SIWS-formatted message that was signed.
  ///   - signature: The signature over `message`.
  ///   - captchaToken: The token the user received for completing a captcha.
  public init(
    chain: Web3Chain,
    message: String,
    signature: String,
    captchaToken: String? = nil
  ) {
    self.chain = chain
    self.message = message
    self.signature = signature
    self.captchaToken = captchaToken
  }
}

/// Options for ``AuthClient/signInWithOTP(email:options:)``.
public struct EmailOTPOptions: Sendable, Hashable {
  /// Whether the server creates a user when none exists for the email. The default is `true`.
  /// When `false`, the call fails for an unknown user.
  public var shouldCreateUser: Bool

  /// Data to store on the user if the call creates one.
  public var userMetadata: JSONObject

  /// The URL the email link redirects to. When `nil`, the client uses
  /// ``AuthClient/Configuration/redirectTo``.
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

/// The `{"message_id": …}` body of a phone `/otp` or `/resend` response.
struct MessageIDBody: Decodable {
  let messageID: MessageID?

  private enum CodingKeys: String, CodingKey {
    case messageID = "message_id"
  }
}

struct OTPParams: Encodable, Hashable, Sendable {
  var email: String?
  var phone: String?
  var createUser: Bool
  var channel: MessagingChannel?
  var data: JSONObject?
  var gotrueMetaSecurity: AuthMetaSecurity?
  var codeChallenge: String?
  var codeChallengeMethod: String?

  private enum CodingKeys: String, CodingKey {
    case email
    case phone
    case createUser = "create_user"
    case channel
    case data
    case gotrueMetaSecurity = "gotrue_meta_security"
    case codeChallenge = "code_challenge"
    case codeChallengeMethod = "code_challenge_method"
  }
}

enum VerifyOTPParams: Encodable {
  case email(VerifyEmailOTPParams)
  case phone(VerifyPhoneOTPParams)
  case tokenHash(VerifyTokenHashParams)

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .email(let value):
      try container.encode(value)
    case .phone(let value):
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
}

struct VerifyTokenHashParams: Encodable, Hashable, Sendable {
  var tokenHash: String
  var type: EmailOTPType

  private enum CodingKeys: String, CodingKey {
    case tokenHash = "token_hash"
    case type
  }
}

struct VerifyPhoneOTPParams: Encodable, Hashable {
  var phone: String
  var token: String
  var type: PhoneOTPType
}

/// The kind of phone one-time password that ``AuthClient/verifyOTP(phone:token:type:)``
/// checks.
public struct PhoneOTPType: RawRepresentable, Encodable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates a ``PhoneOTPType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``PhoneOTPType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// A code sent to sign in or to confirm the phone number, by SMS or WhatsApp.
  public static let sms: PhoneOTPType = "sms"

  /// A code sent to confirm a phone number change.
  public static let phoneChange: PhoneOTPType = "phone_change"
}

/// The kind of email one-time password or token hash that
/// ``AuthClient/verifyOTP(email:token:type:)`` and
/// ``AuthClient/verifyOTP(tokenHash:type:)`` check.
public struct EmailOTPType: RawRepresentable, Encodable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates an ``EmailOTPType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``EmailOTPType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// OTP sent during initial sign-up email confirmation.
  public static let signup: EmailOTPType = "signup"

  /// OTP sent when an admin invites a user by email.
  public static let invite: EmailOTPType = "invite"

  /// OTP sent as part of a magic-link sign-in flow.
  public static let magiclink: EmailOTPType = "magiclink"

  /// OTP sent when the user requests a password reset.
  public static let recovery: EmailOTPType = "recovery"

  /// OTP sent when the user requests an email address change.
  public static let emailChange: EmailOTPType = "email_change"

  /// Generic email OTP.
  public static let email: EmailOTPType = "email"
}

/// The result of ``AuthClient/signUp(email:password:options:)`` and
/// ``AuthClient/signUp(phone:password:options:)``.
///
/// Switch on the result to learn whether the user is signed in:
///
/// ```swift
/// switch try await client.auth.signUp(email: email, password: password) {
/// case .signedIn(let session):
///   showHome(for: session.user)
/// case .confirmationRequired(let user):
///   showCheckYourInbox(for: user)
/// }
/// ```
public enum SignUpResult: Decodable, Hashable, Sendable {
  /// The account is active and the user is signed in. The client stored the session and emitted
  /// ``AuthEvent/signedIn``.
  case signedIn(Session)

  /// The server sent a confirmation email or SMS. The user is not signed in until they confirm.
  ///
  /// When email confirmation is on and the email or phone number already belongs to a confirmed
  /// account, the server does not say so. It returns a fake user with an empty `identities`
  /// list instead, and sends no message. A real new user has one identity. The SDK returns
  /// either user as is.
  case confirmationRequired(User)

  public init(from decoder: any Decoder) throws {
    self =
      try decoder.isSessionBody()
      ? .signedIn(Session(from: decoder))
      : .confirmationRequired(User(from: decoder))
  }

  func received(at date: Date) -> SignUpResult {
    switch self {
    case .signedIn(let session): .signedIn(session.received(at: date))
    case .confirmationRequired: self
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
  /// the client uses ``AuthClient/Configuration/redirectTo``.
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

private enum SessionKeys: String, CodingKey {
  case accessToken = "access_token"
  case refreshToken = "refresh_token"
  case expiresIn = "expires_in"
}

extension Decoder {
  /// Whether the body is a session, the test auth-js applies: `access_token`, `refresh_token`,
  /// and `expires_in` are all present. `/signup` otherwise returns a bare user, and `/verify` the
  /// `{msg, code}` of a half-confirmed email change.
  func isSessionBody() throws -> Bool {
    let container = try container(keyedBy: SessionKeys.self)
    return container.contains(.accessToken) && container.contains(.refreshToken)
      && container.contains(.expiresIn)
  }
}

/// The result of ``AuthClient/verifyOTP(email:token:type:)`` and
/// ``AuthClient/verifyOTP(tokenHash:type:)``.
///
/// ```swift
/// switch try await client.auth.verifyOTP(email: email, token: code, type: .email) {
/// case .signedIn(let session):
///   showHome(for: session.user)
/// case .emailChangePending(let message):
///   showMessage(message)
/// }
/// ```
public enum VerifyOTPResult: Sendable, Hashable {
  /// The code was valid and the user is signed in. The client stored the session and emitted one
  /// auth event: ``AuthEvent/passwordRecovery`` for ``EmailOTPType/recovery``,
  /// ``AuthEvent/userUpdated`` for an email or phone change of the signed-in user, and
  /// ``AuthEvent/signedIn`` otherwise.
  case signedIn(Session)

  /// The first of the two confirmations of a secure email change. The other address must confirm
  /// its link too before the change takes effect. The client stored no session and emitted no
  /// event. `message` comes from the server and is meant for display.
  case emailChangePending(message: String)

  func received(at date: Date) -> VerifyOTPResult {
    switch self {
    case .signedIn(let session): .signedIn(session.received(at: date))
    case .emailChangePending: self
    }
  }
}

/// A `/verify` response body: a session, or the `{"msg": …}` body of the first half of a secure
/// email change.
struct VerifyOTPBody: Decodable {
  let result: VerifyOTPResult

  private enum CodingKeys: String, CodingKey {
    case message = "msg"
  }

  init(from decoder: any Decoder) throws {
    result =
      try decoder.isSessionBody()
      ? .signedIn(Session(from: decoder))
      : .emailChangePending(
        message: decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .message))
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

/// The new user for ``AuthAdminClient/createUser(_:)``.
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

  /// Creates the new user for ``AuthAdminClient/createUser(_:)``.
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

/// The changes for ``AuthAdminClient/updateUser(id:_:)``. The server changes only the fields
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

  /// Creates the changes for ``AuthAdminClient/updateUser(id:_:)``.
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
  /// The duration of `seconds`, or `nil` when it is not a finite number within about 30,000
  /// years. `Duration.seconds(_:)` traps on such a value, and a server, a URL, or stored data
  /// can send one.
  init?(validSeconds seconds: Double) {
    guard seconds.isFinite, abs(seconds) <= 1e12 else { return nil }
    self = .seconds(seconds)
  }

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

struct RecoverParams: Encodable, Hashable, Sendable {
  var email: String
  var gotrueMetaSecurity: AuthMetaSecurity?
  var codeChallenge: String?
  var codeChallengeMethod: String?

  private enum CodingKeys: String, CodingKey {
    case email
    case gotrueMetaSecurity = "gotrue_meta_security"
    case codeChallenge = "code_challenge"
    case codeChallengeMethod = "code_challenge_method"
  }
}

/// The kind of an MFA factor.
public struct FactorType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates a ``FactorType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``FactorType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// A time-based one-time password from an authenticator app.
  public static let totp: FactorType = "totp"

  /// A one-time code sent to a phone by SMS or WhatsApp.
  public static let phone: FactorType = "phone"

  /// A WebAuthn credential, such as a passkey or a security key.
  public static let webAuthn: FactorType = "webauthn"

  /// A set of single-use recovery codes. See ``AuthMFA/recoveryCodes``.
  public static let recoveryCode: FactorType = "recovery_code"
}

/// The enrollment status of an MFA factor.
public struct FactorStatus: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates a ``FactorStatus`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``FactorStatus`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// The factor has been verified and is active.
  public static let verified: FactorStatus = "verified"

  /// The factor has been enrolled but not yet verified.
  public static let unverified: FactorStatus = "unverified"
}

/// An MFA Factor.
public struct Factor: Identifiable, Codable, Hashable, Sendable {
  /// ID of the factor.
  public let id: UUID

  /// Friendly name of the factor, useful to disambiguate between multiple factors.
  public let friendlyName: String?

  /// Type of factor.
  public let factorType: FactorType

  /// Factor's status.
  public let status: FactorStatus

  /// Timestamp when the factor was created.
  public let createdAt: Date

  /// Timestamp when the factor was last updated.
  public let updatedAt: Date

  private enum CodingKeys: String, CodingKey {
    case id
    case friendlyName = "friendly_name"
    case factorType = "factor_type"
    case status
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// The body of `POST /factors`. Each `enroll` method of ``AuthMFA`` fills the fields of its factor
/// type; the encoder omits the rest.
struct MFAEnrollParams: Encodable, Sendable {
  let factorType: FactorType
  var friendlyName: String?
  var issuer: String?
  var phone: String?

  private enum CodingKeys: String, CodingKey {
    case factorType = "factor_type"
    case friendlyName = "friendly_name"
    case issuer
    case phone
  }

  static func totp(issuer: String? = nil, friendlyName: String? = nil) -> Self {
    MFAEnrollParams(factorType: .totp, friendlyName: friendlyName, issuer: issuer)
  }

  static func phone(_ phone: String, friendlyName: String? = nil) -> Self {
    MFAEnrollParams(factorType: .phone, friendlyName: friendlyName, phone: phone)
  }

  static func webAuthn(friendlyName: String? = nil) -> Self {
    MFAEnrollParams(factorType: .webAuthn, friendlyName: friendlyName)
  }
}

/// A TOTP factor created by ``AuthMFA/enrollTOTP(issuer:friendlyName:)``.
///
/// The factor is `unverified` until the user enters a code from their authenticator app in
/// ``AuthMFA/challengeAndVerify(factorID:code:)``.
public struct TOTPEnrollment: Identifiable, Hashable, Sendable {
  /// ID of the new factor.
  public let id: UUID

  /// Friendly name of the factor, useful to tell several factors apart.
  public let friendlyName: String?

  /// A QR code that encodes ``uri``, as an SVG document. Display it by prefixing
  /// `data:image/svg+xml;utf-8,`. Avoid logging this value.
  public let qrCode: String

  /// The TOTP secret, also encoded in the QR code. Show it in a password-style field for users who
  /// cannot scan the QR code. Avoid logging this value.
  public let secret: String

  /// The `otpauth://` URI encoded in the QR code. Avoid logging this value.
  public let uri: String
}

extension TOTPEnrollment: Decodable {
  private enum CodingKeys: String, CodingKey {
    case id
    case friendlyName = "friendly_name"
    case totp
  }

  private struct TOTP: Decodable {
    let qrCode: String
    let secret: String
    let uri: String

    private enum CodingKeys: String, CodingKey {
      case qrCode = "qr_code"
      case secret
      case uri
    }
  }

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
  public let id: UUID

  /// Friendly name of the factor, useful to tell several factors apart.
  public let friendlyName: String?

  /// The phone number of the factor, in E.164 format.
  public let phone: String

  private enum CodingKeys: String, CodingKey {
    case id
    case friendlyName = "friendly_name"
    case phone
  }
}

/// A challenge created by ``AuthMFA/challenge(factorID:channel:)``.
public struct MFAChallenge: Identifiable, Hashable, Sendable {
  /// ID of the challenge. Pass it to ``AuthMFA/verify(factorID:challengeID:code:)``.
  public let id: UUID

  /// The type of the factor that was challenged.
  public let factorType: FactorType

  /// The time after which the challenge can no longer be verified.
  public let expiresAt: Date

  /// WebAuthn credential options. Present only when ``factorType`` is ``FactorType/webAuthn``.
  @_spi(Experimental) public var webauthn: WebAuthnChallengeResponseData? = nil
}

extension MFAChallenge: Decodable {
  private enum CodingKeys: String, CodingKey {
    case id
    case type
    case expiresAt = "expires_at"
    case webauthn
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      factorType: try container.decode(FactorType.self, forKey: .type),
      expiresAt: try container.decodeUnixDate(forKey: .expiresAt),
      webauthn: try container.decodeIfPresent(
        WebAuthnChallengeResponseData.self, forKey: .webauthn)
    )
  }
}

/// The response returned after successfully unenrolling an MFA factor.
public struct AuthMFAUnenrollResponse: Decodable, Hashable, Sendable {
  /// ID of the factor that was successfully unenrolled.
  public let id: UUID
}

/// The response returned by ``AuthMFARecoveryCodes/status()``.
public struct AuthMFARecoveryCodesStatusResponse: Decodable, Hashable, Sendable {
  /// ID of the recovery codes factor, as it appears in ``User/factors``.
  public let id: UUID

  /// Number of codes in the current set.
  public let total: Int

  /// Number of codes in the current set that have not been used yet. Zero when every code has been
  /// consumed.
  public let remaining: Int
}

/// The response returned by ``AuthMFARecoveryCodes/generate(friendlyName:)`` and
/// ``AuthMFARecoveryCodes/regenerate()``.
public struct AuthMFARecoveryCodesGenerateResponse: Decodable, Hashable, Sendable {
  /// ID of the recovery codes factor.
  public let id: UUID

  /// Friendly name of the recovery codes factor.
  public var friendlyName: String?

  /// Number of codes in the new set.
  public let total: Int

  /// The codes themselves. Returned only here, so show them to the user and ask them to store
  /// the codes safely.
  public let codes: [String]

  private enum CodingKeys: String, CodingKey {
    case id
    case friendlyName = "friendly_name"
    case total
    case codes
  }
}

/// The user's MFA factors, returned by ``AuthMFA/factors()``.
public struct MFAFactors: Hashable, Sendable {
  /// Factors the user has verified. Only these count toward reaching `aal2`.
  ///
  /// It includes the user's ``FactorType/recoveryCode`` factor, which cannot be challenged. Filter
  /// on ``Factor/factorType`` to pick a factor to verify.
  public let verified: [Factor]

  /// Factors the user has enrolled but not verified yet.
  public let unverified: [Factor]

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

/// An Authenticator Assurance Level (AAL), the `aal` claim of an access token.
public struct AuthenticatorAssuranceLevel: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
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

/// A method the user verified their identity with, the `method` of an access token's `amr` entry.
public struct AuthenticationMethod: RawRepresentable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates an ``AuthenticationMethod`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates an ``AuthenticationMethod`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Sign-in with an OAuth provider.
  public static let oauth: AuthenticationMethod = "oauth"
  /// Sign-in with a password.
  public static let password: AuthenticationMethod = "password"
  /// Sign-in with a one-time password sent by email or phone.
  public static let otp: AuthenticationMethod = "otp"
  /// Verification of a TOTP factor.
  public static let totp: AuthenticationMethod = "totp"
  /// Sign-in through a password recovery link.
  public static let recovery: AuthenticationMethod = "recovery"
  /// Sign-in through an invite link.
  public static let invite: AuthenticationMethod = "invite"
  /// Sign-in with SAML single sign-on.
  public static let ssoSAML: AuthenticationMethod = "sso/saml"
  /// Sign-in with a magic link.
  public static let magicLink: AuthenticationMethod = "magiclink"
  /// Sign-in through an email sign-up confirmation link.
  public static let emailSignup: AuthenticationMethod = "email/signup"
  /// Sign-in through an email change confirmation link.
  public static let emailChange: AuthenticationMethod = "email_change"
  /// A session refresh.
  public static let tokenRefresh: AuthenticationMethod = "token_refresh"
  /// Anonymous sign-in.
  public static let anonymous: AuthenticationMethod = "anonymous"
  /// Verification of a phone factor.
  public static let mfaPhone: AuthenticationMethod = "mfa/phone"
  /// Verification of a WebAuthn factor.
  public static let mfaWebAuthn: AuthenticationMethod = "mfa/webauthn"
  /// Verification of a recovery code.
  public static let mfaRecoveryCode: AuthenticationMethod = "mfa/recovery_code"
  /// Sign-in with a Web3 wallet.
  public static let web3: AuthenticationMethod = "web3"
  /// Sign-in through the OAuth 2.1 server's authorization code grant.
  public static let oauthProviderAuthorizationCode: AuthenticationMethod =
    "oauth_provider/authorization_code"
  /// Sign-in with a passkey.
  public static let passkey: AuthenticationMethod = "passkey"
}

/// An authentication method reference (AMR) entry: a method the user verified their identity
/// with, and when.
public struct AMREntry: Hashable, Sendable {
  /// The method the user verified their identity with.
  public let method: AuthenticationMethod

  /// When the user verified their identity with ``method``.
  public let timestamp: Date
}

extension AMREntry {
  /// Reads one `amr` claim entry: GoTrue's `{"method", "timestamp"}` object, or the bare method
  /// string of RFC 8176 that a custom access token hook can emit. A bare string carries no time, so
  /// it takes the token's `iat`.
  init?(value: Any, issuedAt: TimeInterval?) {
    if let method = value as? String {
      guard let issuedAt else { return nil }
      self.init(
        method: AuthenticationMethod(rawValue: method),
        timestamp: Date(timeIntervalSince1970: issuedAt))
      return
    }

    guard let dict = value as? [String: Any],
      let method = dict["method"] as? String,
      let timestamp = dict["timestamp"] as? TimeInterval
    else {
      return nil
    }

    self.init(
      method: AuthenticationMethod(rawValue: method),
      timestamp: Date(timeIntervalSince1970: timestamp)
    )
  }
}

/// The assurance level of the current session, returned by ``AuthMFA/assuranceLevel()``.
public struct AssuranceLevelInfo: Hashable, Sendable {
  /// The assurance level of the current access token. `nil` when the token has no `aal` claim.
  public let currentLevel: AuthenticatorAssuranceLevel?

  /// The highest level the user can reach. When it is above ``currentLevel``, ask the user to
  /// verify a factor.
  public let nextLevel: AuthenticatorAssuranceLevel?

  /// The methods attached to the session, most recent first. Use them to find when the user last
  /// verified a factor, for example in a step-up flow.
  public let currentAuthenticationMethods: [AMREntry]
}

/// Which sessions ``AuthClient/signOut(scope:)`` ends.
///
/// Each scope changes the local session in its own way, so the set is closed.
public enum SignOutScope: String, Sendable {
  /// Every session of the user, including this one.
  case global
  /// This session only.
  case local
  /// Every session of the user except this one.
  case others
}

/// The kind of email that ``AuthClient/resend(email:type:options:)`` sends again.
public struct ResendEmailType: RawRepresentable, Encodable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates a ``ResendEmailType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``ResendEmailType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Resends the initial sign-up confirmation email.
  public static let signup: ResendEmailType = "signup"

  /// Resends the email-change confirmation email.
  public static let emailChange: ResendEmailType = "email_change"
}

struct ResendEmailParams: Encodable {
  let type: ResendEmailType
  let email: String
  let gotrueMetaSecurity: AuthMetaSecurity?
  let codeChallenge: String?
  let codeChallengeMethod: String?

  private enum CodingKeys: String, CodingKey {
    case type
    case email
    case gotrueMetaSecurity = "gotrue_meta_security"
    case codeChallenge = "code_challenge"
    case codeChallengeMethod = "code_challenge_method"
  }
}

/// The kind of phone code that ``AuthClient/resend(phone:type:options:)`` sends again.
public struct ResendPhoneType: RawRepresentable, Encodable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates a ``ResendPhoneType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``ResendPhoneType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Resends the SMS OTP for the current phone sign-in.
  public static let sms: ResendPhoneType = "sms"

  /// Resends the OTP for confirming a phone number change.
  public static let phoneChange: ResendPhoneType = "phone_change"
}

struct ResendPhoneParams: Encodable {
  let type: ResendPhoneType
  let phone: String
  let gotrueMetaSecurity: AuthMetaSecurity?

  private enum CodingKeys: String, CodingKey {
    case type
    case phone
    case gotrueMetaSecurity = "gotrue_meta_security"
  }
}

/// Information about why a password is considered weak.
public struct WeakPassword: Codable, Hashable, Sendable {
  /// List of reasons the password is too weak, could be any of `length`, `characters`, or `pwned`.
  public let reasons: [String]
}

struct DeleteUserRequest: Encodable {
  let shouldSoftDelete: Bool

  private enum CodingKeys: String, CodingKey {
    case shouldSoftDelete = "should_soft_delete"
  }
}

/// The messaging channel used to deliver OTPs.
public struct MessagingChannel: RawRepresentable, Encodable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  /// Creates a ``MessagingChannel`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``MessagingChannel`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// Deliver the OTP via SMS.
  public static let sms: MessagingChannel = "sms"

  /// Deliver the OTP via WhatsApp.
  public static let whatsapp: MessagingChannel = "whatsapp"
}

/// The identity provider that ``AuthClient/signInWithSSO(_:options:presenter:)`` signs in with.
public enum SSOTarget: Sendable, Hashable {
  /// The provider registered for this email domain, for example `"example.com"`.
  case domain(String)

  /// The provider with this ID.
  case providerID(UUID)
}

/// Options for ``AuthClient/signInWithSSO(_:options:presenter:)`` and
/// ``AuthClient/ssoSignInURL(_:options:)``.
public struct SSOOptions: Sendable, Hashable {
  /// The URL the server redirects to after the identity provider step. When `nil`, the client
  /// uses ``AuthClient/Configuration/redirectTo``.
  public var redirectTo: URL?

  /// The captcha verification token.
  public var captchaToken: String?

  /// Creates SSO options.
  ///
  /// - Parameters:
  ///   - redirectTo: The URL the server redirects to after the identity provider step.
  ///   - captchaToken: The captcha verification token.
  public init(redirectTo: URL? = nil, captchaToken: String? = nil) {
    self.redirectTo = redirectTo
    self.captchaToken = captchaToken
  }
}

/// Options for ``AuthClient/resend(email:type:options:)``.
public struct ResendEmailOptions: Sendable, Hashable {
  /// The URL the link redirects to. When `nil`, the client uses
  /// ``AuthClient/Configuration/redirectTo``.
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

/// Options for ``AuthClient/resetPassword(email:options:)``.
public struct ResetPasswordOptions: Sendable, Hashable {
  /// The URL the link redirects to. When `nil`, the client uses
  /// ``AuthClient/Configuration/redirectTo``.
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

struct SignInWithSSORequest: Encodable {
  let providerID: UUID?
  let domain: String?
  let redirectTo: URL?
  let gotrueMetaSecurity: AuthMetaSecurity?
  let codeChallenge: String?
  let codeChallengeMethod: String?
  let skipHttpRedirect: Bool?

  private enum CodingKeys: String, CodingKey {
    case providerID = "provider_id"
    case domain
    case redirectTo = "redirect_to"
    case gotrueMetaSecurity = "gotrue_meta_security"
    case codeChallenge = "code_challenge"
    case codeChallengeMethod = "code_challenge_method"
    case skipHttpRedirect = "skip_http_redirect"
  }
}

/// The `{"url": …}` body of a `/sso` or `/user/identities/authorize` response.
struct URLBody: Decodable {
  let url: URL
}

/// Options for an OAuth sign-in or identity link.
public struct OAuthOptions: Sendable, Hashable {
  /// The scopes to request from the provider. The client sends them separated by spaces.
  public var scopes: [String]

  /// The URL the server redirects to after the provider step. When `nil`, the client uses
  /// ``AuthClient/Configuration/redirectTo``.
  public var redirectTo: URL?

  /// Extra query items to add to the authorize URL, for example `access_type=offline`.
  public var queryItems: [URLQueryItem]

  /// Creates OAuth options.
  ///
  /// - Parameters:
  ///   - scopes: The scopes to request from the provider.
  ///   - redirectTo: The URL the server redirects to after the provider step.
  ///   - queryItems: Extra query items to add to the authorize URL.
  public init(scopes: [String] = [], redirectTo: URL? = nil, queryItems: [URLQueryItem] = []) {
    self.scopes = scopes
    self.redirectTo = redirectTo
    self.queryItems = queryItems
  }
}

extension OAuthOptions {
  /// `nil` when empty, so the authorize URL has no `scopes` item.
  var scopesParameter: String? {
    scopes.isEmpty ? nil : scopes.joined(separator: " ")
  }

  var queryParams: [(name: String, value: String?)] {
    queryItems.map { ($0.name, $0.value) }
  }
}

/// A web sign-in flow that ``AuthClient/oauthSignInURL(_:options:)``,
/// ``AuthClient/linkIdentityURL(_:options:)``, or ``AuthClient/ssoSignInURL(_:options:)`` started.
///
/// Open ``url`` to show the provider page. Pass the redirect URL that comes back to
/// ``AuthClient/handleRedirect(_:)``, or pass the code and ``id`` to
/// ``AuthClient/exchangeCodeForSession(_:flowID:)``.
public struct OAuthFlow: Sendable, Hashable, Identifiable {
  /// The ID of the PKCE flow. The client stores the flow under this ID.
  public let id: UUID

  /// The URL that starts the flow at the provider.
  public let url: URL

  /// Creates an OAuth flow.
  ///
  /// - Parameters:
  ///   - id: The ID of the PKCE flow.
  ///   - url: The URL that starts the flow at the provider.
  public init(id: UUID, url: URL) {
    self.id = id
    self.url = url
  }
}

/// What ``AuthClient/handleRedirect(_:)`` did with a redirect URL.
public enum RedirectResult: Sendable, Hashable {
  /// The redirect gave a session. The client stored it and emitted one auth event.
  ///
  /// `verification` is the kind of email link that started the flow: ``EmailOTPType/recovery``
  /// for a password reset, ``EmailOTPType/emailChange`` for an email change, or the `type` that
  /// the server put in the URL. It is `nil` for an OAuth sign-in or an identity link.
  case signedIn(Session, verification: EmailOTPType?)

  /// The user confirmed one of two addresses in an email change. The server waits for the
  /// other confirmation. The client stores nothing.
  case emailChangePending(message: String)
}

/// One page of users, returned by ``AuthAdminClient/listUsers(page:pageSize:)``.
public struct UserPage: Hashable, Sendable {
  /// The users on this page.
  public let users: [User]

  /// The audience the users belong to.
  public let audience: String

  /// The number of the next page, or `nil` on the last page.
  public let nextPage: Int?

  /// The number of the last page.
  public let lastPage: Int

  /// The total number of users.
  public let total: Int
}

/// The link to generate with ``AuthAdminClient/generateLink(_:)``.
public struct GenerateLink: Sendable {
  struct Body: Encodable {
    var type: GenerateLinkType
    var email: String
    var password: String?
    var newEmail: String?
    var userMetadata: JSONObject?

    private enum CodingKeys: String, CodingKey {
      case type
      case email
      case password
      case newEmail = "new_email"
      case userMetadata = "data"
    }
  }
  var body: Body
  var redirectTo: URL?

  /// Generates a signup link.
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
        userMetadata: userMetadata
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates an invite link.
  public static func invite(
    email: String,
    userMetadata: JSONObject? = nil,
    redirectTo: URL? = nil
  ) -> GenerateLink {
    GenerateLink(
      body: .init(
        type: .invite,
        email: email,
        userMetadata: userMetadata
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates a magic link.
  public static func magicLink(
    email: String,
    userMetadata: JSONObject? = nil,
    redirectTo: URL? = nil
  ) -> GenerateLink {
    GenerateLink(
      body: .init(
        type: .magiclink,
        email: email,
        userMetadata: userMetadata
      ),
      redirectTo: redirectTo
    )
  }

  /// Generates a recovery link.
  public static func recovery(
    email: String,
    redirectTo: URL? = nil
  ) -> GenerateLink {
    GenerateLink(
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
  ) -> GenerateLink {
    GenerateLink(
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
  ) -> GenerateLink {
    GenerateLink(
      body: .init(
        type: .emailChangeNew,
        email: email,
        newEmail: newEmail
      ),
      redirectTo: redirectTo
    )
  }
}

/// The response from ``AuthAdminClient/generateLink(_:)``.
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
  /// The URL appended to the action link, or `nil` when the server sent none.
  public let redirectTo: URL?
  /// The verification type that the emaillink is associated to.
  public let verificationType: GenerateLinkType

  private enum CodingKeys: String, CodingKey {
    case actionLink = "action_link"
    case emailOTP = "email_otp"
    case hashedToken = "hashed_token"
    case redirectTo = "redirect_to"
    case verificationType = "verification_type"
  }
}

/// The type of link generated by ``AuthAdminClient/generateLink(_:)``.
public struct GenerateLinkType: RawRepresentable, Codable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a link type from a string literal, such as `"magiclink"`.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public static let signup: GenerateLinkType = "signup"
  public static let invite: GenerateLinkType = "invite"
  public static let magiclink: GenerateLinkType = "magiclink"
  public static let recovery: GenerateLinkType = "recovery"
  public static let emailChangeCurrent: GenerateLinkType = "email_change_current"
  public static let emailChangeNew: GenerateLinkType = "email_change_new"
}

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
public struct OAuthClientType: RawRepresentable, Decodable, Hashable, Sendable,
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
public struct OAuthClientRegistrationType: RawRepresentable, Decodable, Hashable, Sendable,
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
public struct OAuthClient: Decodable, Hashable, Sendable {
  /// Unique identifier for the OAuth client
  public let clientID: UUID

  /// Human-readable name of the OAuth client
  public let clientName: String?

  /// Client secret (only returned on registration and regeneration)
  public let clientSecret: String?

  /// Type of OAuth client
  public let clientType: OAuthClientType

  /// Token endpoint authentication method
  public let tokenEndpointAuthMethod: String

  /// Registration type of the client
  public let registrationType: OAuthClientRegistrationType

  /// URI of the OAuth client
  public let clientURI: URL?

  /// URL of the client application's logo
  public let logoURI: URL?

  /// Array of allowed redirect URIs
  public let redirectURIs: [URL]?

  /// Array of allowed grant types
  public let grantTypes: [OAuthClientGrantType]?

  /// Array of allowed response types
  public let responseTypes: [OAuthClientResponseType]?

  /// Scope of the OAuth client
  public let scope: String?

  /// Timestamp when the client was created
  public let createdAt: Date

  /// Timestamp when the client was last updated
  public let updatedAt: Date

  private enum CodingKeys: String, CodingKey {
    case clientID = "client_id"
    case clientName = "client_name"
    case clientSecret = "client_secret"
    case clientType = "client_type"
    case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    case registrationType = "registration_type"
    case clientURI = "client_uri"
    case logoURI = "logo_uri"
    case redirectURIs = "redirect_uris"
    case grantTypes = "grant_types"
    case responseTypes = "response_types"
    case scope
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// A new OAuth client for ``AuthAdminOAuth/createClient(_:)``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct CreateOAuthClient: Encodable, Hashable, Sendable {
  /// Human-readable name of the OAuth client
  public let clientName: String

  /// URI of the OAuth client
  public let clientURI: URL?

  /// Array of allowed redirect URIs
  public let redirectURIs: [URL]

  /// Array of allowed grant types (optional, defaults to authorization_code and refresh_token)
  public let grantTypes: [OAuthClientGrantType]?

  /// Array of allowed response types (optional, defaults to code)
  public let responseTypes: [OAuthClientResponseType]?

  /// Scope of the OAuth client
  public let scope: String?

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
  public let clientName: String?

  /// URL of the client application's homepage
  public let clientURI: URL?

  /// URL of the client application's logo
  public let logoURI: URL?

  /// Array of redirect URIs used by the client
  public let redirectURIs: [URL]?

  /// OAuth grant types the client is authorized to use
  public let grantTypes: [OAuthClientGrantType]?

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

/// Details about the OAuth client requesting authorization.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthAuthorizationClient: Decodable, Hashable, Sendable {
  /// Unique identifier for the OAuth client.
  public let id: UUID

  /// Human-readable name of the OAuth client.
  public let name: String?

  /// URI of the OAuth client's homepage.
  public let uri: URL?

  /// URL of the OAuth client's logo.
  public let logoURI: URL?

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case uri
    case logoURI = "logo_uri"
  }
}

/// The authenticated user considering the authorization request.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthAuthorizationUser: Decodable, Hashable, Sendable {
  /// Unique identifier for the user.
  public let id: UUID

  /// The user's email address.
  public let email: String?
}

/// Details about a pending OAuth authorization request, returned by
/// ``AuthOAuthServer/authorizationDetails(id:)`` when the
/// request still requires the user's consent.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthAuthorizationDetails: Decodable, Hashable, Sendable {
  /// Opaque identifier for this authorization request.
  public let authorizationID: String

  /// The redirect URI the client registered for this request.
  public let redirectURI: URL

  /// The OAuth client requesting authorization.
  public let client: OAuthAuthorizationClient

  /// The user considering the request.
  public let user: OAuthAuthorizationUser

  /// The requested scope.
  public let scope: String?

  private enum CodingKeys: String, CodingKey {
    case authorizationID = "authorization_id"
    case redirectURI = "redirect_uri"
    case client
    case user
    case scope
  }
}

/// A redirect URL returned after approving or denying an OAuth authorization
/// request, or in place of ``OAuthAuthorizationDetails`` when the server
/// auto-approves a request the user has already consented to.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthRedirect: Decodable, Hashable, Sendable {
  /// The URL the client app should be redirected to. On denial, this URL's
  /// query string carries an `error=access_denied` parameter (RFC 6749) —
  /// denial is a successful API call, not a thrown error.
  public let redirectURL: URL

  private enum CodingKeys: String, CodingKey {
    case redirectURL = "redirect_url"
  }
}

/// The response from ``AuthOAuthServer/authorizationDetails(id:)``.
///
/// The server auto-approves an authorization request if the user already has
/// an active consent covering the requested scopes for that client, returning
/// ``redirect(_:)`` instead of ``details(_:)``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public enum OAuthAuthorizationDetailsResult: Hashable, Sendable {
  /// The authorization is pending; present these details to the user for consent.
  case details(OAuthAuthorizationDetails)

  /// The authorization was already approved automatically; redirect the user.
  case redirect(OAuthRedirect)
}

extension OAuthAuthorizationDetailsResult: Decodable {
  private enum CodingKeys: String, CodingKey {
    case authorizationID = "authorization_id"
  }

  /// Details carry an `authorization_id`; the auto-approve body is `{redirect_url}` alone.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self =
      container.contains(.authorizationID)
      ? .details(try OAuthAuthorizationDetails(from: decoder))
      : .redirect(try OAuthRedirect(from: decoder))
  }
}

/// An OAuth grant the user has given to a third-party client app, returned by
/// ``AuthOAuthServer/listGrants()``.
/// Only relevant when the OAuth 2.1 server is enabled in Supabase Auth.
public struct OAuthGrant: Decodable, Hashable, Sendable {
  /// The OAuth client the grant was given to.
  public let client: OAuthAuthorizationClient

  /// The scopes granted to the client.
  public let scopes: [String]

  /// When the grant was given.
  public let grantedAt: Date

  private enum CodingKeys: String, CodingKey {
    case client
    case scopes
    case grantedAt = "granted_at"
  }
}

/// JSON Web Key (JWK) representation.
public struct JWK: Decodable, Hashable, Sendable {
  /// Key type (e.g., `"RSA"`, `"EC"`, `"oct"`).
  public let kty: String

  /// Key operations (e.g., `["sign", "verify"]`).
  public let keyOps: [String]?

  /// Algorithm (e.g., `"RS256"`, `"ES256"`, `"HS256"`).
  public let alg: String?

  /// Key ID.
  public let kid: String?

  /// RSA modulus (base64url-encoded).
  public let n: String?

  /// RSA exponent (base64url-encoded).
  public let e: String?

  /// EC curve name (e.g., `"P-256"`).
  public let crv: String?

  /// EC x coordinate (base64url-encoded).
  public let x: String?

  /// EC y coordinate (base64url-encoded).
  public let y: String?

  /// Symmetric key value (base64url-encoded).
  public let k: String?

  /// The wire names of RFC 7517.
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
public struct JWKS: Decodable, Hashable, Sendable {
  /// The set of JSON Web Keys.
  public let keys: [JWK]
}

/// The header portion of a decoded JSON Web Token.
public struct JWTHeader: Decodable, Hashable, Sendable {
  /// Algorithm (e.g., `"RS256"`, `"ES256"`, `"HS256"`).
  public let alg: String

  /// Key ID used to select the signing key.
  public let kid: String?

  /// Token type (typically `"JWT"`).
  public let typ: String?
}
