import Foundation
import CryptoExtras

@testable import Auth
@testable import Helpers

struct RS256TestSigner {
  let jwk: JWK
  private let privateKey: _RSA.Signing.PrivateKey

  init(keySize: _RSA.Signing.KeySize = .bits2048) {
    let privateKey = try! _RSA.Signing.PrivateKey(unsafeKeySize: keySize)
    let (modulus, publicExponent) = Self.integers(
      inPKCS1DER: privateKey.publicKey.pkcs1DERRepresentation)
    self.privateKey = privateKey
    jwk = JWK(
      kty: "RSA",
      keyOps: ["verify"],
      alg: "RS256",
      kid: "rs256-test-kid",
      n: Base64URL.encode(modulus),
      e: Base64URL.encode(publicExponent),
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

  // `getKeyPrimitives()` needs swift-crypto 3.8.0; the package allows 3.6.0. A PKCS #1 public key
  // is `SEQUENCE { INTEGER n, INTEGER e }`.
  private static func integers(inPKCS1DER der: Data) -> (Data, Data) {
    var bytes = [UInt8](der)[...]

    func readLength() -> Int {
      let first = Int(bytes.removeFirst())
      guard first & 0x80 != 0 else { return first }
      return (0..<(first & 0x7F)).reduce(0) { length, _ in length << 8 | Int(bytes.removeFirst()) }
    }

    func readInteger() -> Data {
      precondition(bytes.removeFirst() == 0x02)
      let length = readLength()
      let value = bytes.prefix(length)
      bytes.removeFirst(length)
      return Data(value.drop { $0 == 0 })
    }

    precondition(bytes.removeFirst() == 0x30)
    _ = readLength()
    return (readInteger(), readInteger())
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
