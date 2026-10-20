import Crypto
import Foundation
import Testing

@testable import Auth

@Suite
struct PKCETests {
  let sut = PKCE.live

  @Test
  func generateCodeVerifierLength() {
    let verifier = sut.generateCodeVerifier()
    #expect(verifier.count >= 85)
    #expect(verifier.count <= 87)
  }

  @Test
  func generateCodeVerifierUniqueness() {
    let verifier1 = sut.generateCodeVerifier()
    let verifier2 = sut.generateCodeVerifier()
    #expect(verifier1 != verifier2)
  }

  @Test
  func generateCodeChallenge() {
    let testVerifier = "test_verifier"
    let challenge = sut.generateCodeChallenge(testVerifier)

    let expectedChallenge = "0Ku4rR8EgR1w3HyHLBCxVLtPsAAks5HOlpmTEt0XhVA"
    #expect(challenge == expectedChallenge)
  }

  @Test
  func pkceBase64Encoding() {
    let testData = Data([251, 255, 191])
    let encoded = testData.pkceBase64EncodedString()

    #expect(!encoded.contains("+"), "Should not contain '+'")
    #expect(!encoded.contains("/"), "Should not contain '/'")
    #expect(!encoded.contains("="), "Should not contain '='")
    #expect(encoded.contains("-"), "Should contain '-' as replacement for '+'")
    #expect(encoded.contains("_"), "Should contain '_' as replacement for '/'")
  }
}
