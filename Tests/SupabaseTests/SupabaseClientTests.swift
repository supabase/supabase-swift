import GoTrue
import XCTest

@testable import Supabase

final class GoTrueLocalStorageMock: GoTrueLocalStorage {
  func store(key _: String, value _: Data) throws {}

  func retrieve(key _: String) throws -> Data? {
    nil
  }

  func remove(key _: String) throws {}
}

final class SupabaseClientTests: XCTestCase {
  func testClientInitialization() {
    let customSchema = "custom_schema"
    let localStorage = GoTrueLocalStorageMock()
    let customHeaders = ["header_field": "header_value"]

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "ANON_KEY",
      options: SupabaseClientOptions(
        db: SupabaseClientOptions.DatabaseOptions(schema: customSchema),
        auth: SupabaseClientOptions.AuthOptions(storage: localStorage),
        global: SupabaseClientOptions.GlobalOptions(
          headers: customHeaders,
          session: .shared
        )
      )
    )

    XCTAssertEqual(client.supabaseURL.absoluteString, "https://project-ref.supabase.co")
    XCTAssertEqual(client.supabaseKey, "ANON_KEY")
    XCTAssertEqual(client.authURL.absoluteString, "https://project-ref.supabase.co/auth/v1")
    XCTAssertEqual(client.storageURL.absoluteString, "https://project-ref.supabase.co/storage/v1")
    XCTAssertEqual(client.databaseURL.absoluteString, "https://project-ref.supabase.co/rest/v1")
    XCTAssertEqual(client.realtimeURL.absoluteString, "https://project-ref.supabase.co/realtime/v1")
    XCTAssertEqual(
      client.functionsURL.absoluteString,
      "https://project-ref.supabase.co/functions/v1"
    )

    XCTAssertEqual(
      client.defaultHeaders,
      [
        "X-Client-Info": "supabase-swift/\(Supabase.version)",
        "apikey": "ANON_KEY",
        "header_field": "header_value",
        "Authorization": "Bearer ANON_KEY",
      ]
    )
  }
}
