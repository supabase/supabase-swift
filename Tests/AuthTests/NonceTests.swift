import Foundation
import Testing

@testable import Auth

@Suite
struct NonceTests {
  @Test
  func hashedIsTheSHA256HexOfRaw() {
    let nonce = Nonce.generate()

    #expect(nonce.hashed == Nonce.sha256Hex(nonce.raw))
    #expect(nonce.hashed.count == 64)
    #expect(nonce.hashed.allSatisfy { $0.isHexDigit && !$0.isUppercase })
  }

  @Test
  func rawIsURLSafeBase64Of32Bytes() {
    let raw = Nonce.generate().raw

    #expect(raw.count == 43)
    #expect(raw.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
  }

  @Test
  func eachCallReturnsANewNonce() {
    #expect(Nonce.generate().raw != Nonce.generate().raw)
  }

  @Test
  func sha256HexMatchesAKnownVector() {
    #expect(
      Nonce.sha256Hex("abc")
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }
}
