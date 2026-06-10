import CustomDump
import InlineSnapshotTesting
import IssueReporting
import SnapshotTestingCustomDump
import XCTest

@testable import Auth
@testable import Functions
@testable import Realtime
@testable import Supabase

// MARK: - Helpers

private final class RequestCapturingProtocol: URLProtocol {
  // NSLock guards the mutable statics — startLoading runs on the URLSession delegate queue.
  private static let lock = NSLock()
  private static var _capturedRequests: [URLRequest] = []
  private static var _stubbedData = Data("[]".utf8)
  private static var _stubbedStatusCode = 200

  static var capturedRequests: [URLRequest] {
    get { lock.withLock { _capturedRequests } }
    set { lock.withLock { _capturedRequests = newValue } }
  }

  static var stubbedData: Data {
    get { lock.withLock { _stubbedData } }
    set { lock.withLock { _stubbedData = newValue } }
  }

  static var stubbedStatusCode: Int {
    get { lock.withLock { _stubbedStatusCode } }
    set { lock.withLock { _stubbedStatusCode = newValue } }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let captured = request
    Self.lock.withLock { Self._capturedRequests.append(captured) }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: Self.lock.withLock { Self._stubbedStatusCode },
      httpVersion: "HTTP/1.1",
      headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.lock.withLock { Self._stubbedData })
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
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
        "X-Client-Info": "supabase-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0",
        "header_field": "header_value"
      ]
      """
    }
    expectNoDifference(client.headers, client.auth.configuration.headers)
    expectNoDifference(client.headers, client.functions.headers.dictionary)
    expectNoDifference(client.headers, client.storage.configuration.headers)
    expectNoDifference(client.headers, client.rest.configuration.headers)

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

  func testTracePropagationInjectsTraceParentHeader() async throws {
    struct MockTraceContextProvider: TraceContextProvider {
      func traceContext() -> [String: String] {
        ["traceparent": "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"]
      }
    }

    RequestCapturingProtocol.capturedRequests = []

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          session: makeMockSession(),
          tracePropagation: MockTraceContextProvider()
        )
      )
    )

    _ = try? await client.from("todos").select().execute()

    XCTAssertFalse(
      RequestCapturingProtocol.capturedRequests.isEmpty, "Expected at least one request")
    let request = try XCTUnwrap(RequestCapturingProtocol.capturedRequests.first)
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "traceparent"),
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
    )
  }

  func testTracePropagationIsNoOpWhenNil() async throws {
    RequestCapturingProtocol.capturedRequests = []

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          session: makeMockSession()
        )
      )
    )

    _ = try? await client.from("todos").select().execute()

    XCTAssertFalse(
      RequestCapturingProtocol.capturedRequests.isEmpty, "Expected at least one request")
    let request = try XCTUnwrap(RequestCapturingProtocol.capturedRequests.first)
    XCTAssertNil(request.value(forHTTPHeaderField: "traceparent"))
  }

  func testTracePropagationInjectsHeaderIntoAuthRequests() async throws {
    struct MockTraceContextProvider: TraceContextProvider {
      func traceContext() -> [String: String] {
        ["traceparent": "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"]
      }
    }

    RequestCapturingProtocol.capturedRequests = []

    let client = SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: AuthLocalStorageMock(),
          autoRefreshToken: false
        ),
        global: SupabaseClientOptions.GlobalOptions(
          session: makeMockSession(),
          tracePropagation: MockTraceContextProvider()
        )
      )
    )

    _ = try? await client.auth.signUp(email: "test@example.com", password: "password123")

    XCTAssertFalse(
      RequestCapturingProtocol.capturedRequests.isEmpty, "Expected at least one request")
    let request = try XCTUnwrap(RequestCapturingProtocol.capturedRequests.first)
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "traceparent"),
      "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
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
