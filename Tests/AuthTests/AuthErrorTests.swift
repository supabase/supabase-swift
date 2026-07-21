//
//  AuthErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/08/24.
//

import Foundation
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct AuthErrorTests {
  @Test
  func errors() {
    let sessionMissing = AuthError.sessionMissing
    #expect(sessionMissing.errorCode == .sessionNotFound)
    #expect(sessionMissing.message == "Auth session missing.")

    let weakPassword = AuthError.weakPassword(message: "Weak password", reasons: [])
    #expect(weakPassword.errorCode == .weakPassword)
    #expect(weakPassword.message == "Weak password")

    let api = AuthError.api(
      message: "API Error",
      errorCode: .emailConflictIdentityNotDeletable,
      underlyingData: Data(),
      underlyingResponse: HTTPURLResponse(
        url: URL(string: "http://localhost")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
    )
    #expect(api.errorCode == .emailConflictIdentityNotDeletable)
    #expect(api.message == "API Error")

    let pkceGrantCodeExchange = AuthError.pkceGrantCodeExchange(
      message: "PKCE failure", error: nil, code: nil)
    #expect(pkceGrantCodeExchange.errorCode == .unknown)
    #expect(pkceGrantCodeExchange.message == "PKCE failure")

    let implicitGrantRedirect = AuthError.implicitGrantRedirect(message: "Implicit grant failure")
    #expect(implicitGrantRedirect.errorCode == .unknown)
    #expect(implicitGrantRedirect.message == "Implicit grant failure")
  }

  @Test
  func weakPasswordWithReasons() {
    let reasons = ["length", "characters", "pwned"]
    let weakPassword = AuthError.weakPassword(message: "Password is weak", reasons: reasons)

    #expect(weakPassword.message == "Password is weak")
    #expect(weakPassword.errorCode == .weakPassword)
    #expect(weakPassword.errorDescription == "Password is weak")
  }

  @Test
  func jwtVerificationFailed() {
    let jwtError = AuthError.jwtVerificationFailed(message: "Invalid JWT signature")

    #expect(jwtError.message == "Invalid JWT signature")
    #expect(jwtError.errorCode == .invalidJWT)
    #expect(jwtError.errorDescription == "Invalid JWT signature")
  }

  @Test
  func pkceGrantCodeExchangeWithErrorAndCode() {
    let pkceError = AuthError.pkceGrantCodeExchange(
      message: "Exchange failed",
      error: "invalid_grant",
      code: "auth_code_123"
    )

    #expect(pkceError.message == "Exchange failed")
    #expect(pkceError.errorCode == .unknown)
  }

  @Test
  func apiErrorWithDifferentCodes() {
    let errorCodes: [ErrorCode] = [
      .badJWT,
      .sessionExpired,
      .userNotFound,
      .invalidCredentials,
      .emailExists,
      .overRequestRateLimit,
    ]

    for code in errorCodes {
      let error = AuthError.api(
        message: "Test error",
        errorCode: code,
        underlyingData: Data(),
        underlyingResponse: HTTPURLResponse(
          url: URL(string: "http://localhost")!,
          statusCode: 400,
          httpVersion: nil,
          headerFields: nil
        )!
      )

      #expect(error.errorCode == code)
      #expect(error.message == "Test error")
    }
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

  @Test
  func authErrorPatternMatching() {
    let error1: any Error = AuthError.sessionMissing
    #expect(AuthError.sessionMissing ~= error1)

    let error2: any Error = AuthError.weakPassword(message: "weak", reasons: [])
    #expect(AuthError.weakPassword(message: "weak", reasons: []) ~= error2)

    // Test non-AuthError
    struct OtherError: Error {}
    let error3: any Error = OtherError()
    #expect(!(AuthError.sessionMissing ~= error3))
  }
}
