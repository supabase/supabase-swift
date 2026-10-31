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
struct JWTVerifierTests {
  private let header = #"{"alg":"ES256","kid":"es256-test-kid","typ":"JWT"}"#
  private let payload = #"{"sub":"1234567890","role":"authenticated"}"#

  @Test
  func rs256ValidSignatureVerifies() throws {
    let signer = RS256TestSigner()
    let jwt = signer.sign(
      header: ["alg": "RS256", "kid": "rs256-test-kid", "typ": "JWT"],
      payload: ["sub": "1234567890", "role": "authenticated"]
    )
    let decoded = try #require(JWT.decode(jwt))

    #expect(JWTVerifier.verify(decoded, with: signer.jwk) == true)
  }

  @Test
  func rs256TamperedPayloadFails() throws {
    let signer = RS256TestSigner()
    let jwt = signer.sign(
      header: ["alg": "RS256", "kid": "rs256-test-kid", "typ": "JWT"],
      payload: ["sub": "1234567890", "role": "authenticated"]
    )
    let parts = jwt.split(separator: ".")
    let payloadJSON = try #require(
      Base64URL.decode(String(parts[1])).map { String(decoding: $0, as: UTF8.self) })
    let tamperedPayload = Base64URL.encode(
      Data(payloadJSON.replacingOccurrences(of: "1234567890", with: "1234567891").utf8))
    let decoded = try #require(JWT.decode("\(parts[0]).\(tamperedPayload).\(parts[2])"))

    #expect(JWTVerifier.verify(decoded, with: signer.jwk) == false)
  }

  @Test
  func es256ValidSignatureVerifies() throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(header: header, payload: payload)
    let decoded = try #require(JWT.decode(jwt))

    #expect(JWTVerifier.verify(decoded, with: signer.jwk) == true)
  }

  @Test
  func es256TamperedFails() throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(header: header, payload: payload)
    let parts = jwt.split(separator: ".")
    let tamperedPayload = Base64URL.encode(Data(#"{"sub":"attacker","role":"service_role"}"#.utf8))
    let decoded = try #require(JWT.decode("\(parts[0]).\(tamperedPayload).\(parts[2])"))

    #expect(JWTVerifier.verify(decoded, with: signer.jwk) == false)
  }

  @Test
  func es256SignatureFromAnotherKeyFails() throws {
    let signer = ES256TestSigner()
    let otherSigner = ES256TestSigner()
    let jwt = try signer.sign(header: header, payload: payload)
    let decoded = try #require(JWT.decode(jwt))

    #expect(JWTVerifier.verify(decoded, with: otherSigner.jwk) == false)
  }

  @Test
  func es256MalformedSignatureFails() throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(header: header, payload: payload)
    let parts = jwt.split(separator: ".")
    let decoded = try #require(
      JWT.decode("\(parts[0]).\(parts[1]).\(Base64URL.encode(Data([0x00, 0x01, 0x02, 0x03])))")
    )

    #expect(JWTVerifier.verify(decoded, with: signer.jwk) == false)
  }

  @Test
  func algorithmBoundFromJWKNotHeader() throws {
    let signer = ES256TestSigner()
    let jwt = try signer.sign(
      header: #"{"alg":"RS256","kid":"es256-test-kid","typ":"JWT"}"#,
      payload: payload
    )
    let decoded = try #require(JWT.decode(jwt))

    #expect(JWTVerifier.verify(decoded, with: signer.jwk) == true)

    let es256Decoded = try #require(JWT.decode(try signer.sign(header: header, payload: payload)))

    #expect(JWTVerifier.verify(es256Decoded, with: RS256TestSigner().jwk) == false)
  }

  @Test
  func algorithmInferredWhenJWKHasNoAlg() {
    let ecJWK = JWK(
      kty: "EC",
      keyOps: nil,
      alg: nil,
      kid: "kid",
      n: nil,
      e: nil,
      crv: "P-256",
      x: "AQAB",
      y: "AQAB",
      k: nil
    )
    let rsaJWK = JWK(
      kty: "RSA",
      keyOps: nil,
      alg: nil,
      kid: "kid",
      n: "AQAB",
      e: "AQAB",
      crv: nil,
      x: nil,
      y: nil,
      k: nil
    )

    #expect(JWTVerifier.algorithm(for: ecJWK) == .es256)
    #expect(JWTVerifier.algorithm(for: rsaJWK) == .rs256)
  }

  @Test
  func unsupportedAlgReturnsNil() throws {
    let signer = ES256TestSigner()
    let base = signer.jwk
    let jwk = JWK(
      kty: base.kty,
      keyOps: base.keyOps,
      alg: "ES512",
      kid: base.kid,
      n: nil,
      e: nil,
      crv: base.crv,
      x: base.x,
      y: base.y,
      k: nil
    )
    let decoded = try #require(JWT.decode(try signer.sign(header: header, payload: payload)))

    #expect(JWTVerifier.algorithm(for: jwk) == nil)
    #expect(JWTVerifier.verify(decoded, with: jwk) == nil)
  }

  @Test
  func algorithmRawValue() {
    #expect(JWTVerifier.Algorithm(rawValue: "ES256") == .es256)
    #expect(JWTVerifier.Algorithm(rawValue: "RS256") == .rs256)
  }

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
}
