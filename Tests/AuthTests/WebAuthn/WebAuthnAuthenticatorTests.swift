//
//  WebAuthnAuthenticatorTests.swift
//
//
//  Created by Guilherme Souza on 14/09/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import Auth

@Suite
struct WebAuthnAuthenticatorTests {
  @Test
  func webAuthnCreationRpIdMissingFieldThrowsWebAuthnKind() {
    let options = JSONValue.object([:])

    #expect {
      try options.webAuthnCreationRpId()
    } throws: { error in
      guard let authError = error as? AuthError else { return false }
      return authError.kind == .webAuthn
        && authError.message == "Missing field 'rp.id' in WebAuthn credential options."
    }
  }

  @Test
  func webAuthnChallengeDataInvalidBase64URLThrowsWebAuthnKind() {
    let options = JSONValue.object(["challenge": .string("not valid base64url!!!")])

    #expect {
      try options.webAuthnChallengeData()
    } throws: { error in
      guard let authError = error as? AuthError else { return false }
      return authError.kind == .webAuthn
    }
  }
}
