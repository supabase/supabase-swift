import Auth
import SnapshotTesting
import XCTest

final class AuthResponseTests: XCTestCase {
  func testSession() throws {
    let response = try AuthClient.Configuration.jsonDecoder.decode(
      AuthResponse.self,
      from: json(named: "session")
    )
    XCTAssertNotNil(response.session)
    XCTAssertEqual(response.user, response.session?.user)
  }

  func testUser() throws {
    let response = try AuthClient.Configuration.jsonDecoder.decode(
      AuthResponse.self,
      from: json(named: "user")
    )
    XCTAssertNil(response.session)
  }

  func testSignUpConfirmationRequired() throws {
    let response = try AuthClient.Configuration.jsonDecoder.decode(
      AuthResponse.self,
      from: json(named: "signup-response")
    )
    XCTAssertNil(response.session)
    XCTAssertNotNil(response.user)
  }

  func testEmailChangeSingleConfirmation() throws {
    let response = try AuthClient.Configuration.jsonDecoder.decode(
      AuthResponse.self,
      from: json(named: "email-change-single-confirmation")
    )
    XCTAssertNil(response.session)
    XCTAssertNil(response.user)
  }
}
