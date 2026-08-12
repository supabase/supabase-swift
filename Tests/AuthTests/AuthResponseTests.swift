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
    #expect(response.user != nil)
  }

  @Test
  func emailChangeSingleConfirmation() throws {
    let response = try AuthClient.Configuration.jsonDecoder.decode(
      AuthResponse.self,
      from: json(named: "email-change-single-confirmation")
    )
    #expect(response.session == nil)
    #expect(response.user == nil)
  }
}
