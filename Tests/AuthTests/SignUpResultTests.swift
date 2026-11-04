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
  func emailChangeSingleConfirmation_isNotAValidSignUpResult() {
    #expect(throws: (any Error).self) {
      try AuthClient.Configuration.jsonDecoder.decode(
        SignUpResult.self,
        from: json(named: "email-change-single-confirmation")
      )
    }
  }
}
