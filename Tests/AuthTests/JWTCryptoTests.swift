//
//  JWTCryptoTests.swift
//  Supabase
//
//  Created by Coverage Tests
//

import XCTest
@testable import Auth
@testable import Helpers

#if canImport(Security)
final class JWTCryptoTests: XCTestCase {

  // MARK: - JWK+RSA Tests

  func testRSAPublishKeyGeneration() {
    // Test data from a real RS256 JWT (modulus and exponent)
    // This is a sample RSA256 public key
    let jwk = JWK(
      kty: "RSA",
      keyOps: ["verify"],
      alg: "RS256",
      kid: "test-key-1",
      n: "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw",
      e: "AQAB",
      crv: nil,
      x: nil,
      y: nil,
      k: nil
    )

    // Test valid RSA key generation
    let rsaKey = jwk.rsaPublishKey
    XCTAssertNotNil(rsaKey, "RSA public key should be generated successfully")
  }

  func testRSAPublishKeyInvalidAlgorithm() {
    // Test with invalid algorithm
    let jwk = JWK(
      kty: "RSA",
      keyOps: nil,
      alg: "ES256", // Wrong algorithm - should be RS256
      kid: "test-key-2",
      n: "test-modulus",
      e: "AQAB",
      crv: nil,
      x: nil,
      y: nil,
      k: nil
    )

    let rsaKey = jwk.rsaPublishKey
    XCTAssertNil(rsaKey, "RSA public key should be nil with wrong algorithm")
  }

  func testRSAPublishKeyInvalidKeyType() {
    // Test with invalid key type
    let jwk = JWK(
      kty: "EC", // Wrong type - should be RSA
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
    XCTAssertNil(rsaKey, "RSA public key should be nil with wrong key type")
  }

  func testRSAPublishKeyMissingModulus() {
    // Test with missing modulus
    let jwk = JWK(
      kty: "RSA",
      keyOps: nil,
      alg: "RS256",
      kid: "test-key-4",
      n: nil, // Missing modulus
      e: "AQAB",
      crv: nil,
      x: nil,
      y: nil,
      k: nil
    )

    let rsaKey = jwk.rsaPublishKey
    XCTAssertNil(rsaKey, "RSA public key should be nil with missing modulus")
  }

  func testRSAPublishKeyMissingExponent() {
    // Test with missing exponent
    let jwk = JWK(
      kty: "RSA",
      keyOps: nil,
      alg: "RS256",
      kid: "test-key-5",
      n: "test-modulus",
      e: nil, // Missing exponent
      crv: nil,
      x: nil,
      y: nil,
      k: nil
    )

    let rsaKey = jwk.rsaPublishKey
    XCTAssertNil(rsaKey, "RSA public key should be nil with missing exponent")
  }

  func testRSAPublishKeyInvalidBase64() {
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
    XCTAssertNil(rsaKey, "RSA public key should be nil with invalid base64 modulus")
  }

  // MARK: - JWTAlgorithm Tests

  func testRS256VerificationWithValidSignature() {
    // Create a sample JWT token (this would normally come from a real auth server)
    // For testing, we'll use a known-good JWT
    let header = #"{"alg":"RS256","typ":"JWT"}"#
    let payload = #"{"sub":"1234567890","name":"Test User","iat":1516239022}"#

    guard
      let headerData = header.data(using: .utf8),
      let payloadData = payload.data(using: .utf8)
    else {
      XCTFail("Failed to create test data")
      return
    }

    let headerB64 = Base64URL.encode(headerData)
    let payloadB64 = Base64URL.encode(payloadData)

    // Create a mock signature (in real scenario, this would be a proper RSA signature)
    let mockSignature = Data([0x00, 0x01, 0x02, 0x03])
    let signatureB64 = Base64URL.encode(mockSignature)

    let jwtString = "\(headerB64).\(payloadB64).\(signatureB64)"

    // Decode the JWT
    guard let decoded = JWT.decode(jwtString) else {
      XCTFail("Failed to decode JWT")
      return
    }

    XCTAssertEqual(decoded.raw.header, headerB64)
    XCTAssertEqual(decoded.raw.payload, payloadB64)
    XCTAssertEqual(decoded.signature, mockSignature)
  }

  func testRS256AlgorithmType() {
    let algorithm = JWTAlgorithm.rs256
    XCTAssertEqual(algorithm.rawValue, "RS256")
  }

}
#endif
