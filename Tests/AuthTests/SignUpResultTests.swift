import Auth
import Foundation
import Testing

@Suite
struct SignUpResultTests {
  @Test
  func sessionBodyIsSignedIn() throws {
    let result = try AuthClient.Configuration.jsonDecoder.decode(
      SignUpResult.self,
      from: json(named: "session")
    )
    guard case .signedIn(let session) = result else {
      Issue.record("Expected .signedIn, got \(result)")
      return
    }
    #expect(result.session == session)
    #expect(result.user == session.user)
  }

  @Test
  func userBodyIsConfirmationRequired() throws {
    let result = try AuthClient.Configuration.jsonDecoder.decode(
      SignUpResult.self,
      from: json(named: "user")
    )
    guard case .confirmationRequired(let user) = result else {
      Issue.record("Expected .confirmationRequired, got \(result)")
      return
    }
    #expect(result.session == nil)
    #expect(result.user == user)
  }

  @Test
  func signUpConfirmationRequired() throws {
    let result = try AuthClient.Configuration.jsonDecoder.decode(
      SignUpResult.self,
      from: json(named: "signup-response")
    )
    #expect(result.session == nil)
    #expect(result.user.email == "jane@example.com")
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
  func emailChangeSingleConfirmation_isNotAValidSignUpResult() {
    #expect(throws: (any Error).self) {
      try AuthClient.Configuration.jsonDecoder.decode(
        SignUpResult.self,
        from: json(named: "email-change-single-confirmation")
      )
    }
  }

  @Test
  func bareUser_isNotAValidVerifyOTPResponse() {
    #expect(throws: (any Error).self) {
      try AuthClient.Configuration.jsonDecoder.decode(
        VerifyOTPResponse.self,
        from: json(named: "user")
      )
    }
  }
}
