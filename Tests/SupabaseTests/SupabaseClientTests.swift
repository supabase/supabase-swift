import CustomDump
import InlineSnapshotTesting
import IssueReporting
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
    final class Logger: SupabaseLogger {
      func log(message _: SupabaseLogMessage) {
        // no-op
      }
    }

    let logger = Logger()
    let customSchema = "custom_schema"
    let localStorage = AuthLocalStorageMock()
    let customHeaders = ["header_field": "header_value"]

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        db: SupabaseClientOptions.DatabaseOptions(schema: customSchema),
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          headers: customHeaders,
          session: .shared,
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

    XCTAssertEqual(client.supabaseURL.absoluteString, "https://project-ref.supabase.co")
    XCTAssertEqual(client.supabaseKey, "PUBLISHABLE_KEY")
    XCTAssertEqual(client.storageURL.absoluteString, "https://project-ref.supabase.co/storage/v1")
    XCTAssertEqual(client.databaseURL.absoluteString, "https://project-ref.supabase.co/rest/v1")
    XCTAssertEqual(
      client.functionsURL.absoluteString,
      "https://project-ref.supabase.co/functions/v1"
    )

    assertInlineSnapshot(of: client.headers, as: .customDump) {
      """
      [
        "Apikey": "PUBLISHABLE_KEY",
        "Authorization": "Bearer PUBLISHABLE_KEY",
        "X-Client-Info": "supabase-swift/0.0.0",
        "X-Supabase-Client-Platform": "macOS",
        "X-Supabase-Client-Platform-Version": "0.0.0",
        "header_field": "header_value"
      ]
      """
    }
    let functionsHeaders = await client.functions.headers
    let functionsRegion = await client.functions.region
    expectNoDifference(client.headers, client.auth.configuration.headers)
<<<<<<< HEAD
    expectNoDifference(client.headers, functionsHeaders)
=======
    expectNoDifference(client.headers, client.functions.headers)
>>>>>>> 9e4ae44 (fix(functions): catch HTTPClientError and convert to FunctionsError in rawInvoke)
    expectNoDifference(client.headers, client.storage.configuration.headers)
    expectNoDifference(client.headers, client.rest.configuration.headers)

    XCTAssertEqual(functionsRegion, .apNortheast1)

    let realtimeURL = client.realtimeV2.url
    XCTAssertEqual(realtimeURL.absoluteString, "https://project-ref.supabase.co/realtime/v1")

    let realtimeOptions = client.realtimeV2.options
    let expectedRealtimeHeader = client._headers.merging(with: [
      .init("custom_realtime_header_key")!: "custom_realtime_header_value"
    ]
    )
    expectNoDifference(realtimeOptions.headers, expectedRealtimeHeader)
    XCTAssertIdentical(realtimeOptions.logger as? Logger, logger)

    XCTAssertFalse(client.auth.configuration.autoRefreshToken)
    XCTAssertEqual(client.auth.configuration.storageKey, "sb-project-ref-auth-token")

    XCTAssertNotNil(
      client.mutableState.listenForAuthEventsTask,
      "should listen for internal auth events"
    )
  }

  #if !os(Linux) && !os(Android)
    func testClientInitWithDefaultOptionsShouldBeAvailableInNonLinux() {
      _ = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY"
      )
    }
  #endif

  func testCustomSessionPropagatedToRealtimeClient() {
    let localStorage = AuthLocalStorageMock()
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(session: .shared)
      )
    )

    XCTAssertNotNil(
      client.realtimeV2.options.fetch,
      "global URLSession should be propagated to Realtime client as a fetch closure"
    )
  }

  func testUserProvidedRealtimeFetchIsNotOverridden() {
    let localStorage = AuthLocalStorageMock()
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefreshToken: false
        ),
        realtime: RealtimeClientOptions(
          fetch: { _ in throw URLError(.cancelled) }
        )
      )
    )

    XCTAssertNotNil(
      client.realtimeV2.options.fetch,
      "user-provided realtime fetch should be preserved"
    )
  }

  func testClientInitWithCustomAccessToken() async {
    let localStorage = AuthLocalStorageMock()

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: .init(
        auth: .init(
          storage: localStorage,
          accessToken: { "jwt" }
        )
      )
    )

    XCTAssertNil(
      client.mutableState.listenForAuthEventsTask,
      "should not listen for internal auth events when using 3p authentication"
    )

    #if canImport(Darwin)
      // withExpectedIssue is unavailable on non-Darwin platform.
      withExpectedIssue {
        _ = client.auth
      }
    #endif
  }
}
