//
//  WebAuthnTypesTests.swift
//
//
//  Created by Guilherme Souza on 13/08/26.
//

import Foundation
import Testing

@_spi(Experimental) @testable import Auth

@Suite
struct WebAuthnTypesTests {
  private struct ChallengeTypeContainer: Decodable {
    let type: WebAuthnChallengeType
  }

  @Test
  func webAuthnChallengeTypeDecodesUnknownValue() throws {
    let json = Data(#"{"type":"reauthenticate"}"#.utf8)
    let decoded = try JSONDecoder().decode(ChallengeTypeContainer.self, from: json)
    #expect(decoded.type.rawValue == "reauthenticate")
  }

  @Test
  func webAuthnChallengeTypeDecodesKnownValue() throws {
    let json = Data(#"{"type":"create"}"#.utf8)
    let decoded = try JSONDecoder().decode(ChallengeTypeContainer.self, from: json)
    #expect(decoded.type == .create)
  }

  @Test
  func webAuthnChallengeTypeStringLiteral() {
    let type: WebAuthnChallengeType = "custom_ceremony"
    #expect(type.rawValue == "custom_ceremony")
  }
}
