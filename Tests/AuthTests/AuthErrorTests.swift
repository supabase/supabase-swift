//
//  AuthErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/08/24.
//

import XCTest

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class AuthErrorTests: XCTestCase {
  func testErrors() {
    let sessionMissing = AuthError.sessionMissing
    XCTAssertEqual(sessionMissing.errorCode, .sessionNotFound)
    XCTAssertEqual(sessionMissing.message, "Auth session missing.")

    let weakPassword = AuthError.weakPassword(message: "Weak password", reasons: [])
    XCTAssertEqual(weakPassword.errorCode, .weakPassword)
    XCTAssertEqual(weakPassword.message, "Weak password")

    let api = AuthError.api(
      message: "API Error",
      errorCode: .emailConflictIdentityNotDeletable,
      underlyingData: Data(),
      underlyingResponse: HTTPURLResponse(
        url: URL(string: "http://localhost")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
    )
    XCTAssertEqual(api.errorCode, .emailConflictIdentityNotDeletable)
    XCTAssertEqual(api.message, "API Error")

    let pkceGrantCodeExchange = AuthError.pkceGrantCodeExchange(
      message: "PKCE failure", error: nil, code: nil)
    XCTAssertEqual(pkceGrantCodeExchange.errorCode, .unknown)
    XCTAssertEqual(pkceGrantCodeExchange.message, "PKCE failure")

    let implicitGrantRedirect = AuthError.implicitGrantRedirect(message: "Implicit grant failure")
    XCTAssertEqual(implicitGrantRedirect.errorCode, .unknown)
    XCTAssertEqual(implicitGrantRedirect.message, "Implicit grant failure")
  }

  func testWeakPasswordWithReasons() {
    let reasons = ["length", "characters", "pwned"]
    let weakPassword = AuthError.weakPassword(message: "Password is weak", reasons: reasons)

    XCTAssertEqual(weakPassword.message, "Password is weak")
    XCTAssertEqual(weakPassword.errorCode, .weakPassword)
    XCTAssertEqual(weakPassword.errorDescription, "Password is weak")
  }

  func testJWTVerificationFailed() {
    let jwtError = AuthError.jwtVerificationFailed(message: "Invalid JWT signature")

    XCTAssertEqual(jwtError.message, "Invalid JWT signature")
    XCTAssertEqual(jwtError.errorCode, .invalidJWT)
    XCTAssertEqual(jwtError.errorDescription, "Invalid JWT signature")
  }

  func testPKCEGrantCodeExchangeWithErrorAndCode() {
    let pkceError = AuthError.pkceGrantCodeExchange(
      message: "Exchange failed",
      error: "invalid_grant",
      code: "auth_code_123"
    )

    XCTAssertEqual(pkceError.message, "Exchange failed")
    XCTAssertEqual(pkceError.errorCode, .unknown)
  }

  func testAPIErrorWithDifferentCodes() {
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

      XCTAssertEqual(error.errorCode, code)
      XCTAssertEqual(error.message, "Test error")
    }
  }

  func testErrorCodeEquality() {
    XCTAssertEqual(ErrorCode.badJWT, ErrorCode("bad_jwt"))
    XCTAssertEqual(ErrorCode.sessionExpired, ErrorCode("session_expired"))
    XCTAssertNotEqual(ErrorCode.badJWT, ErrorCode.sessionExpired)
  }

  func testErrorCodeRawValue() {
    XCTAssertEqual(ErrorCode.badJWT.rawValue, "bad_jwt")
    XCTAssertEqual(ErrorCode.sessionExpired.rawValue, "session_expired")
    XCTAssertEqual(ErrorCode.unknown.rawValue, "unknown")
  }

  func testErrorCodeInitWithString() {
    let code1 = ErrorCode("custom_error")
    XCTAssertEqual(code1.rawValue, "custom_error")

    let code2 = ErrorCode(rawValue: "another_error")
    XCTAssertEqual(code2.rawValue, "another_error")
  }

  func testErrorCodeHashable() {
    let set: Set<ErrorCode> = [.badJWT, .sessionExpired, .userNotFound]
    XCTAssertTrue(set.contains(.badJWT))
    XCTAssertTrue(set.contains(.sessionExpired))
    XCTAssertFalse(set.contains(.emailExists))
  }

  func testAuthErrorPatternMatching() {
    let error1: Error = AuthError.sessionMissing
    XCTAssertTrue(AuthError.sessionMissing ~= error1)

    let error2: Error = AuthError.weakPassword(message: "weak", reasons: [])
    XCTAssertTrue(AuthError.weakPassword(message: "weak", reasons: []) ~= error2)

    // Test non-AuthError
    struct OtherError: Error {}
    let error3: Error = OtherError()
    XCTAssertFalse(AuthError.sessionMissing ~= error3)
  }
}
