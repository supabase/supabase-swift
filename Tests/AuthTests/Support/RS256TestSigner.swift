import Foundation
import _CryptoExtras

@testable import Auth
@testable import Helpers

struct RS256TestSigner {
  let jwk: JWK
  private let privateKey: _RSA.Signing.PrivateKey

  init(keySize: _RSA.Signing.KeySize = .bits2048) {
    let privateKey = try! _RSA.Signing.PrivateKey(unsafeKeySize: keySize)
    let primitives = try! privateKey.publicKey.getKeyPrimitives()
    self.privateKey = privateKey
    jwk = JWK(
      kty: "RSA",
      keyOps: ["verify"],
      alg: "RS256",
      kid: "rs256-test-kid",
      n: Base64URL.encode(primitives.modulus),
      e: Base64URL.encode(primitives.publicExponent),
      crv: nil,
      x: nil,
      y: nil,
      k: nil
    )
  }

  func sign(header: [String: Any], payload: [String: Any]) -> String {
    let headerB64 = Base64URL.encode(try! JSONSerialization.data(withJSONObject: header))
    let payloadB64 = Base64URL.encode(try! JSONSerialization.data(withJSONObject: payload))
    let signature = try! privateKey.signature(
      for: Data("\(headerB64).\(payloadB64)".utf8),
      padding: .insecurePKCS1v1_5
    )
    return "\(headerB64).\(payloadB64).\(Base64URL.encode(signature.rawRepresentation))"
  }
}

extension JWK {
  func withModulusPrefixedByZeroBytes(_ count: Int) -> JWK {
    JWK(
      kty: kty,
      keyOps: keyOps,
      alg: alg,
      kid: kid,
      n: n.flatMap(Base64URL.decode).map { Base64URL.encode(Data(count: count) + $0) },
      e: e,
      crv: crv,
      x: x,
      y: y,
      k: k
    )
  }
}
