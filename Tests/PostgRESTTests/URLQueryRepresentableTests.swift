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
}
