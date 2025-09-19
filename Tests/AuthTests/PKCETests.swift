import Crypto
import Foundation
import Testing

@testable import Auth

@Suite struct PKCETests {
  let sut = PKCE.live

  @Test("Code verifier has appropriate length")
  func testGenerateCodeVerifierLength() {
    // The code verifier should generate a string of appropriate length
    // Base64 encoding of 64 random bytes should result in ~86 characters
    let verifier = sut.generateCodeVerifier()
    #expect(verifier.count >= 85)
    #expect(verifier.count <= 87)
  }

  @Test("Code verifiers are unique")
  func testGenerateCodeVerifierUniqueness() {
    // Each generated code verifier should be unique
    let verifier1 = sut.generateCodeVerifier()
    let verifier2 = sut.generateCodeVerifier()
    #expect(verifier1 != verifier2)
  }

  @Test("Code challenge generation works correctly")
  func testGenerateCodeChallenge() {
    // Test with a known input-output pair
    let testVerifier = "test_verifier"
    let challenge = sut.generateCodeChallenge(testVerifier)

    // Expected value from the current implementation
    let expectedChallenge = "0Ku4rR8EgR1w3HyHLBCxVLtPsAAks5HOlpmTEt0XhVA"
    #expect(challenge == expectedChallenge)
  }

  @Test("PKCE Base64 encoding uses URL-safe characters")
  func testPKCEBase64Encoding() {
    // Create data that will produce Base64 with special characters
    let testData = Data([251, 255, 191])  // This will produce Base64 with padding and special chars
    let encoded = testData.pkceBase64EncodedString()

    #expect(!encoded.contains("+"), "Should not contain '+'")
    #expect(!encoded.contains("/"), "Should not contain '/'")
    #expect(!encoded.contains("="), "Should not contain '='")
    #expect(encoded.contains("-"), "Should contain '-' as replacement for '+'")
    #expect(encoded.contains("_"), "Should contain '_' as replacement for '/'")
  }
}
