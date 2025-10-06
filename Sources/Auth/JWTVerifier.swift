//
//  JWTVerifier.swift
//  Supabase
//
//  Created by Claude on 06/10/25.
//

import CryptoKit
import Foundation

enum JWTVerifier {
  /// Verifies an asymmetric JWT signature using CryptoKit
  static func verify(
    jwt: DecodedJWT,
    jwk: JWK
  ) throws -> Bool {
    guard let alg = jwt.header["alg"] as? String else {
      throw AuthError.jwtVerificationFailed(message: "Missing alg in JWT header")
    }

    let message = "\(jwt.raw.header).\(jwt.raw.payload)".data(using: .utf8)!

    switch alg {
    case "RS256":
      // RS256 (RSA) verification requires swift-crypto's _RSA which is not yet public API
      // For now, we fall back to server-side verification via getUser()
      throw AuthError.jwtVerificationFailed(
        message: "RS256 JWTs are currently verified server-side via getUser()"
      )
    case "ES256":
      return try verifyES256(message: message, signature: jwt.signature, jwk: jwk)
    case "HS256":
      // Symmetric keys should be verified server-side via getUser
      throw AuthError.jwtVerificationFailed(
        message: "HS256 JWTs must be verified server-side"
      )
    default:
      throw AuthError.jwtVerificationFailed(message: "Unsupported algorithm: \(alg)")
    }
  }

  private static func verifyES256(message: Data, signature: Data, jwk: JWK) throws -> Bool {
    guard
      let xString = jwk.x,
      let yString = jwk.y,
      let xData = Base64URL.decode(xString),
      let yData = Base64URL.decode(yString)
    else {
      throw AuthError.jwtVerificationFailed(message: "Invalid EC JWK")
    }

    // For P256, we need to construct the X9.63 representation
    // X9.63 format: 0x04 + x + y for uncompressed point
    var x963Data = Data([0x04])
    x963Data.append(xData)
    x963Data.append(yData)

    // Create EC public key from JWK
    let publicKey = try P256.Signing.PublicKey(
      x963Representation: x963Data
    )

    let isValid = publicKey.isValidSignature(
      try P256.Signing.ECDSASignature(rawRepresentation: signature),
      for: SHA256.hash(data: message)
    )

    return isValid
  }
}
