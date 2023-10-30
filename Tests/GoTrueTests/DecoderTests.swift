import GoTrue
import SnapshotTesting
import XCTest

final class DecoderTests: XCTestCase {
  func testDecodeUser() {
    XCTAssertNoThrow(
      try JSONDecoder.goTrue.decode(User.self, from: json(named: "user"))
    )
  }

  func testDecodeSessionOrUser() {
    XCTAssertNoThrow(
      try JSONDecoder.goTrue.decode(
        AuthResponse.self, from: json(named: "session")
      )
    )
  }
}
