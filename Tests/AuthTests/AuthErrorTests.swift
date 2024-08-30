//
//  AuthErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/08/24.
//

@testable import Auth
import XCTest

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
      underlyingResponse: HTTPURLResponse(url: URL(string: "http://localhost")!, statusCode: 400, httpVersion: nil, headerFields: nil)!
    )
    XCTAssertEqual(api.errorCode, .emailConflictIdentityNotDeletable)
    XCTAssertEqual(api.message, "API Error")

    let pkceGrantCodeExchange = AuthError.pkceGrantCodeExchange(message: "PKCE failure", error: nil, code: nil)
    XCTAssertEqual(pkceGrantCodeExchange.errorCode, .unknown)
    XCTAssertEqual(pkceGrantCodeExchange.message, "PKCE failure")

    let implicitGrantRedirect = AuthError.implicitGrantRedirect(message: "Implicit grant failure")
    XCTAssertEqual(implicitGrantRedirect.errorCode, .unknown)
    XCTAssertEqual(implicitGrantRedirect.message, "Implicit grant failure")
  }
}
