import Crypto
import Foundation
import Helpers
import _CryptoExtras

enum JWTVerifier {
  enum Algorithm: String {
    case rs256 = "RS256"
    case es256 = "ES256"
  }

  static func algorithm(for jwk: JWK) -> Algorithm? {
    if let alg = jwk.alg {
      return Algorithm(rawValue: alg)
    }
    if jwk.kty == "EC", jwk.crv == "P-256" {
      return .es256
    }
    if jwk.kty == "RSA" {
      return .rs256
    }
    return nil
  }

  static func verify(_ jwt: DecodedJWT, with jwk: JWK) -> Bool? {
    guard let algorithm = algorithm(for: jwk) else {
      return nil
    }

    let message = Data("\(jwt.raw.header).\(jwt.raw.payload)".utf8)
    switch algorithm {
    case .rs256:
      guard let publicKey = jwk.rsaPublicKey else {
        return false
      }
      return publicKey.isValidSignature(
        _RSA.Signing.RSASignature(rawRepresentation: jwt.signature),
        for: message,
        padding: .insecurePKCS1v1_5
      )
    case .es256:
      guard
        let publicKey = jwk.p256PublicKey,
        let signature = try? P256.Signing.ECDSASignature(rawRepresentation: jwt.signature)
      else {
        return false
      }
      return publicKey.isValidSignature(signature, for: message)
    }
  }
}

extension JWK {
  var rsaPublicKey: _RSA.Signing.PublicKey? {
    guard kty == "RSA",
      let n,
      let modulus = Base64URL.decode(n),
      let e,
      let exponent = Base64URL.decode(e),
      // swift-crypto enforces this floor in `init(n:e:)` only from 4.5.2; the package allows 4.0.0.
      Self.bitLength(of: modulus) >= 2048
    else {
      return nil
    }

    return try? _RSA.Signing.PublicKey(n: modulus, e: exponent)
  }

  private static func bitLength(of bytes: Data) -> Int {
    guard let first = bytes.firstIndex(where: { $0 != 0 }) else {
      return 0
    }
    return (bytes.endIndex - first) * 8 - bytes[first].leadingZeroBitCount
  }
}
