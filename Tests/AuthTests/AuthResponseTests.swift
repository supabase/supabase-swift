import Auth
import Foundation
import Testing

@Suite
struct AuthResponseTests {
  @Test
  func session() throws {
    let response = try AuthClient.Configuration.jsonDecoder.decode(
      AuthResponse.self,
      from: json(named: "session")
    )
    #expect(response.session != nil)
    #expect(response.user == response.session?.user)
  }

  @Test
  func user() throws {
    let response = try AuthClient.Configuration.jsonDecoder.decode(
      AuthResponse.self,
      from: json(named: "user")
    )
    #expect(response.session == nil)
  }

  @Test
  func signUpConfirmationRequired() throws {
    let response = try AuthClient.Configuration.jsonDecoder.decode(
      AuthResponse.self,
      from: json(named: "signup-response")
    )
    #expect(response.session == nil)
    #expect(response.user.email == "jane@example.com")
  }

  @Test
  func emailChangeSingleConfirmation() throws {
    let response = try AuthClient.Configuration.jsonDecoder.decode(
      VerifyOTPResponse.self,
      from: json(named: "email-change-single-confirmation")
    )
    #expect(response.session == nil)
    guard case .emailChangeConfirmationPending(let confirmation) = response else {
      Issue.record("Expected .emailChangeConfirmationPending, got \(response)")
      return
    }
    #expect(confirmation.code == "200")
    #expect(
      confirmation.message
        == "Confirmation link accepted. Please proceed to confirm link sent to the other email"
    )
  }

  @Test
  func emailChangeSingleConfirmation_isNotAValidAuthResponse() {
    #expect(throws: (any Error).self) {
      try AuthClient.Configuration.jsonDecoder.decode(
        AuthResponse.self,
        from: json(named: "email-change-single-confirmation")
      )
    }
  }

  @Test
  func bareUser_isNotAValidVerifyOTPResponse() {
    // The /verify endpoint verifyOTP calls never returns a bare user with no session: unlike signUp,
    // every verification type either issues a session or (for the first of the two secure
    // email change confirmations) the emailChangeConfirmationPending shape above.
    #expect(throws: (any Error).self) {
      try AuthClient.Configuration.jsonDecoder.decode(
        VerifyOTPResponse.self,
        from: json(named: "user")
      )
    }
  }
}
