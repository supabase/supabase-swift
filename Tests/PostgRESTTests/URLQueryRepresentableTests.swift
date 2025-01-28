import PostgREST
import XCTest

final class URLQueryRepresentableTests: XCTestCase {
  func testArray() {
    let array = ["is:online", "faction:red"]
    let queryValue = array.queryValue
    XCTAssertEqual(queryValue, "{is:online,faction:red}")
  }

  func testAnyJSON() {
    XCTAssertEqual(
      AnyJSON.array(["is:online", "faction:red"]).queryValue,
      "{is:online,faction:red}"
    )
    XCTAssertEqual(
      AnyJSON.object(["postalcode": 90210]).queryValue,
      "{\"postalcode\":90210}"
    )
    XCTAssertEqual(AnyJSON.string("string").queryValue, "string")
    XCTAssertEqual(AnyJSON.double(3.14).queryValue, "3.14")
    XCTAssertEqual(AnyJSON.integer(3).queryValue, "3")
    XCTAssertEqual(AnyJSON.bool(true).queryValue, "true")
    XCTAssertEqual(AnyJSON.null.queryValue, "NULL")
  }

  func testOptional() {
    XCTAssertEqual(Optional.some([1, 2]).queryValue, "{1,2}")
    XCTAssertEqual(Optional<[Int]>.none.queryValue, "NULL")
  }

  func testUUID() {
    XCTAssertEqual(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!.queryValue, "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
  }

  func testDate() {
    XCTAssertEqual(
      Date(timeIntervalSince1970: 1737465985).queryValue,
      "2025-01-21T13:26:25.000Z"
    )
  }
}
