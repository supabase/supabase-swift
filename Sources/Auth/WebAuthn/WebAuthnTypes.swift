//
//  WebAuthnTypes.swift
//  Auth
//
//  Created by Guilherme Souza on 11/06/26.
//

public import Foundation
import Helpers

/// Relying-party options sent when challenging a WebAuthn factor.
///
/// - Warning: WebAuthn/passkey support is experimental and may change in a future release. Opt in
///   with `@_spi(Experimental) import Supabase`.
@_spi(Experimental)
public struct WebAuthnChallengeOptions: Encodable, Hashable, Sendable {
  /// The relying party identifier (typically your app's associated domain, e.g. `example.com`).
  public var rpID: String?

  /// Allowed relying party origins (e.g. `https://example.com`).
  public var rpOrigins: [String]?

  private enum CodingKeys: String, CodingKey {
    case rpID = "rp_id"
    case rpOrigins = "rp_origins"
  }

  /// Creates a ``WebAuthnChallengeOptions``.
  public init(rpID: String? = nil, rpOrigins: [String]? = nil) {
    self.rpID = rpID
    self.rpOrigins = rpOrigins
  }
}

/// The kind of WebAuthn ceremony a challenge requests.
///
/// - Warning: Experimental. See ``WebAuthnChallengeOptions``.
@_spi(Experimental)
public struct WebAuthnChallengeType: RawRepresentable, Decodable, Hashable, Sendable,
  ExpressibleByStringLiteral
{
  /// The ceremony name as the server sends it, such as `"create"`.
  public let rawValue: String

  /// Creates a ``WebAuthnChallengeType`` from a raw string value.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Creates a ``WebAuthnChallengeType`` from a string literal.
  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  /// A registration ceremony (`navigator.credentials.create`).
  public static let create: WebAuthnChallengeType = "create"

  /// An authentication ceremony (`navigator.credentials.get`).
  public static let request: WebAuthnChallengeType = "request"
}

/// WebAuthn-specific payload returned by ``AuthMFA/challenge(factorID:webAuthn:)`` for `webauthn` factors.
///
/// - Warning: Experimental. See ``WebAuthnChallengeOptions``.
@_spi(Experimental)
public struct WebAuthnChallengeResponseData: Decodable, Hashable, Sendable {
  /// Whether the authenticator should create a new credential or assert an existing one.
  public var type: WebAuthnChallengeType

  /// The W3C credential options (creation or request), wrapped as `{"publicKey": {…}}` like the
  /// argument of `navigator.credentials.create()`. Passkey endpoints send the inner object bare.
  /// Field names follow the W3C spec verbatim (camelCase) and are not transformed.
  public var credentialOptions: JSONValue

  /// Creates a ``WebAuthnChallengeResponseData``.
  public init(
    type: WebAuthnChallengeType,
    credentialOptions: JSONValue
  ) {
    self.type = type
    self.credentialOptions = credentialOptions
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case credentialOptions = "credential_options"
  }
}

/// A passkey registered for the current user.
///
/// - Warning: Experimental. See ``WebAuthnChallengeOptions``.
@_spi(Experimental)
public struct PasskeyListItem: Decodable, Identifiable, Hashable, Sendable {
  /// Unique identifier of the passkey.
  public var id: UUID

  /// Human readable name assigned to the passkey.
  public var friendlyName: String?

  /// When the passkey was registered.
  public var createdAt: Date

  /// When the passkey was last used to authenticate, if ever.
  public var lastUsedAt: Date?

  private enum CodingKeys: String, CodingKey {
    case id
    case friendlyName = "friendly_name"
    case createdAt = "created_at"
    case lastUsedAt = "last_used_at"
  }

  /// Creates a ``PasskeyListItem``.
  public init(id: UUID, friendlyName: String?, createdAt: Date, lastUsedAt: Date?) {
    self.id = id
    self.friendlyName = friendlyName
    self.createdAt = createdAt
    self.lastUsedAt = lastUsedAt
  }
}

/// Credential creation options for registering a new passkey (first factor).
///
/// - Warning: Experimental. See ``WebAuthnChallengeOptions``.
@_spi(Experimental)
public struct PasskeyRegistrationOptions: Decodable, Hashable, Sendable {
  /// ID of the challenge, to be passed back when verifying.
  public var challengeID: UUID

  /// W3C `PublicKeyCredentialCreationOptions`, forwarded verbatim to the authenticator.
  public var options: JSONValue

  /// When the challenge expires.
  public var expiresAt: Date

  /// Creates a ``PasskeyRegistrationOptions``.
  public init(
    challengeID: UUID,
    options: JSONValue,
    expiresAt: Date
  ) {
    self.challengeID = challengeID
    self.options = options
    self.expiresAt = expiresAt
  }

  private enum CodingKeys: String, CodingKey {
    case challengeID = "challenge_id"
    case options
    case expiresAt = "expires_at"
  }

  /// Decodes the options. Reads `expires_at` as a Unix timestamp.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    challengeID = try container.decode(UUID.self, forKey: .challengeID)
    options = try container.decode(JSONValue.self, forKey: .options)
    expiresAt = try container.decodeUnixDate(forKey: .expiresAt)
  }
}

/// Assertion options for authenticating with a passkey (first factor).
///
/// - Warning: Experimental. See ``WebAuthnChallengeOptions``.
@_spi(Experimental)
public struct PasskeyAuthenticationOptions: Decodable, Hashable, Sendable {
  /// ID of the challenge, to be passed back when verifying.
  public var challengeID: UUID

  /// W3C `PublicKeyCredentialRequestOptions`, forwarded verbatim to the authenticator.
  public var options: JSONValue

  /// When the challenge expires.
  public var expiresAt: Date

  /// Creates a ``PasskeyAuthenticationOptions``.
  public init(
    challengeID: UUID,
    options: JSONValue,
    expiresAt: Date
  ) {
    self.challengeID = challengeID
    self.options = options
    self.expiresAt = expiresAt
  }

  private enum CodingKeys: String, CodingKey {
    case challengeID = "challenge_id"
    case options
    case expiresAt = "expires_at"
  }

  /// Decodes the options. Reads `expires_at` as a Unix timestamp.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    challengeID = try container.decode(UUID.self, forKey: .challengeID)
    options = try container.decode(JSONValue.self, forKey: .options)
    expiresAt = try container.decodeUnixDate(forKey: .expiresAt)
  }
}
