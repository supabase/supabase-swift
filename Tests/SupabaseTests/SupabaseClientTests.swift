@testable import Supabase
import XCTest

final class SupabaseClientTests: XCTestCase {
  func testFunctionsURL() {
    var client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "ANON_KEY"
    )
    XCTAssertEqual(client.functionsURL.absoluteString, "https://project-ref.functions.supabase.co")

    client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.in")!,
      supabaseKey: "ANON_KEY"
    )
    XCTAssertEqual(client.functionsURL.absoluteString, "https://project-ref.functions.supabase.in")

    client = SupabaseClient(
      supabaseURL: URL(string: "https://custom-domain.com")!,
      supabaseKey: "ANON_KEY"
    )
    XCTAssertEqual(client.functionsURL.absoluteString, "https://custom-domain.com/functions/v1")
  }
}
