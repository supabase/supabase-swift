@testable import Supabase
import XCTest

final class HeleperTests: XCTestCase {
  func testIsJWT() {
    XCTAssertTrue(isJWT("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"))
    XCTAssertTrue(isJWT("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"))
    XCTAssertFalse(isJWT("invalid.token.format"))
    XCTAssertFalse(isJWT("part1.part2.part3.part4"))
    XCTAssertFalse(isJWT("part1.part2"))
    XCTAssertFalse(isJWT(".."))
    XCTAssertFalse(isJWT("a.a.a"))
    XCTAssertFalse(isJWT("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.*&@!.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"))
    XCTAssertFalse(isJWT(""))
    XCTAssertFalse(isJWT("Bearer "))
  }
}
