//
//  AuthErrorTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 29/08/24.
//

import Foundation
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite struct AuthErrorTests {
  @Test("Auth errors have correct properties")
  func testErrors() {
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
}
