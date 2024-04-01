@testable import Auth
import SnapshotTesting
import XCTest

final class StoredSessionTests: XCTestCase {
  func testDecode2_4_0() throws {
    XCTAssertNoThrow(try AuthClient.Configuration.jsonDecoder.decode(
      StoredSession.self,
      from: json(named: "stored-session_2_4_0")
    ))
  }

  func testDecode2_5_0() throws {
    XCTAssertNoThrow(try AuthClient.Configuration.jsonDecoder.decode(
      StoredSession.self,
      from: json(named: "stored-session_2_5_0")
    ))
  }
}
