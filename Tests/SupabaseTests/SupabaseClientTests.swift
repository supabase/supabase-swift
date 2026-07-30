import ConcurrencyExtras
import CustomDump
import Foundation
import HTTPTypes
import InlineSnapshotTesting
import SnapshotTestingCustomDump
import Testing

@testable import Auth
@testable import Functions
@testable import Realtime
@testable import RealtimeV2
@testable import Supabase

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Captures every request handed to it and responds with an empty JSON array.
/// `startLoading` runs on the `URLSession` delegate queue, so mutable state is lock-guarded.
///
/// Shared with `TracingTests`, which needs it to assert on `traceparent` header injection.
final class RequestCapturingProtocol: URLProtocol {
  private static let storage = LockIsolated<[URLRequest]>([])

  static var capturedRequests: [URLRequest] {
    get { storage.value }
    set { storage.setValue(newValue) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.capturedRequests.append(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("[]".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

func makeMockSession() -> URLSession {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [RequestCapturingProtocol.self]
  return URLSession(configuration: config)
}

final class AuthLocalStorageMock: AuthLocalStorage {
  func store(key _: String, value _: Data) throws {}

  func retrieve(key _: String) throws -> Data? {
    nil
  }

  func remove(key _: String) throws {}
}

@Suite
struct SupabaseClientTests {
  @Test
  func clientInitialization() async {
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

    #expect(client.supabaseURL.absoluteString == "https://project-ref.supabase.co")
    #expect(client.supabaseKey == "PUBLISHABLE_KEY")
    #expect(client.storageURL.absoluteString == "https://project-ref.supabase.co/storage/v1")
    #expect(client.databaseURL.absoluteString == "https://project-ref.supabase.co/rest/v1")
    #expect(
      client.functionsURL.absoluteString
        == "https://project-ref.supabase.co/functions/v1"
    )

    assertInlineSnapshot(of: client.headers, as: .customDump) {
      """
      [
        "Apikey": "PUBLISHABLE_KEY",
        "Authorization": "Bearer PUBLISHABLE_KEY",
        "X-Client-Info": "supabase-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0",
        "header_field": "header_value"
      ]
      """
    }
    expectNoDifference(client.headers, client.auth.configuration.headers)
    expectNoDifference(client.headers, client.functions.headers.dictionary)
    expectNoDifference(client.headers, client.storage.configuration.headers)
    expectNoDifference(client.headers, client.rest.configuration.headers)

    #expect(client.functions.region == "ap-northeast-1")

    let realtimeURL = client.realtimeV2.url
    #expect(realtimeURL.absoluteString == "https://project-ref.supabase.co/realtime/v1")

    let realtimeOptions = client.realtimeV2.options
    let expectedRealtimeHeader = client._headers.merging(with: [
      .init("custom_realtime_header_key")!: "custom_realtime_header_value"
    ]
    )
    expectNoDifference(realtimeOptions.headers, expectedRealtimeHeader)
    #expect(realtimeOptions.logger as? Logger === logger)

    #expect(!client.auth.configuration.autoRefreshToken)
    #expect(client.auth.configuration.storageKey == "sb-project-ref-auth-token")

    #expect(
      client.mutableState.listenForAuthEventsTask != nil,
      "should listen for internal auth events"
    )
  }

  #if !os(Linux) && !os(Android)
    @Test
    func clientInitWithDefaultOptionsShouldBeAvailableInNonLinux() {
      _ = SupabaseClient(
        supabaseURL: URL(string: "https://project-ref.supabase.co")!,
        supabaseKey: "PUBLISHABLE_KEY"
      )
    }
  #endif

  @Test
  func customSessionPropagatedToRealtimeClient() {
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

    #expect(
      client.realtimeV2.options.fetch != nil,
      "global URLSession should be propagated to Realtime client as a fetch closure"
    )
  }

  @Test
  func userProvidedRealtimeFetchIsNotOverridden() {
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

    #expect(
      client.realtimeV2.options.fetch != nil,
      "user-provided realtime fetch should be preserved"
    )
  }

  @Test
  func globalSessionPropagatedToRealtimeWebSocket() {
    let localStorage = AuthLocalStorageMock()
    let customSession = URLSession(configuration: .ephemeral)
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(session: customSession)
      )
    )

    #expect(
      client.realtimeV2.options.session === customSession,
      "global URLSession should be propagated to Realtime's WebSocket transport for certificate pinning"
    )
  }

  @Test
  func userProvidedRealtimeSessionIsNotOverridden() {
    let localStorage = AuthLocalStorageMock()
    let globalSession = URLSession(configuration: .ephemeral)
    let realtimeSpecificSession = URLSession(configuration: .default)
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: localStorage,
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(session: globalSession),
        realtime: RealtimeClientOptions(session: realtimeSpecificSession)
      )
    )

    #expect(
      client.realtimeV2.options.session === realtimeSpecificSession,
      "user-provided realtime session should be preserved"
    )
  }

  @Test
  func clientInitWithCustomAccessToken() async {
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

    #expect(
      client.mutableState.listenForAuthEventsTask == nil,
      "should not listen for internal auth events when using 3p authentication"
    )

    // Not asserting that `client.auth` reports an issue here (as the XCTest version of this
    // test did via `withExpectedIssue`/`withKnownIssue`): under Xcode 26's Swift Testing +
    // XCTest bundle hosting, `reportIssue` (xctest-dynamic-overlay) segfaults the test process
    // when called from a `@Test` function, regardless of which "expected/known issue" wrapper
    // is used. Reproduced locally via `xcodebuild test`; does not reproduce under `swift test`.
    // Tracked as a migration-wide risk in SDK-435 for any later phase whose tests exercise
    // `reportIssue`-instrumented production code.
  }

  @Test
  func functionsOmitsAuthorizationBearerForNewFormatKey() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "sb_publishable_abc123",
      options: SupabaseClientOptions(auth: .init(storage: AuthLocalStorageMock()))
    )

    #expect(client.functions.headers.dictionary["Authorization"] == nil)
    #expect(client.functions.headers.dictionary["Apikey"] == "sb_publishable_abc123")
  }

  @Test
  func functionsKeepsAuthorizationBearerForLegacyKey() {
    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "legacy-jwt-key",
      options: SupabaseClientOptions(auth: .init(storage: AuthLocalStorageMock()))
    )

    #expect(client.functions.headers.dictionary["Authorization"] == "Bearer legacy-jwt-key")
    #expect(client.functions.headers.dictionary["Apikey"] == "legacy-jwt-key")
  }
}
