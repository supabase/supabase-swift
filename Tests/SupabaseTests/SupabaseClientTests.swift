import Auth
import XCTest

@testable import Functions
@testable import Supabase

final class AuthLocalStorageMock: AuthLocalStorage {
  func store(key _: String, value _: Data) throws {}

  func retrieve(key _: String) throws -> Data? {
    nil
  }

  func remove(key _: String) throws {}
}

final class SupabaseClientTests: XCTestCase {
  func testClientInitialization() async {
    let customSchema = "custom_schema"
    let localStorage = AuthLocalStorageMock()
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
        ),
        functions: SupabaseClientOptions.FunctionsOptions(
          region: .apNortheast1
        )
      )
    )

    XCTAssertEqual(client.supabaseURL.absoluteString, "https://project-ref.supabase.co")
    XCTAssertEqual(client.supabaseKey, "ANON_KEY")
    XCTAssertEqual(client.storageURL.absoluteString, "https://project-ref.supabase.co/storage/v1")
    XCTAssertEqual(client.databaseURL.absoluteString, "https://project-ref.supabase.co/rest/v1")
    XCTAssertEqual(
      client.functionsURL.absoluteString,
      "https://project-ref.supabase.co/functions/v1"
    )

    XCTAssertEqual(
      client.defaultHeaders,
      [
        "X-Client-Info": "supabase-swift/\(Supabase.version)",
        "Apikey": "ANON_KEY",
        "header_field": "header_value",
        "Authorization": "Bearer ANON_KEY",
      ]
    )

    let region = await client.functions.region
    XCTAssertEqual(region, "ap-northeast-1")
  }

  #if !os(Linux)
    func testClientInitWithDefaultOptionsShouldBeAvailableInNonLinux() {
      _ = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "ANON_KEY"
      )
    }
  #endif
}
