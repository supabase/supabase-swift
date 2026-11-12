import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestRPCArgumentTests {
  @Test(arguments: [
    ("9223372036854775809", "9223372036854775809"),
    ("-12345678901234567.89", "-12345678901234567.89"),
    ("0.1", "0.1"),
    ("42", "42"),
    ("1e300", "1e300"),
  ])
  func aNumberKeepsItsDigits(json: String, rendered: String) {
    let items = PostgrestClient.queryItems(forJSONObject: Data(#"{"n":\#(json)}"#.utf8))
    #expect(items == [URLQueryItem(name: "n", value: rendered)])
  }

  @Test
  func aBodyThatIsNotAnObjectHasNoQueryItems() {
    #expect(PostgrestClient.queryItems(forJSONObject: Data("[1,2]".utf8)) == nil)
  }
}
