import CustomDump
import IssueReporting
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
  let jwt =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

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
      supabaseKey: jwt,
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
    XCTAssertEqual(client.supabaseKey, jwt)
    XCTAssertEqual(client.storageURL.absoluteString, "https://project-ref.supabase.co/storage/v1")
    XCTAssertEqual(client.databaseURL.absoluteString, "https://project-ref.supabase.co/rest/v1")
    XCTAssertEqual(
      client.functionsURL.absoluteString,
      "https://project-ref.supabase.co/functions/v1"
    )

    XCTAssertEqual(
      client.headers,
      [
        "X-Client-Info": "supabase-swift/\(Supabase.version)",
        "Apikey": jwt,
        "header_field": "header_value",
        "Authorization": "Bearer \(jwt)",
      ]
    )
    expectNoDifference(client._headers.dictionary, client.headers)

    XCTAssertEqual(client.functions.region, "ap-northeast-1")

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
        supabaseKey: jwt
      )
    }
  #endif

  func testClientInitWithCustomAccessToken() async {
    let localStorage = AuthLocalStorageMock()

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: jwt,
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
      withExpectedIssue(
        """
        Supabase Client is configured with the auth.accessToken option,
        accessing supabase.auth is not possible.
        """
      ) {
        _ = client.auth
      }
    #endif
  }

  #if canImport(Darwin)
    // withExpectedIssue is unavailable on non-Darwin platform.
    func testClientInitWithNonJWTAPIKey() {
      withExpectedIssue("Authorization header does not contain a JWT") {
        _ = SupabaseClient(
          supabaseURL: URL(string: "https://project-ref.supabase.co")!,
          supabaseKey: "invalid.token.format",
          options: SupabaseClientOptions(
            auth: .init(
              storage: AuthLocalStorageMock()
            )
          )
        )
      }
    }
  #endif
}
