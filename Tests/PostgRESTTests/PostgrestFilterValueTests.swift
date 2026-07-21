import PostgREST
import XCTest

final class PostgrestFilterValue: XCTestCase {
  func testArray() {
    let array = ["is:online", "faction:red"]
    let queryValue = array.rawValue
    XCTAssertEqual(queryValue, "{is:online,faction:red}")
  }

  func testArrayQuotesElementsContainingReservedCharacters() {
    XCTAssertEqual(["a,b"].rawValue, "{\"a,b\"}")
    XCTAssertEqual(["a", "b,c", "d"].rawValue, "{a,\"b,c\",d}")
    XCTAssertEqual(["a{b"].rawValue, "{\"a{b\"}")
  }

  func testArrayEscapesQuotesAndBackslashes() {
    XCTAssertEqual([#"a"b"#].rawValue, #"{"a\"b"}"#)
    XCTAssertEqual([#"a\b"#].rawValue, #"{"a\\b"}"#)
  }

  func testArrayQuotesWhitespaceEmptyAndNullElements() {
    XCTAssertEqual([" a"].rawValue, "{\" a\"}")
    XCTAssertEqual([""].rawValue, "{\"\"}")
    XCTAssertEqual(["NULL"].rawValue, "{\"NULL\"}")
    XCTAssertEqual(["null"].rawValue, "{\"null\"}")
  }

  func testArrayLeavesSafeAndNumericElementsUnquoted() {
    XCTAssertEqual([1, 2, 3].rawValue, "{1,2,3}")
    XCTAssertEqual(["admin", "user"].rawValue, "{admin,user}")
    XCTAssertEqual(["9:00", "17:00"].rawValue, "{9:00,17:00}")
  }

  func testArrayPreservesNestedArrayLiterals() {
    XCTAssertEqual([[1, 2], [3, 4]].rawValue, "{{1,2},{3,4}}")
  }

  func testAnyJSONArrayEscapesReservedCharacters() {
    XCTAssertEqual(AnyJSON.array(["a,b"]).rawValue, "{\"a,b\"}")
  }

  func testAnyJSON() {
    XCTAssertEqual(
      AnyJSON.array(["is:online", "faction:red"]).rawValue,
      "{is:online,faction:red}"
    )
    XCTAssertEqual(
      AnyJSON.object(["postalcode": 90210]).rawValue,
      "{\"postalcode\":90210}"
    )
    XCTAssertEqual(AnyJSON.string("string").rawValue, "string")
    XCTAssertEqual(AnyJSON.double(3.14).rawValue, "3.14")
    XCTAssertEqual(AnyJSON.integer(3).rawValue, "3")
    XCTAssertEqual(AnyJSON.bool(true).rawValue, "true")
    XCTAssertEqual(AnyJSON.null.rawValue, "NULL")
  }

  func testOptional() {
    XCTAssertEqual(Optional.some([1, 2]).rawValue, "{1,2}")
    XCTAssertEqual(Optional<[Int]>.none.rawValue, "NULL")
  }

  func testUUID() {
    XCTAssertEqual(
      UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!.rawValue,
      "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
  }

  func testDate() {
    XCTAssertEqual(
      Date(timeIntervalSince1970: 1_737_465_985).rawValue,
      "2025-01-21T13:26:25.000Z"
    )
  }
}
