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
}
