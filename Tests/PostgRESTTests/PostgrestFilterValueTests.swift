import Foundation
import PostgREST
import Testing

@Suite
struct PostgrestFilterValueTests {
  @Test
  func array() {
    let array = ["is:online", "faction:red"]
    let queryValue = array.rawValue
    #expect(queryValue == "{is:online,faction:red}")
  }

  @Test
  func anyJSON() {
    #expect(
      AnyJSON.array(["is:online", "faction:red"]).rawValue == "{is:online,faction:red}"
    )
    #expect(
      AnyJSON.object(["postalcode": 90210]).rawValue == "{\"postalcode\":90210}"
    )
    #expect(AnyJSON.string("string").rawValue == "string")
    #expect(AnyJSON.double(3.14).rawValue == "3.14")
    #expect(AnyJSON.integer(3).rawValue == "3")
    #expect(AnyJSON.bool(true).rawValue == "true")
    #expect(AnyJSON.null.rawValue == "NULL")
  }

  @Test
  func optional() {
    #expect(Optional.some([1, 2]).rawValue == "{1,2}")
    #expect(Optional<[Int]>.none.rawValue == "NULL")
  }

  @Test
  func uuid() {
    #expect(
      UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!.rawValue
        == "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
  }

  @Test
  func date() {
    #expect(
      Date(timeIntervalSince1970: 1_737_465_985).rawValue == "2025-01-21T13:26:25.000Z"
    )
  }
}
