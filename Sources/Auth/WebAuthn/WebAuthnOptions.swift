//
//  WebAuthnOptions.swift
//  Auth
//
//  Created by Guilherme Souza on 30/10/26.
//

import Foundation
import Helpers

/// The fields of W3C `PublicKeyCredentialCreationOptions` that the platform authenticator needs.
struct WebAuthnCreationOptions: Equatable, Sendable {
  var rpID: String
  var challenge: Data
  var userID: Data
  var userName: String
  var excludedCredentialIDs: [Data]
}

extension WebAuthnCreationOptions {
  /// Parses the bare `publicKey` object. Passkey endpoints return it as `options`; MFA wraps it,
  /// see ``WebAuthnChallengeResponseData/publicKeyOptions()``.
  init(publicKey: JSONValue) throws {
    self.init(
      rpID: try publicKey.webAuthnString(at: ["rp", "id"]),
      challenge: try publicKey.webAuthnBase64URL(at: ["challenge"]),
      userID: try publicKey.webAuthnBase64URL(at: ["user", "id"]),
      userName: try publicKey.webAuthnString(at: ["user", "name"]),
      excludedCredentialIDs: try publicKey.webAuthnCredentialIDs(at: "excludeCredentials")
    )
  }
}

/// The fields of W3C `PublicKeyCredentialRequestOptions` that the platform authenticator needs.
struct WebAuthnRequestOptions: Equatable, Sendable {
  var rpID: String
  var challenge: Data
  var allowedCredentialIDs: [Data]
}

extension WebAuthnRequestOptions {
  /// Parses the bare `publicKey` object. Passkey endpoints return it as `options`; MFA wraps it,
  /// see ``WebAuthnChallengeResponseData/publicKeyOptions()``.
  init(publicKey: JSONValue) throws {
    self.init(
      rpID: try publicKey.webAuthnString(at: ["rpId"]),
      challenge: try publicKey.webAuthnBase64URL(at: ["challenge"]),
      allowedCredentialIDs: try publicKey.webAuthnCredentialIDs(at: "allowCredentials")
    )
  }
}

extension WebAuthnChallengeResponseData {
  /// The bare `publicKey` object inside ``credentialOptions``, which the server sends as
  /// go-webauthn's `{"publicKey": {…}}` wrapper.
  func publicKeyOptions() throws -> JSONValue {
    guard let publicKey = credentialOptions.objectValue?["publicKey"] else {
      throw AuthError.decoding("Missing field 'publicKey' in WebAuthn credential options.")
    }
    return publicKey
  }
}

/// Builds the W3C `PublicKeyCredential` JSON the server parses, with binary fields base64url
/// encoded.
enum WebAuthnCredentialJSON {
  static func registration(
    credentialID: Data,
    clientDataJSON: Data,
    attestationObject: Data?
  ) throws -> JSONValue {
    guard let attestationObject else {
      throw AuthError.decoding("The authenticator returned no attestation object.")
    }
    return [
      "id": .string(Base64URL.encode(credentialID)),
      "rawId": .string(Base64URL.encode(credentialID)),
      "type": "public-key",
      "response": [
        "clientDataJSON": .string(Base64URL.encode(clientDataJSON)),
        "attestationObject": .string(Base64URL.encode(attestationObject)),
      ],
    ]
  }

  static func assertion(
    credentialID: Data,
    clientDataJSON: Data,
    authenticatorData: Data,
    signature: Data,
    userID: Data
  ) -> JSONValue {
    [
      "id": .string(Base64URL.encode(credentialID)),
      "rawId": .string(Base64URL.encode(credentialID)),
      "type": "public-key",
      "response": [
        "clientDataJSON": .string(Base64URL.encode(clientDataJSON)),
        "authenticatorData": .string(Base64URL.encode(authenticatorData)),
        "signature": .string(Base64URL.encode(signature)),
        "userHandle": .string(Base64URL.encode(userID)),
      ],
    ]
  }
}

extension JSONValue {
  fileprivate func webAuthnString(at path: [String]) throws -> String {
    guard let string = value(at: path)?.stringValue else {
      throw AuthError.decoding(
        "Missing field '\(path.joined(separator: "."))' in WebAuthn credential options.")
    }
    return string
  }

  fileprivate func webAuthnBase64URL(at path: [String]) throws -> Data {
    let string = try webAuthnString(at: path)
    guard let data = Base64URL.decode(string) else {
      throw AuthError.decoding("Field '\(path.joined(separator: "."))' is not valid base64url.")
    }
    return data
  }

  /// The decoded `id` of each descriptor in an optional `PublicKeyCredentialDescriptor` list.
  fileprivate func webAuthnCredentialIDs(at key: String) throws -> [Data] {
    guard let descriptors = objectValue?[key]?.arrayValue else { return [] }
    return try descriptors.map { try $0.webAuthnBase64URL(at: ["id"]) }
  }

  private func value(at path: [String]) -> JSONValue? {
    var current: JSONValue? = self
    for key in path {
      current = current?.objectValue?[key]
    }
    return current
  }
}
