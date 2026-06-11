//
//  WebAuthnTypes.swift
//  Auth
//
//  Created by Guilherme Souza on 11/06/26.
//

import Foundation
import Helpers

/// Parameters for enrolling a new WebAuthn (passkey) factor as a second factor (MFA).
public struct MFAWebAuthnEnrollParams: MFAEnrollParamsType {
  public let factorType: FactorType = "webauthn"

  /// Human readable name assigned to the factor.
  public let friendlyName: String?

  public init(friendlyName: String? = nil) {
    self.friendlyName = friendlyName
  }
}

extension MFAEnrollParamsType where Self == MFAWebAuthnEnrollParams {
  /// Creates parameters for enrolling a WebAuthn (passkey) factor.
  ///
  /// - Parameter friendlyName: Human readable name assigned to the factor.
  public static func webAuthn(friendlyName: String? = nil) -> Self {
    MFAWebAuthnEnrollParams(friendlyName: friendlyName)
  }
}

/// Relying-party options sent when challenging a WebAuthn factor.
public struct WebAuthnChallengeOptions: Encodable, Hashable, Sendable {
  /// The relying party identifier (typically your app's associated domain, e.g. `example.com`).
  public let rpId: String?

  /// Allowed relying party origins (e.g. `https://example.com`).
  public let rpOrigins: [String]?

  public init(rpId: String? = nil, rpOrigins: [String]? = nil) {
    self.rpId = rpId
    self.rpOrigins = rpOrigins
  }
}

/// The kind of WebAuthn ceremony a challenge requests.
public enum WebAuthnChallengeType: String, Codable, Hashable, Sendable {
  /// A registration ceremony (`navigator.credentials.create`).
  case create
  /// An authentication ceremony (`navigator.credentials.get`).
  case request
}

/// WebAuthn-specific payload returned by ``AuthMFA/challenge(params:)`` for `webauthn` factors.
public struct WebAuthnChallengeResponseData: Decodable, Hashable, Sendable {
  /// Whether the authenticator should create a new credential or assert an existing one.
  public let type: WebAuthnChallengeType

  /// The W3C credential options (creation or request) to forward to the authenticator. Field
  /// names follow the W3C spec verbatim (camelCase) and are not transformed.
  public let credentialOptions: AnyJSON
}

// MARK: - First-factor passkeys

/// A passkey registered for the current user.
public struct PasskeyListItem: Codable, Identifiable, Hashable, Sendable {
  /// Unique identifier of the passkey.
  public let id: String

  /// Human readable name assigned to the passkey.
  public let friendlyName: String?

  /// When the passkey was registered.
  public let createdAt: Date

  /// When the passkey was last used to authenticate, if ever.
  public let lastUsedAt: Date?

  public init(id: String, friendlyName: String?, createdAt: Date, lastUsedAt: Date?) {
    self.id = id
    self.friendlyName = friendlyName
    self.createdAt = createdAt
    self.lastUsedAt = lastUsedAt
  }
}

/// Credential creation options for registering a new passkey (first factor).
public struct PasskeyRegistrationOptions: Decodable, Hashable, Sendable {
  /// ID of the challenge, to be passed back when verifying.
  public let challengeId: String

  /// W3C `PublicKeyCredentialCreationOptions`, forwarded verbatim to the authenticator.
  public let options: AnyJSON

  /// When the challenge expires.
  public let expiresAt: Date
}

/// Assertion options for authenticating with a passkey (first factor).
public struct PasskeyAuthenticationOptions: Decodable, Hashable, Sendable {
  /// ID of the challenge, to be passed back when verifying.
  public let challengeId: String

  /// W3C `PublicKeyCredentialRequestOptions`, forwarded verbatim to the authenticator.
  public let options: AnyJSON

  /// When the challenge expires.
  public let expiresAt: Date
}

/// Encodes a WebAuthn request body without applying the snake_case key strategy, so the embedded
/// W3C credential JSON (which uses camelCase field names such as `clientDataJSON`) reaches the
/// backend verbatim. All backend field names must be spelled out explicitly by the caller.
func encodeWebAuthnBody(_ json: AnyJSON) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(json)
}
