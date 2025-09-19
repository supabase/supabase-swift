import Foundation
import Testing

@testable import Auth

@Suite struct AuthResponseTests {
  @Test("Session response contains valid session and user")
  func testSession() throws {
    let response = try JSONDecoder.supabase().decode(
      AuthResponse.self,
      from: json(named: "session")
    )
    #expect(response.session != nil)
    #expect(response.user == response.session?.user)
  }

  @Test("User response contains no session")
  func testUser() throws {
    let response = try JSONDecoder.supabase().decode(
      AuthResponse.self,
      from: json(named: "user")
    )
    #expect(response.session == nil)
  }
}
