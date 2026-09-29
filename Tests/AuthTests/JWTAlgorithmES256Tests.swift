import Crypto
import Foundation
import Testing

@testable import Auth
@testable import Helpers

struct ES256TestSigner {
  let privateKey = P256.Signing.PrivateKey()

  var jwk: JWK {
    let coordinates = privateKey.publicKey.x963Representation.dropFirst()
    return JWK(
      kty: "EC",
      keyOps: ["verify"],
      alg: "ES256",
      kid: "es256-test-kid",
      n: nil,
      e: nil,
      crv: "P-256",
      x: Base64URL.encode(coordinates.prefix(32)),
      y: Base64URL.encode(coordinates.suffix(32)),
      k: nil
    )
  }

  func sign(header: String, payload: String) throws -> String {
    let headerB64 = Base64URL.encode(Data(header.utf8))
    let payloadB64 = Base64URL.encode(Data(payload.utf8))
    let signature = try privateKey.signature(for: Data("\(headerB64).\(payloadB64)".utf8))
    return "\(headerB64).\(payloadB64).\(Base64URL.encode(signature.rawRepresentation))"
  }
}

@Suite
struct JWTAlgorithmES256Tests {
  private let header = #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#
  private let payload = #"{"sub":"1234567890","role":"authenticated"}"#

  @Test
  func p256PublicKeyFromJWK() {
    let signer = ES256TestSigner()

    let publicKey = signer.jwk.p256PublicKey

    #expect(publicKey?.rawRepresentation == signer.privateKey.publicKey.rawRepresentation)
  }

  @Test
  func p256PublicKeyRejectsNonECKey() {
    let jwk = JWK(
      kty: "RSA",
      keyOps: nil,
      alg: "ES256",
      kid: "kid",
      n: "AQAB",
      e: "AQAB",
      crv: "P-256",
      x: "AQAB",
      y: "AQAB",
      k: nil
    )

    #expect(jwk.p256PublicKey == nil)
  }

  @Test
  func p256PublicKeyRejectsOtherCurves() {
    let signer = ES256TestSigner()
    let base = signer.jwk
    let jwk = JWK(
      kty: base.kty,
      keyOps: base.keyOps,
      alg: "ES384",
      kid: base.kid,
      n: nil,
      e: nil,
      crv: "P-384",
      x: base.x,
      y: base.y,
      k: nil
    )

    #expect(jwk.p256PublicKey == nil)
  }

  @Test
  func p256PublicKeyRejectsWrongLengthCoordinates() {
    let signer = ES256TestSigner()
    let base = signer.jwk
    let jwk = JWK(
      kty: base.kty,
      keyOps: base.keyOps,
      alg: base.alg,
      kid: base.kid,
      n: nil,
      e: nil,
      crv: base.crv,
      x: base.x,
      y: Base64URL.encode(Data(repeating: 0x01, count: 31)),
      k: nil
    )

    #expect(jwk.p256PublicKey == nil)
  }

  @Test
  func p256PublicKeyRejectsOffCurvePoint() {
    let jwk = JWK(
      kty: "EC",
      keyOps: nil,
      alg: "ES256",
      kid: "kid",
      n: nil,
      e: nil,
      crv: "P-256",
      x: Base64URL.encode(Data(repeating: 0x00, count: 32)),
      y: Base64URL.encode(Data(repeating: 0x00, count: 32)),
      k: nil
    )

    #expect(jwk.p256PublicKey == nil)
  }

  @Test
  func es256VerifiesValidSignature() throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(header: header, payload: payload)
    let decoded = try #require(JWT.decode(jwt))

    #expect(JWTAlgorithm.es256.verify(jwt: decoded, jwk: signer.jwk))
  }

  @Test
  func es256RejectsTamperedPayload() throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(header: header, payload: payload)
    let parts = jwt.split(separator: ".")
    let tamperedPayload = Base64URL.encode(Data(#"{"sub":"attacker","role":"service_role"}"#.utf8))
    let decoded = try #require(JWT.decode("\(parts[0]).\(tamperedPayload).\(parts[2])"))

    #expect(!JWTAlgorithm.es256.verify(jwt: decoded, jwk: signer.jwk))
  }

  @Test
  func es256RejectsSignatureFromAnotherKey() throws {
    let signer = ES256TestSigner()
    let otherSigner = ES256TestSigner()
    let jwt = try signer.sign(header: header, payload: payload)
    let decoded = try #require(JWT.decode(jwt))

    #expect(!JWTAlgorithm.es256.verify(jwt: decoded, jwk: otherSigner.jwk))
  }

  @Test
  func es256RejectsMalformedSignature() throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(header: header, payload: payload)
    let parts = jwt.split(separator: ".")
    let decoded = try #require(
      JWT.decode("\(parts[0]).\(parts[1]).\(Base64URL.encode(Data([0x00, 0x01, 0x02, 0x03])))")
    )

    #expect(!JWTAlgorithm.es256.verify(jwt: decoded, jwk: signer.jwk))
  }

  @Test
  func es256AlgorithmType() {
    #expect(JWTAlgorithm(rawValue: "ES256") == .es256)
  }
}
