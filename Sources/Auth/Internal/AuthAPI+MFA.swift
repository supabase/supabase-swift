//
//  AuthAPI+MFA.swift
//  Auth
//
//  Created by Guilherme Souza on 26/10/26.
//

import Foundation
import HTTPTypes

// MARK: - Factors

extension AuthAPI {
  func enrollFactor<Enrollment: Decodable>(
    _ params: MFAEnrollParams,
    decoding _: Enrollment.Type,
    accessToken: String
  ) throws -> AuthRequest<Enrollment> {
    try request(
      .post, "factors", authorization: bearer(accessToken), body: encoder.encode(params),
      decode: decoding(Enrollment.self))
  }

  func challengeFactor(
    factorID: UUID,
    channel: MessagingChannel?,
    webAuthn: WebAuthnChallengeOptions?,
    accessToken: String
  ) throws -> AuthRequest<MFAChallenge> {
    // The server parses a JSON body for `webauthn` factors even when it has no fields, so always
    // send an object.
    struct Body: Encodable {
      let channel: MessagingChannel?
      let webauthn: WebAuthnChallengeOptions?
    }

    return try request(
      .post, "factors/\(factorID)/challenge", authorization: bearer(accessToken),
      body: encoder.encode(Body(channel: channel, webauthn: webAuthn)),
      decode: decoding(MFAChallenge.self))
  }

  func verifyFactor(
    factorID: UUID,
    challengeID: UUID,
    code: String,
    accessToken: String
  ) throws -> AuthRequest<Session> {
    struct Params: Encodable {
      let factorID: UUID
      let challengeID: UUID
      let code: String

      private enum CodingKeys: String, CodingKey {
        case factorID = "factor_id"
        case challengeID = "challenge_id"
        case code
      }
    }

    return try request(
      .post, "factors/\(factorID)/verify", authorization: bearer(accessToken),
      body: encoder.encode(Params(factorID: factorID, challengeID: challengeID, code: code)),
      decode: decodingSession())
  }

  func verifyFactor(
    factorID: UUID,
    challengeID: UUID,
    type: WebAuthnChallengeType,
    credentialResponse: JSONValue,
    accessToken: String
  ) throws -> AuthRequest<Session> {
    // The server needs `type` to parse the credential. The credential is a `JSONValue`, so the
    // snake_case key strategy keeps its W3C field names.
    struct WebAuthn: Encodable {
      let type: String
      let credentialResponse: JSONValue

      private enum CodingKeys: String, CodingKey {
        case type
        case credentialResponse = "credential_response"
      }
    }
    struct Params: Encodable {
      let factorID: UUID
      let challengeID: UUID
      let webauthn: WebAuthn

      private enum CodingKeys: String, CodingKey {
        case factorID = "factor_id"
        case challengeID = "challenge_id"
        case webauthn
      }
    }

    return try request(
      .post, "factors/\(factorID)/verify", authorization: bearer(accessToken),
      body: encoder.encode(
        Params(
          factorID: factorID, challengeID: challengeID,
          webauthn: WebAuthn(type: type.rawValue, credentialResponse: credentialResponse))),
      decode: decodingSession())
  }

  func unenrollFactor(
    factorID: UUID,
    accessToken: String
  ) -> AuthRequest<AuthMFAUnenrollResponse> {
    request(
      .delete, "factors/\(factorID)", authorization: bearer(accessToken),
      decode: decoding(AuthMFAUnenrollResponse.self))
  }
}

// MARK: - Recovery codes

extension AuthAPI {
  private static let recoveryCodes = "factors/recovery-codes"

  func recoveryCodesStatus(
    accessToken: String
  ) -> AuthRequest<AuthMFARecoveryCodesStatusResponse> {
    request(
      .get, Self.recoveryCodes, authorization: bearer(accessToken),
      decode: decoding(AuthMFARecoveryCodesStatusResponse.self))
  }

  func generateRecoveryCodes(
    friendlyName: String?,
    accessToken: String
  ) throws -> AuthRequest<AuthMFARecoveryCodesGenerateResponse> {
    struct Params: Encodable {
      let friendlyName: String

      private enum CodingKeys: String, CodingKey {
        case friendlyName = "friendly_name"
      }
    }

    return try request(
      .post, Self.recoveryCodes, authorization: bearer(accessToken),
      body: friendlyName.map { try encoder.encode(Params(friendlyName: $0)) },
      decode: decoding(AuthMFARecoveryCodesGenerateResponse.self))
  }

  func verifyRecoveryCode(
    _ code: String,
    accessToken: String
  ) throws -> AuthRequest<Session> {
    struct Params: Encodable {
      let code: String
    }

    return try request(
      .post, "\(Self.recoveryCodes)/verify", authorization: bearer(accessToken),
      body: encoder.encode(Params(code: code)), decode: decodingSession())
  }

  func regenerateRecoveryCodes(
    accessToken: String
  ) -> AuthRequest<AuthMFARecoveryCodesGenerateResponse> {
    request(
      .post, "\(Self.recoveryCodes)/regenerate", authorization: bearer(accessToken),
      decode: decoding(AuthMFARecoveryCodesGenerateResponse.self))
  }

  func unenrollRecoveryCodes(accessToken: String) -> AuthRequest<AuthMFAUnenrollResponse> {
    request(
      .delete, Self.recoveryCodes, authorization: bearer(accessToken),
      decode: decoding(AuthMFAUnenrollResponse.self))
  }
}
