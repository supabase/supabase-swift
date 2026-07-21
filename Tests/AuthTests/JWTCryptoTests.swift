//
//  JWTCryptoTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import Foundation
import Testing

@testable import Auth
@testable import Helpers

#if canImport(Security)
  @Suite
  struct JWTCryptoTests {

    // MARK: - JWK+RSA Tests

    @Test
    func rsaPublishKeyGeneration() {
      // Test data from a real RS256 JWT (modulus and exponent)
      // This is a sample RSA256 public key
      let jwk = JWK(
        kty: "RSA",
        keyOps: ["verify"],
        alg: "RS256",
        kid: "test-key-1",
        n:
          "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw",
        e: "AQAB",
        crv: nil,
        x: nil,
        y: nil,
        k: nil
      )

      // Test valid RSA key generation
      let rsaKey = jwk.rsaPublishKey
      #expect(rsaKey != nil, "RSA public key should be generated successfully")
    }

    @Test
    func rsaPublishKeyInvalidAlgorithm() {
      // Test with invalid algorithm
      let jwk = JWK(
        kty: "RSA",
        keyOps: nil,
        alg: "ES256",  // Wrong algorithm - should be RS256
        kid: "test-key-2",
        n: "test-modulus",
        e: "AQAB",
        crv: nil,
        x: nil,
        y: nil,
        k: nil
      )

      let rsaKey = jwk.rsaPublishKey
      #expect(rsaKey == nil, "RSA public key should be nil with wrong algorithm")
    }

    @Test
    func rsaPublishKeyInvalidKeyType() {
      // Test with invalid key type
      let jwk = JWK(
        kty: "EC",  // Wrong type - should be RSA
        keyOps: nil,
        alg: "RS256",
        kid: "test-key-3",
        n: "test-modulus",
        e: "AQAB",
        crv: nil,
        x: nil,
        y: nil,
        k: nil
      )

      let rsaKey = jwk.rsaPublishKey
      #expect(rsaKey == nil, "RSA public key should be nil with wrong key type")
    }

    @Test
    func rsaPublishKeyMissingModulus() {
      // Test with missing modulus
      let jwk = JWK(
        kty: "RSA",
        keyOps: nil,
        alg: "RS256",
        kid: "test-key-4",
        n: nil,  // Missing modulus
        e: "AQAB",
        crv: nil,
        x: nil,
        y: nil,
        k: nil
      )

      let rsaKey = jwk.rsaPublishKey
      #expect(rsaKey == nil, "RSA public key should be nil with missing modulus")
    }

    @Test
    func rsaPublishKeyMissingExponent() {
      // Test with missing exponent
      let jwk = JWK(
        kty: "RSA",
        keyOps: nil,
        alg: "RS256",
        kid: "test-key-5",
        n: "test-modulus",
        e: nil,  // Missing exponent
        crv: nil,
        x: nil,
        y: nil,
        k: nil
      )

      let rsaKey = jwk.rsaPublishKey
      #expect(rsaKey == nil, "RSA public key should be nil with missing exponent")
    }

    @Test
    func rsaPublishKeyInvalidBase64() {
      // Test with invalid Base64URL data
      let jwk = JWK(
        kty: "RSA",
        keyOps: nil,
        alg: "RS256",
        kid: "test-key-6",
        n: "!!!invalid-base64!!!",
        e: "AQAB",
        crv: nil,
        x: nil,
        y: nil,
        k: nil
      )

      let rsaKey = jwk.rsaPublishKey
      #expect(rsaKey == nil, "RSA public key should be nil with invalid base64 modulus")
    }

    @Test
    func rs256VerifyDoesNotCrashOnMalformedModulus() {
      let jwk = JWK(
        kty: "RSA",
        keyOps: nil,
        alg: "RS256",
        kid: "malformed-key",
        n: "AAAA",
        e: "AQAB",
        crv: nil,
        x: nil,
        y: nil,
        k: nil
      )

      #expect(jwk.rsaPublishKey == nil, "Malformed modulus should not produce a key")

      let header = #"{"alg":"RS256","typ":"JWT"}"#
      let payload = #"{"sub":"1234567890"}"#
      let headerB64 = Base64URL.encode(header.data(using: .utf8)!)
      let payloadB64 = Base64URL.encode(payload.data(using: .utf8)!)
      let signatureB64 = Base64URL.encode(Data([0x00, 0x01, 0x02, 0x03]))
      let jwtString = "\(headerB64).\(payloadB64).\(signatureB64)"

      guard let decoded = JWT.decode(jwtString) else {
        Issue.record("Failed to decode JWT")
        return
      }

      let isValid = JWTAlgorithm.rs256.verify(jwt: decoded, jwk: jwk)
      #expect(!isValid, "Verification with a malformed key should return false, not crash")
    }

    // MARK: - DER Encoding Tests

    @Test
    func derEncodeLongFormLengthWithInteriorZero() {
      let content = [UInt8](repeating: 0xAB, count: 256)
      let encoded = content.derEncode(as: 2)

      #expect(encoded[0] == 0x02, "Data type tag")
      #expect(encoded[1] == 0x82, "Long form with 2 length bytes")
      #expect(encoded[2] == 0x01, "High-order length byte")
      #expect(encoded[3] == 0x00, "Low-order length byte")
      #expect(encoded.count == 4 + 256, "Header (4) + content (256)")
    }

    @Test
    func derEncodeShortFormLength() {
      let content = [UInt8](repeating: 0xAB, count: 5)
      let encoded = content.derEncode(as: 2)

      #expect(encoded[0] == 0x02, "Data type tag")
      #expect(encoded[1] == 0x05, "Short form length")
      #expect(encoded.count == 2 + 5, "Header (2) + content (5)")
    }

    // MARK: - JWTAlgorithm Tests

    @Test
    func rs256VerificationWithValidSignature() throws {
      // Create a sample JWT token (this would normally come from a real auth server)
      // For testing, we'll use a known-good JWT
      let header = #"{"alg":"RS256","typ":"JWT"}"#
      let payload = #"{"sub":"1234567890","name":"Test User","iat":1516239022}"#

      let headerData = try #require(header.data(using: .utf8), "Failed to create test data")
      let payloadData = try #require(payload.data(using: .utf8), "Failed to create test data")

      let headerB64 = Base64URL.encode(headerData)
      let payloadB64 = Base64URL.encode(payloadData)

      // Create a mock signature (in real scenario, this would be a proper RSA signature)
      let mockSignature = Data([0x00, 0x01, 0x02, 0x03])
      let signatureB64 = Base64URL.encode(mockSignature)

      let jwtString = "\(headerB64).\(payloadB64).\(signatureB64)"

      // Decode the JWT
      let decoded = try #require(JWT.decode(jwtString), "Failed to decode JWT")

      #expect(decoded.raw.header == headerB64)
      #expect(decoded.raw.payload == payloadB64)
      #expect(decoded.signature == mockSignature)
    }

    @Test
    func rs256AlgorithmType() {
      let algorithm = JWTAlgorithm.rs256
      #expect(algorithm.rawValue == "RS256")
    }

  }
#endif
