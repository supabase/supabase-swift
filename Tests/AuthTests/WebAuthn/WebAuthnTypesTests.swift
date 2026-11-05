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

  @Test
  func passkeyRegistrationOptionsDecodeExpiresAtFromUnixSeconds() throws {
    let json = Data(
      #"{"challengeId":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","options":{},"expiresAt":1700000000}"#
        .utf8)

    let decoded = try JSONDecoder().decode(PasskeyRegistrationOptions.self, from: json)

    #expect(decoded.expiresAt == Date(timeIntervalSince1970: 1_700_000_000))
  }

  @Test
  func passkeyAuthenticationOptionsDecodeExpiresAtFromUnixSeconds() throws {
    let json = Data(
      #"{"challengeId":"e621e1f8-c36c-495a-93fc-0c247a3e6e5f","options":{},"expiresAt":1700000000}"#
        .utf8)

    let decoded = try JSONDecoder().decode(PasskeyAuthenticationOptions.self, from: json)

    #expect(decoded.expiresAt == Date(timeIntervalSince1970: 1_700_000_000))
  }
}
