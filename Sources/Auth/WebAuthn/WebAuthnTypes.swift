//
//  WebAuthnTypes.swift
//  Auth
//
//  Created by Guilherme Souza on 11/06/26.
//

import Foundation
import Helpers

/// Parameters for enrolling a new WebAuthn (passkey) factor as a second factor (MFA).
///
/// - Warning: WebAuthn/passkey support is experimental and may change in a future release. Opt in
///   with `@_spi(Experimental) import Supabase`.
@_spi(Experimental)
public struct MFAWebAuthnEnrollParams: MFAEnrollParamsType {
  public let factorType: FactorType = "webauthn"

  /// Human readable name assigned to the factor.
  public let friendlyName: String?

  public init(friendlyName: String? = nil) {
    self.friendlyName = friendlyName
  }
}

@_spi(Experimental)
extension MFAEnrollParamsType where Self == MFAWebAuthnEnrollParams {
  /// Creates parameters for enrolling a WebAuthn (passkey) factor.
  ///
  /// - Parameter friendlyName: Human readable name assigned to the factor.
  public static func webAuthn(friendlyName: String? = nil) -> Self {
    MFAWebAuthnEnrollParams(friendlyName: friendlyName)
  }
}

/// Relying-party options sent when challenging a WebAuthn factor.
///
/// - Warning: Experimental. See ``MFAWebAuthnEnrollParams``.
@_spi(Experimental)
public struct WebAuthnChallengeOptions: Encodable, Hashable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case relyingPartyIdentifier = "rp_id"
    case relyingPartyOrigins = "rp_origins"
  }

  /// The relying party identifier (typically your app's associated domain, e.g. `example.com`).
  public let relyingPartyIdentifier: String?

  /// Allowed relying party origins (e.g. `https://example.com`).
  public let relyingPartyOrigins: [String]?

  public init(relyingPartyIdentifier: String? = nil, relyingPartyOrigins: [String]? = nil) {
    self.relyingPartyIdentifier = relyingPartyIdentifier
    self.relyingPartyOrigins = relyingPartyOrigins
  }
}

/// The kind of WebAuthn ceremony a challenge requests.
///
/// - Warning: Experimental. See ``MFAWebAuthnEnrollParams``.
@_spi(Experimental)
public enum WebAuthnChallengeType: String, Codable, Hashable, Sendable {
  /// A registration ceremony (`navigator.credentials.create`).
  case create
  /// An authentication ceremony (`navigator.credentials.get`).
  case request
}

/// WebAuthn-specific payload returned by ``AuthMFA/challenge(params:)`` for `webauthn` factors.
///
/// - Warning: Experimental. See ``MFAWebAuthnEnrollParams``.
@_spi(Experimental)
public struct WebAuthnChallengeResponseData: Decodable, Hashable, Sendable {
  /// Whether the authenticator should create a new credential or assert an existing one.
  public let type: WebAuthnChallengeType

  /// The W3C credential options (creation or request) to forward to the authenticator. Field
  /// names follow the W3C spec verbatim (camelCase) and are not transformed.
  public let credentialOptions: AnyJSON
}

// MARK: - First-factor passkeys

/// A passkey registered for the current user.
///
/// - Warning: Experimental. See ``MFAWebAuthnEnrollParams``.
@_spi(Experimental)
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
///
/// - Warning: Experimental. See ``MFAWebAuthnEnrollParams``.
@_spi(Experimental)
public struct PasskeyRegistrationOptions: Decodable, Hashable, Sendable {
  /// ID of the challenge, to be passed back when verifying.
  public let challengeId: String

  /// W3C `PublicKeyCredentialCreationOptions`, forwarded verbatim to the authenticator.
  public let options: AnyJSON

  /// Unix timestamp (seconds since epoch) when the challenge expires.
  public let expiresAt: TimeInterval
}

/// Assertion options for authenticating with a passkey (first factor).
///
/// - Warning: Experimental. See ``MFAWebAuthnEnrollParams``.
@_spi(Experimental)
public struct PasskeyAuthenticationOptions: Decodable, Hashable, Sendable {
  /// ID of the challenge, to be passed back when verifying.
  public let challengeId: String

  /// W3C `PublicKeyCredentialRequestOptions`, forwarded verbatim to the authenticator.
  public let options: AnyJSON

  /// Unix timestamp (seconds since epoch) when the challenge expires.
  public let expiresAt: TimeInterval
}

/// Top-level body for passkey registration and authentication verify endpoints.
struct PasskeyVerifyBody: Encodable {
  let challengeId: String
  let credential: AnyJSON
}

/// Encodes a passkey verify body using snake_case for the top-level fields while leaving the
/// nested W3C credential JSON (which uses camelCase such as `clientDataJSON`) verbatim, because
/// the snake_case strategy converts struct CodingKeys but not AnyJSON dictionary keys.
func encodeWebAuthnBody(_ body: PasskeyVerifyBody) throws -> Data {
  let encoder = JSONEncoder()
  encoder.keyEncodingStrategy = .convertToSnakeCase
  encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(body)
}
