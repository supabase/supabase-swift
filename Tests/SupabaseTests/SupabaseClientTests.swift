import Alamofire
import CustomDump
import Helpers
import InlineSnapshotTesting
import IssueReporting
import Logging
import SnapshotTestingCustomDump
import XCTest

@testable import Auth
@testable import Functions
@testable import Realtime
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
    let logger = Logger(label: "test")
    let customSchema = "custom_schema"
    let localStorage = AuthLocalStorageMock()
    let customHeaders = ["header_field": "header_value"]

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "ANON_KEY",
      options: SupabaseClientOptions(
        db: SupabaseClientOptions.DatabaseOptions(schema: customSchema),
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          headers: customHeaders,
          session: .default,
          logger: logger
        ),
        functions: SupabaseClientOptions.FunctionsOptions(
          region: .apNortheast1
        ),
        realtime: RealtimeClientOptions(
          headers: ["custom_realtime_header_key": "custom_realtime_header_value"]
        )
      )
    )

    XCTAssertEqual(await client.supabaseURL.absoluteString, "https://project-ref.supabase.co")
    XCTAssertEqual(await client.supabaseKey, "ANON_KEY")
    XCTAssertEqual(await client.storageURL.absoluteString, "https://project-ref.supabase.co/storage/v1")
    XCTAssertEqual(await client.databaseURL.absoluteString, "https://project-ref.supabase.co/rest/v1")
    XCTAssertEqual(
      await client.functionsURL.absoluteString,
      "https://project-ref.supabase.co/functions/v1"
    )

    assertInlineSnapshot(of: await client.headers as [String: String], as: .customDump) {
      """
      [
        "Apikey": "ANON_KEY",
        "Authorization": "Bearer ANON_KEY",
        "X-Client-Info": "supabase-swift/0.0.0",
        "X-Supabase-Client-Platform": "macOS",
        "X-Supabase-Client-Platform-Version": "0.0.0",
        "header_field": "header_value"
      ]
      """
    }

    let functionsHeaders = await client.functions.headers.dictionary
    expectNoDifference(await client.headers, functionsHeaders)
    expectNoDifference(await client.headers, await client.storage.configuration.headers)
    // Note: client.rest no longer exists in the new architecture

//    XCTAssertEqual(client.functions.region?.rawValue, "ap-northeast-1")

    let realtimeURL = await client.realtime.url
    XCTAssertEqual(realtimeURL.absoluteString, "https://project-ref.supabase.co/realtime/v1")

    let realtimeOptions = await client.realtime.options
    // Note: client._headers is private, so we can't access it directly
    expectNoDifference(realtimeOptions.headers.sorted(), [
      "custom_realtime_header_key": "custom_realtime_header_value"
    ].sorted())
    XCTAssertEqual(realtimeOptions.logger?.label, logger.label)

    XCTAssertFalse(await client.auth.configuration.autoRefreshToken)
    XCTAssertEqual(await client.auth.configuration.storageKey, "sb-project-ref-auth-token")

    // Note: client.mutableState no longer exists in the new architecture
    // The auth event listening is now handled internally
  }

  #if !os(Linux) && !os(Android)
    func testClientInitWithDefaultOptionsShouldBeAvailableInNonLinux() {
      _ = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "ANON_KEY"
      )
    }
  #endif

  func testClientInitWithCustomAccessToken() async {
    let localStorage = AuthLocalStorageMock()

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "ANON_KEY",
      options: .init(
        auth: .init(
          storage: localStorage,
          accessToken: { "jwt" }
        )
      )
    )

    // Note: client.mutableState no longer exists in the new architecture
    // The auth event listening is now handled internally

    #if canImport(Darwin)
      // withExpectedIssue is unavailable on non-Darwin platform.
      withExpectedIssue {
        _ = await client.auth
      }
    #endif
  }
}
