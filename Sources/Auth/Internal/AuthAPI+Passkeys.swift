//
//  AuthAPI+Passkeys.swift
//  Auth
//
//  Created by Guilherme Souza on 26/10/26.
//

import Foundation
import HTTPTypes

extension AuthAPI {
  /// The credential is a `JSONValue`, so its W3C field names reach the server as they are.
  private struct VerifyBody: Encodable {
    let challengeID: UUID
    let credential: JSONValue

    private enum CodingKeys: String, CodingKey {
      case challengeID = "challenge_id"
      case credential
    }
  }

  func passkeyRegistrationOptions(
    accessToken: String
  ) -> AuthRequest<PasskeyRegistrationOptions> {
    request(
      .post, "passkeys/registration/options", authorization: bearer(accessToken),
      decode: decoding(PasskeyRegistrationOptions.self))
  }

  func verifyPasskeyRegistration(
    challengeID: UUID,
    credential: JSONValue,
    accessToken: String
  ) throws -> AuthRequest<PasskeyListItem> {
    try request(
      .post, "passkeys/registration/verify", authorization: bearer(accessToken),
      body: encodeBody(VerifyBody(challengeID: challengeID, credential: credential)),
      decode: decoding(PasskeyListItem.self))
  }

  func passkeyAuthenticationOptions() -> AuthRequest<PasskeyAuthenticationOptions> {
    request(
      .post, "passkeys/authentication/options",
      decode: decoding(PasskeyAuthenticationOptions.self))
  }

  func verifyPasskeyAuthentication(
    challengeID: UUID,
    credential: JSONValue
  ) throws -> AuthRequest<Session> {
    try request(
      .post, "passkeys/authentication/verify",
      body: encodeBody(VerifyBody(challengeID: challengeID, credential: credential)),
      decode: decodingSession())
  }

  func listPasskeys(accessToken: String) -> AuthRequest<[PasskeyListItem]> {
    request(
      .get, "passkeys/", authorization: bearer(accessToken),
      decode: decoding([PasskeyListItem].self))
  }

  func renamePasskey(
    id: UUID,
    friendlyName: String,
    accessToken: String
  ) throws -> AuthRequest<PasskeyListItem> {
    try request(
      .patch, "passkeys/\(id)", authorization: bearer(accessToken),
      body: encodeBody(["friendly_name": friendlyName]), decode: decoding(PasskeyListItem.self))
  }

  func deletePasskey(id: UUID, accessToken: String) -> AuthRequest<Void> {
    request(
      .delete, "passkeys/\(id)", authorization: bearer(accessToken), decode: ignoringBody)
  }
}
