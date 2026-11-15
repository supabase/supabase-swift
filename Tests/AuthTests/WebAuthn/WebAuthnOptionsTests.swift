//
//  WebAuthnOptionsTests.swift
//  Auth
//
//  Created by Guilherme Souza on 30/10/26.
//

import CustomDump
import Foundation
import InlineSnapshotTesting
import Testing

@_spi(Experimental) @testable import Auth

@Suite
struct WebAuthnOptionsTests {
  @Test
  func creationOptionsParseTheBarePublicKey() throws {
    let options = try WebAuthnCreationOptions(
      publicKey: [
        "challenge": "Y2hhbGxlbmdl",
        "rp": ["id": "example.com", "name": "Example"],
        "user": ["id": "dXNlci1pZA", "name": "u@e.com", "displayName": "U"],
        "excludeCredentials": [["id": "b2xk", "type": "public-key"]],
      ]
    )

    expectNoDifference(
      options,
      WebAuthnCreationOptions(
        rpID: "example.com",
        challenge: Data("challenge".utf8),
        userID: Data("user-id".utf8),
        userName: "u@e.com",
        excludedCredentialIDs: [Data("old".utf8)]
      )
    )
  }

  @Test
  func creationOptionsWithoutRpIDThrowDecoding() {
    #expect {
      try WebAuthnCreationOptions(publicKey: ["challenge": "Y2hhbGxlbmdl"])
    } throws: { error in
      let error = error as? AuthError
      return error?.kind == .decoding
        && error?.message == "Missing field 'rp.id' in WebAuthn credential options."
    }
  }

  @Test
  func requestOptionsParseTheBarePublicKey() throws {
    let options = try WebAuthnRequestOptions(
      publicKey: ["challenge": "Y2hhbGxlbmdl", "rpId": "example.com"]
    )

    expectNoDifference(
      options,
      WebAuthnRequestOptions(
        rpID: "example.com",
        challenge: Data("challenge".utf8),
        allowedCredentialIDs: []
      )
    )
  }

  @Test
  func requestOptionsWithInvalidChallengeThrowDecoding() {
    #expect {
      try WebAuthnRequestOptions(
        publicKey: ["challenge": "not valid base64url!!!", "rpId": "example.com"])
    } throws: { error in
      let error = error as? AuthError
      return error?.kind == .decoding
        && error?.message == "Field 'challenge' is not valid base64url."
    }
  }

  @Test
  func mfaCredentialOptionsUnwrapPublicKey() throws {
    let challenge = WebAuthnChallengeResponseData(
      type: .request,
      credentialOptions: ["publicKey": ["challenge": "Y2hhbGxlbmdl", "rpId": "example.com"]]
    )

    expectNoDifference(
      try challenge.publicKeyOptions(),
      ["challenge": "Y2hhbGxlbmdl", "rpId": "example.com"]
    )
  }

  @Test
  func mfaCredentialOptionsWithoutPublicKeyThrowDecoding() {
    let challenge = WebAuthnChallengeResponseData(
      type: .request,
      credentialOptions: ["challenge": "Y2hhbGxlbmdl", "rpId": "example.com"]
    )

    #expect {
      try challenge.publicKeyOptions()
    } throws: { error in
      let error = error as? AuthError
      return error?.kind == .decoding
        && error?.message == "Missing field 'publicKey' in WebAuthn credential options."
    }
  }

  @Test
  func registrationCredentialSerializesBase64URLFields() throws {
    let json = try WebAuthnCredentialJSON.registration(
      credentialID: Data([0xFB, 0xFF, 0x01]),
      clientDataJSON: Data("client-data".utf8),
      attestationObject: Data("attestation".utf8)
    )

    assertInlineSnapshot(of: json, as: .json) {
      """
      {
        "id" : "-_8B",
        "rawId" : "-_8B",
        "response" : {
          "attestationObject" : "YXR0ZXN0YXRpb24",
          "clientDataJSON" : "Y2xpZW50LWRhdGE"
        },
        "type" : "public-key"
      }
      """
    }
  }

  @Test
  func registrationCredentialWithoutAttestationThrowsDecoding() {
    #expect {
      try WebAuthnCredentialJSON.registration(
        credentialID: Data([1]),
        clientDataJSON: Data(),
        attestationObject: nil
      )
    } throws: { error in
      (error as? AuthError)?.kind == .decoding
    }
  }

  @Test
  func assertionCredentialSerializesBase64URLFields() {
    let json = WebAuthnCredentialJSON.assertion(
      credentialID: Data([0xFB, 0xFF, 0x01]),
      clientDataJSON: Data("client-data".utf8),
      authenticatorData: Data("auth".utf8),
      signature: Data("sig".utf8),
      userID: Data("user-id".utf8)
    )

    assertInlineSnapshot(of: json, as: .json) {
      """
      {
        "id" : "-_8B",
        "rawId" : "-_8B",
        "response" : {
          "authenticatorData" : "YXV0aA",
          "clientDataJSON" : "Y2xpZW50LWRhdGE",
          "signature" : "c2ln",
          "userHandle" : "dXNlci1pZA"
        },
        "type" : "public-key"
      }
      """
    }
  }
}
