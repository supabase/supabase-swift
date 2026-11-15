import Foundation
import Testing

@testable import Auth

@Suite
struct NonceTests {
  @Test
  func hashedIsTheSHA256HexOfRaw() {
    let nonce = Nonce.generate()

    #expect(nonce.hashed == Nonce(raw: nonce.raw).hashed)
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
    #expect(Nonce.generate() != Nonce.generate())
  }

  @Test
  func hashedMatchesAKnownSHA256Vector() {
    #expect(
      Nonce(raw: "abc").hashed
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }
}
