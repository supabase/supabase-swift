import Foundation

/// Schema 1 of the stored session.
///
/// Every key is spelled out, so renaming a property of `Session` or `User` cannot change what is
/// on disk and sign users out.
struct PersistedSession: Codable, Sendable {
  static let currentSchema = 1

  var schema: Int
  var receivedAt: Date
  var accessToken: String
  var tokenType: String
  var expiresIn: TimeInterval
  var expiresAt: TimeInterval
  var refreshToken: String
  var providerToken: String?
  var providerRefreshToken: String?
  var weakPassword: PersistedWeakPassword?
  var user: PersistedUser

  enum CodingKeys: String, CodingKey {
    case schema
    case receivedAt = "received_at"
    case accessToken = "access_token"
    case tokenType = "token_type"
    case expiresIn = "expires_in"
    case expiresAt = "expires_at"
    case refreshToken = "refresh_token"
    case providerToken = "provider_token"
    case providerRefreshToken = "provider_refresh_token"
    case weakPassword = "weak_password"
    case user
  }
}

struct PersistedWeakPassword: Codable, Sendable {
  var reasons: [String]
}

struct PersistedUser: Codable, Sendable {
  var id: UUID
  var aud: String
  var role: String?
  var email: String?
  var phone: String?
  var newEmail: String?
  var actionLink: String?
  var appMetadata: [String: JSONValue]
  var userMetadata: [String: JSONValue]
  var isAnonymous: Bool
  var createdAt: Date
  var updatedAt: Date
  var confirmationSentAt: Date?
  var recoverySentAt: Date?
  var emailChangeSentAt: Date?
  var invitedAt: Date?
  var confirmedAt: Date?
  var emailConfirmedAt: Date?
  var phoneConfirmedAt: Date?
  var lastSignInAt: Date?
  var identities: [PersistedIdentity]?
  var factors: [PersistedFactor]?

  enum CodingKeys: String, CodingKey {
    case id
    case aud
    case role
    case email
    case phone
    case newEmail = "new_email"
    case actionLink = "action_link"
    case appMetadata = "app_metadata"
    case userMetadata = "user_metadata"
    case isAnonymous = "is_anonymous"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case confirmationSentAt = "confirmation_sent_at"
    case recoverySentAt = "recovery_sent_at"
    case emailChangeSentAt = "email_change_sent_at"
    case invitedAt = "invited_at"
    case confirmedAt = "confirmed_at"
    case emailConfirmedAt = "email_confirmed_at"
    case phoneConfirmedAt = "phone_confirmed_at"
    case lastSignInAt = "last_sign_in_at"
    case identities
    case factors
  }
}

struct PersistedIdentity: Codable, Sendable {
  var id: String
  var identityId: UUID
  var userId: UUID
  var identityData: [String: JSONValue]?
  var provider: String
  var createdAt: Date?
  var lastSignInAt: Date?
  var updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id
    case identityId = "identity_id"
    case userId = "user_id"
    case identityData = "identity_data"
    case provider
    case createdAt = "created_at"
    case lastSignInAt = "last_sign_in_at"
    case updatedAt = "updated_at"
  }
}

struct PersistedFactor: Codable, Sendable {
  var id: UUID
  var friendlyName: String?
  var factorType: String
  var status: String
  var createdAt: Date
  var updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case friendlyName = "friendly_name"
    case factorType = "factor_type"
    case status
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

extension PersistedSession {
  init(_ received: ReceivedSession) {
    let session = received.session
    self.init(
      schema: Self.currentSchema,
      receivedAt: received.receivedAt,
      accessToken: session.accessToken,
      tokenType: session.tokenType,
      expiresIn: session.expiresIn,
      expiresAt: session.expiresAt,
      refreshToken: session.refreshToken,
      providerToken: session.providerToken,
      providerRefreshToken: session.providerRefreshToken,
      weakPassword: session.weakPassword.map { PersistedWeakPassword(reasons: $0.reasons) },
      user: PersistedUser(session.user)
    )
  }

  var receivedSession: ReceivedSession {
    ReceivedSession(
      session: Session(
        providerToken: providerToken,
        providerRefreshToken: providerRefreshToken,
        accessToken: accessToken,
        tokenType: tokenType,
        expiresIn: expiresIn,
        expiresAt: expiresAt,
        refreshToken: refreshToken,
        weakPassword: weakPassword.map { WeakPassword(reasons: $0.reasons) },
        user: user.user
      ),
      receivedAt: receivedAt
    )
  }
}

extension PersistedUser {
  init(_ user: User) {
    self.init(
      id: user.id,
      aud: user.audience,
      role: user.role,
      email: user.email,
      phone: user.phone,
      newEmail: user.newEmail,
      actionLink: user.actionLink,
      appMetadata: user.appMetadata,
      userMetadata: user.userMetadata,
      isAnonymous: user.isAnonymous,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      confirmationSentAt: user.confirmationSentAt,
      recoverySentAt: user.recoverySentAt,
      emailChangeSentAt: user.emailChangeSentAt,
      invitedAt: user.invitedAt,
      confirmedAt: user.confirmedAt,
      emailConfirmedAt: user.emailConfirmedAt,
      phoneConfirmedAt: user.phoneConfirmedAt,
      lastSignInAt: user.lastSignInAt,
      identities: user.identities?.map(PersistedIdentity.init),
      factors: user.factors?.map(PersistedFactor.init)
    )
  }

  var user: User {
    User(
      id: id,
      appMetadata: appMetadata,
      userMetadata: userMetadata,
      audience: aud,
      confirmationSentAt: confirmationSentAt,
      recoverySentAt: recoverySentAt,
      emailChangeSentAt: emailChangeSentAt,
      newEmail: newEmail,
      invitedAt: invitedAt,
      actionLink: actionLink,
      email: email,
      phone: phone,
      createdAt: createdAt,
      confirmedAt: confirmedAt,
      emailConfirmedAt: emailConfirmedAt,
      phoneConfirmedAt: phoneConfirmedAt,
      lastSignInAt: lastSignInAt,
      role: role,
      updatedAt: updatedAt,
      identities: identities?.map(\.identity),
      isAnonymous: isAnonymous,
      factors: factors?.map(\.factor)
    )
  }
}

extension PersistedIdentity {
  init(_ identity: UserIdentity) {
    self.init(
      id: identity.id,
      identityId: identity.identityId,
      userId: identity.userId,
      identityData: identity.identityData,
      provider: identity.provider,
      createdAt: identity.createdAt,
      lastSignInAt: identity.lastSignInAt,
      updatedAt: identity.updatedAt
    )
  }

  var identity: UserIdentity {
    var identity = UserIdentity(
      id: id,
      identityId: identityId,
      userId: userId,
      identityData: [:],
      provider: provider,
      createdAt: createdAt,
      lastSignInAt: lastSignInAt,
      updatedAt: updatedAt
    )
    identity.identityData = identityData
    return identity
  }
}

extension PersistedFactor {
  init(_ factor: Factor) {
    self.init(
      id: factor.id,
      friendlyName: factor.friendlyName,
      factorType: factor.factorType,
      status: factor.status.rawValue,
      createdAt: factor.createdAt,
      updatedAt: factor.updatedAt
    )
  }

  var factor: Factor {
    Factor(
      id: id,
      friendlyName: friendlyName,
      factorType: factorType,
      status: FactorStatus(rawValue: status),
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }
}
