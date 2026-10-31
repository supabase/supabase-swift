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
    let body: Data?
    if let webAuthn {
      body = try encoder.encode(["webauthn": webAuthn])
    } else if let channel {
      body = try encoder.encode(["channel": channel])
    } else {
      body = nil
    }

    return request(
      .post, "factors/\(factorID)/challenge", authorization: bearer(accessToken),
      body: body, decode: decoding(MFAChallenge.self))
  }

  func verifyFactor(
    factorID: UUID,
    challengeID: UUID,
    code: String,
    accessToken: String
  ) throws -> AuthRequest<Session> {
    struct Params: Encodable {
      let factorId: UUID
      let challengeId: UUID
      let code: String
    }

    return try request(
      .post, "factors/\(factorID)/verify", authorization: bearer(accessToken),
      body: encoder.encode(Params(factorId: factorID, challengeId: challengeID, code: code)),
      decode: decoding(Session.self))
  }

  func verifyFactor(
    factorID: UUID,
    challengeID: UUID,
    credentialResponse: JSONValue,
    accessToken: String
  ) throws -> AuthRequest<Session> {
    // WebAuthn credential responses use W3C camelCase field names (e.g. `clientDataJSON`).
    // Encode without the snake_case strategy so they reach the backend verbatim.
    let body = try encodeWebAuthnBody([
      "factor_id": .string(factorID.uuidString),
      "challenge_id": .string(challengeID.uuidString),
      "webauthn": ["credential_response": credentialResponse],
    ])

    return request(
      .post, "factors/\(factorID)/verify", authorization: bearer(accessToken), body: body,
      decode: decoding(Session.self))
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
      body: encoder.encode(Params(code: code)), decode: decoding(Session.self))
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
