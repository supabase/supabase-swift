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
}
