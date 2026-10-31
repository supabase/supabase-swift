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
  func enrollFactor(
    _ params: any MFAEnrollParamsType,
    accessToken: String
  ) throws -> AuthRequest<AuthMFAEnrollResponse> {
    try request(
      .post, "factors", authorization: bearer(accessToken), body: encoder.encode(params),
      decode: decoding(AuthMFAEnrollResponse.self))
  }

  func challengeFactor(
    _ params: MFAChallengeParams,
    accessToken: String
  ) throws -> AuthRequest<AuthMFAChallengeResponse> {
    // The server parses a JSON body for `webauthn` factors even when it has no fields, so always
    // send an object.
    struct Body: Encodable {
      let channel: MessagingChannel?
      let webauthn: WebAuthnChallengeOptions?
    }

    return try request(
      .post, "factors/\(params.factorId)/challenge", authorization: bearer(accessToken),
      body: encoder.encode(Body(channel: params.channel, webauthn: params.webAuthn)),
      decode: decoding(AuthMFAChallengeResponse.self))
  }

  func verifyFactor(
    _ params: MFAVerifyParams,
    accessToken: String
  ) throws -> AuthRequest<AuthMFAVerifyResponse> {
    try request(
      .post, "factors/\(params.factorId)/verify", authorization: bearer(accessToken),
      body: encoder.encode(params), decode: decoding(AuthMFAVerifyResponse.self))
  }

  func unenrollFactor(
    _ params: MFAUnenrollParams,
    accessToken: String
  ) -> AuthRequest<AuthMFAUnenrollResponse> {
    request(
      .delete, "factors/\(params.factorId)", authorization: bearer(accessToken),
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
  ) throws -> AuthRequest<AuthMFAVerifyResponse> {
    struct Params: Encodable {
      let code: String
    }

    return try request(
      .post, "\(Self.recoveryCodes)/verify", authorization: bearer(accessToken),
      body: encoder.encode(Params(code: code)), decode: decoding(AuthMFAVerifyResponse.self))
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
