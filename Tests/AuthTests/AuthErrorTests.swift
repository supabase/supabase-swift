//
//  AuthErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/08/24.
//

import Foundation
import HTTPTypes
import Testing

@_spi(Experimental) @testable import Auth

@Suite
struct AuthErrorTests {
  @Test
  func sessionMissingStatic() {
    let error = AuthError.sessionMissing

    #expect(error.kind == .sessionMissing)
    #expect(error.errorCode == .sessionNotFound)
    #expect(error.message == "Auth session missing.")
    #expect(error.weakPasswordReasons.isEmpty)
    #expect(error.response == nil)
  }

  @Test
  func defaultsForErrorCodeAndReasons() {
    let error = AuthError(kind: .implicitGrantRedirect, message: "Implicit grant failure")

    #expect(error.errorCode == .unknown)
    #expect(error.weakPasswordReasons.isEmpty)
    #expect(error.errorDescription == "Implicit grant failure")
  }

  @Test
  func oauthFlowFailedIsClientSide() {
    let error = AuthError.oauthFlowFailed("No redirect URL configured")

    #expect(error.kind == .oauthFlowFailed)
    #expect(error.errorCode == .unknown)
    #expect(error.response == nil)
    #expect(error.errorDescription == "No redirect URL configured")
  }

  @Test
  func weakPasswordCarriesReasons() {
    let error = AuthError(
      kind: .weakPassword,
      message: "Password is weak",
      errorCode: .weakPassword,
      weakPasswordReasons: ["length", "characters", "pwned"]
    )

    #expect(error.kind == .weakPassword)
    #expect(error.weakPasswordReasons == ["length", "characters", "pwned"])
  }

  @Test
  func apiErrorCarriesResponse() {
    var headers = HTTPFields()
    headers[.sbRequestID] = "req-1"
    let error = AuthError(
      kind: .api,
      message: "API Error",
      errorCode: .emailConflictIdentityNotDeletable,
      response: HTTPErrorResponse(statusCode: 422, headers: headers, body: Data())
    )

    #expect(error.errorCode == .emailConflictIdentityNotDeletable)
    #expect(error.response?.statusCode == 422)
    #expect(error.response?.requestID == "req-1")
    #expect(error.description == "AuthError(api): API Error [status 422, request req-1]")
  }

  @Test
  func kindIsOpen() {
    let future = AuthError.Kind(rawValue: "somethingNew")

    #expect(future.rawValue == "somethingNew")
    #expect(future != .api)
  }

  @Test
  func conformsToSupabaseError() {
    let error: any Error = AuthError.sessionMissing

    #expect((error as? any SupabaseError)?.message == "Auth session missing.")
  }

  @Test
  func webAuthnErrorCodeRawValues() {
    #expect(ErrorCode.webAuthnChallengeNotFound.rawValue == "webauthn_challenge_not_found")
    #expect(ErrorCode.webAuthnChallengeExpired.rawValue == "webauthn_challenge_expired")
    #expect(ErrorCode.webAuthnVerificationFailed.rawValue == "webauthn_verification_failed")
    #expect(ErrorCode.webAuthnCredentialExists.rawValue == "webauthn_credential_exists")
    #expect(ErrorCode.tooManyPasskeys.rawValue == "too_many_passkeys")
  }

  @Test
  func errorCodeEquality() {
    #expect(ErrorCode.badJWT == ErrorCode("bad_jwt"))
    #expect(ErrorCode.sessionExpired == ErrorCode("session_expired"))
    #expect(ErrorCode.badJWT != ErrorCode.sessionExpired)
  }

  @Test
  func errorCodeRawValue() {
    #expect(ErrorCode.badJWT.rawValue == "bad_jwt")
    #expect(ErrorCode.sessionExpired.rawValue == "session_expired")
    #expect(ErrorCode.unknown.rawValue == "unknown")
  }

  @Test
  func errorCodeInitWithString() {
    let code1 = ErrorCode("custom_error")
    #expect(code1.rawValue == "custom_error")

    let code2 = ErrorCode(rawValue: "another_error")
    #expect(code2.rawValue == "another_error")
  }

  @Test
  func errorCodeHashable() {
    let set: Set<ErrorCode> = [.badJWT, .sessionExpired, .userNotFound]
    #expect(set.contains(.badJWT))
    #expect(set.contains(.sessionExpired))
    #expect(!set.contains(.emailExists))
  }
}
