import PostgREST
import XCTest

final class URLQueryRepresentableTests: XCTestCase {
  func testArray() {
    let array = ["is:online", "faction:red"]
    let queryValue = array.queryValue
    XCTAssertEqual(queryValue, "{is:online,faction:red}")
  }

  func testDictionary() {
    let dictionary = ["postalcode": 90210]
    let queryValue = dictionary.queryValue
    XCTAssertEqual(queryValue, "{\"postalcode\":90210}")
  }
}
