import Crypto
import XCTest

@testable import Auth

final class PKCETests: XCTestCase {
  let sut = PKCE.live

  func testGenerateCodeVerifierLength() {
    // The code verifier should generate a string of appropriate length
    // Base64 encoding of 64 random bytes should result in ~86 characters
    let verifier = sut.generateCodeVerifier()
    XCTAssertGreaterThanOrEqual(verifier.count, 85)
    XCTAssertLessThanOrEqual(verifier.count, 87)
  }

  func testGenerateCodeVerifierUniqueness() {
    // Each generated code verifier should be unique
    let verifier1 = sut.generateCodeVerifier()
    let verifier2 = sut.generateCodeVerifier()
    XCTAssertNotEqual(verifier1, verifier2)
  }

  func testGenerateCodeChallenge() {
    // Test with a known input-output pair
    let testVerifier = "test_verifier"
    let challenge = sut.generateCodeChallenge(testVerifier)

    // Expected value from the current implementation
    let expectedChallenge = "0Ku4rR8EgR1w3HyHLBCxVLtPsAAks5HOlpmTEt0XhVA"
    XCTAssertEqual(challenge, expectedChallenge)
  }

  func testPKCEBase64Encoding() {
    // Create data that will produce Base64 with special characters
    let testData = Data([251, 255, 191])  // This will produce Base64 with padding and special chars
    let encoded = testData.pkceBase64EncodedString()

    XCTAssertFalse(encoded.contains("+"), "Should not contain '+'")
    XCTAssertFalse(encoded.contains("/"), "Should not contain '/'")
    XCTAssertFalse(encoded.contains("="), "Should not contain '='")
    XCTAssertTrue(encoded.contains("-"), "Should contain '-' as replacement for '+'")
    XCTAssertTrue(encoded.contains("_"), "Should contain '_' as replacement for '/'")
  }
}
