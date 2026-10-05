import Foundation
import HTTPTypes
import Helpers
import Mocker
import TestHelpers
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Captures the last `HTTPRequest` seen by a custom transport, for tests that need to inspect
/// properties (like the resolved timeout) not surfaced by Mocker's `snapshotRequest` curl output.
private actor CapturedRequestBox {
  var request: HTTPTypes.HTTPRequest?
  var timeout: Duration?

  func set(_ request: HTTPTypes.HTTPRequest, timeout: Duration?) {
    self.request = request
    self.timeout = timeout
  }
}

/// `.serialized`: Mocker registers stubs in a process-global table with no per-test isolation, so
/// tests that stub overlapping URLs (e.g. `hello-world`) would otherwise race against each other
/// under Swift Testing's default parallel execution. `.mockerSerialized` (see
/// `TestHelpers/MockerSerialization.swift`) extends that guarantee across test *targets* too --
/// StorageTests and PostgRESTTests have their own Mocker-backed suites, and without it this suite
/// can still run concurrently with theirs and race on Mocker's shared registry.
@Suite(.serialized, .mockerSerialized)
struct FunctionsClientTests {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

  private var headers: HTTPFields { [HTTPField.Name("apikey")!: apiKey] }

  private func makeSUT(
    region: FunctionRegion? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) -> FunctionsClient {
    Mocker.removeAll()

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: sessionConfiguration)
    return makeClient(
      region: region,
      http: .init(transport: URLSessionTransport(session: session)),
      accessToken: accessToken
    )
  }

  private func makeSUT(
    transport:
      @escaping @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) -> FunctionsClient {
    makeClient(http: .init(transport: ClosureTransport(handler: transport)))
  }

  private func makeClient(
    region: FunctionRegion? = nil,
    http: HTTPClientConfiguration,
    decoder: JSONDecoder = .supabase(),
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) -> FunctionsClient {
    FunctionsClient(
      configuration: .init(
        url: url, headers: headers, region: region, http: http, decoder: decoder,
        accessToken: accessToken))
  }

  @Test
  func `init`() async {
    let client = FunctionsClient(
      configuration: .init(url: url, headers: headers, region: .saEast1))

    #expect(client.configuration.region == .saEast1)
    #expect(client.configuration.headers[.init("apikey")!] == apiKey)
    #expect(client.configuration.url == url)
  }

  @Test
  func initWithCustomDecoder() async {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let client = FunctionsClient(
      configuration: .init(url: url, headers: headers, decoder: decoder))

    #expect(client.configuration.decoder === decoder)
  }

  // Not asserting that `init(configuration:)` reports an issue for an `Authorization` header in
  // `Configuration.headers`: `reportIssue` (swift-issue-reporting) called from a `@Test`
  // function segfaults the test process on some toolchains (the nightly Linux job, and Xcode's
  // XCTest hosting), regardless of the expected-issue wrapper used. Tracked in SDK-435; the
  // same note applies in `SupabaseClientTests`.

  @Test
  func invokeReturnsTheResponseHead() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data("hi".utf8)],
      additionalHeaders: [
        "Content-Type": "text/plain",
        "x-sb-edge-region": "eu-central-2",
        "x-deno-execution-id": "exec-1",
      ]
    )
    .register()

    let response = try await sut.invoke("hello")

    #expect(response.status == .ok)
    #expect(response.contentType == "text/plain")
    #expect(response.region == .euCentral2)
    #expect(response.executionID == "exec-1")
    #expect(response.text == "hi")
  }

  /// The default decoder reads the ISO 8601 date a TypeScript function writes with
  /// `JSON.stringify`; `JSONDecoder()` would not.
  @Test
  func invokeDecodesISO8601DatesByDefault() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data(#"{"at":"2026-10-05T12:34:56.789Z"}"#.utf8)]
    )
    .register()

    struct Payload: Decodable {
      var at: Date
    }

    let payload: Payload = try await sut.invoke("hello")
    #expect(payload.at == Date(timeIntervalSince1970: 1_791_203_696.789))
  }

  @Test
  func perCallDecoderWinsOverTheClientDecoder() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello"),
      statusCode: 200,
      data: [.post: Data(#"{"user_name":"a"}"#.utf8)]
    )
    .register()

    struct Payload: Decodable {
      var userName: String
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let payload = try await sut.invoke("hello", as: Payload.self, decoder: decoder)
    #expect(payload.userName == "a")
  }

  /// A body that fails to encode is rejected before anything is sent.
  @Test
  func invokeWithABodyThatFailsToEncodeSendsNothing() async {
    struct Failing: Encodable {
      struct Reason: Error {}
      func encode(to encoder: any Encoder) throws { throw Reason() }
    }
    let sut = makeSUT { _, _ in
      Issue.record("transport should not be called")
      return (HTTPTypes.HTTPResponse(status: .ok), nil)
    }

    do {
      try await sut.invoke("hello", body: .json(Failing()))
      Issue.record("Expected failure")
    } catch let error as FunctionsError {
      #expect(error.kind == .invalidRequest)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func invoke() async throws {
    let sut = makeSUT()

    Mock(
      url: self.url.appendingPathComponent("hello_world"),
      statusCode: 200,
      data: [.post: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 19" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "X-Custom-Key: value" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"name\":\"Supabase\"}" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }
    .register()

    try await sut.invoke(
      "hello_world",
      body: .json(["name": "Supabase"]),
      options: .init(headers: [.init("X-Custom-Key")!: "value"])
    )
  }

  @Test
  func invokeReturningDecodable() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello"),
      statusCode: 200,
      data: [
        .post: #"{"message":"Hello, world!","status":"ok"}"#.data(using: .utf8)!
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello"
      """#
    }
    .register()

    struct Payload: Decodable {
      var message: String
      var status: String
    }

    let response = try await sut.invoke("hello") as Payload
    #expect(response.message == "Hello, world!")
    #expect(response.status == "ok")

    let explicit = try await sut.invoke("hello", as: Payload.self)
    #expect(explicit.message == "Hello, world!")
  }

  @Test
  func invokeWithCustomMethod() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello-world"),
      statusCode: 200,
      data: [.delete: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request DELETE \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }
    .register()

    try await sut.invoke("hello-world", options: .init(method: .delete))
  }

  @Test
  func invokeWithQuery() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello-world"),
      ignoreQuery: true,
      statusCode: 200,
      data: [
        .post: Data()
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world?key=value"
      """#
    }
    .register()

    try await sut.invoke(
      "hello-world",
      options: .init(
        query: [URLQueryItem(name: "key", value: "value")]
      )
    )
  }

  @Test
  func invokeWithRegionDefinedInClient() async throws {
    let sut = makeSUT(region: .caCentral1)

    Mock(
      url: url.appendingPathComponent("hello-world"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-region: ca-central-1" \
      	"http://localhost:5432/functions/v1/hello-world?forceFunctionRegion=ca-central-1"
      """#
    }
    .register()

    try await sut.invoke("hello-world")
  }

  @Test
  func invokeWithRegion() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello-world"),
      ignoreQuery: true,
      statusCode: 200,
      data: [.post: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-region: ca-central-1" \
      	"http://localhost:5432/functions/v1/hello-world?forceFunctionRegion=ca-central-1"
      """#
    }
    .register()

    try await sut.invoke("hello-world", options: .init(region: .caCentral1))
  }

  @Test
  func invokeWithoutRegion() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello-world"),
      statusCode: 200,
      data: [.post: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }
    .register()

    try await sut.invoke("hello-world")
  }

  @Test
  func invoke_badServerResponse_wrapsAsTransport() async {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello_world"),
      statusCode: 200,
      data: [.post: Data()],
      requestError: URLError(.badServerResponse)
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }
    .register()

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .transport)
      #expect((error.underlyingError as? URLError)?.code == .badServerResponse)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func invoke_shouldThrow_FunctionsError_httpError() async {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello_world"),
      statusCode: 300,
      data: [.post: Data()]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }
    .register()

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .server)
      #expect(error.response?.statusCode == 300)
      #expect(error.response?.body == Data())
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func invoke_shouldThrow_FunctionsError_relayError() async {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello_world"),
      statusCode: 200,
      data: [.post: Data()],
      additionalHeaders: [
        "x-relay-error": "true"
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }
    .register()

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .relay)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func invoke_relayErrorWithNon2xxStatus_shouldThrowRelayError() async {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello_world"),
      statusCode: 500,
      data: [.post: Data()],
      additionalHeaders: [
        "x-relay-error": "true"
      ]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }
    .register()

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .relay)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func invoke_transportFailure_wrapsURLError() async {
    let sut = makeSUT { _, _ in throw URLError(.notConnectedToInternet) }

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .transport)
      #expect(error.response == nil)
      #expect((error.underlyingError as? URLError)?.code == .notConnectedToInternet)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func invoke_cancellation_isNotWrapped() async {
    let sut = makeSUT { _, _ in throw CancellationError() }

    await #expect(throws: CancellationError.self) {
      try await sut.invoke("hello_world")
    }
  }

  /// A `URLError(.cancelled)` that is not caused by cancelling the caller's `Task` (a middleware
  /// or a custom transport cancelled the request) is a transport failure.
  @Test
  func invoke_cancelledURLErrorWithoutTaskCancellation_isWrapped() async {
    let sut = makeSUT { _, _ in throw URLError(.cancelled) }

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .transport)
      #expect((error.underlyingError as? URLError)?.code == .cancelled)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  /// Cancelling the enclosing `Task` mid-flight makes the real ``URLSessionTransport`` fail with
  /// `URLError(.cancelled)`; Functions reports it as `CancellationError` (SDK-2141).
  @Test
  func invoke_cancellingTheTask_throwsCancellationError() async {
    let sut = makeSUT()
    let (requestStarted, onRequestStarted) = AsyncStream<Void>.makeStream()

    var mock = Mock(
      url: url.appendingPathComponent("hello_world"),
      statusCode: 200,
      data: [.post: Data()]
    )
    // `MockingURLProtocol` runs the request callback before it schedules the delayed response,
    // so the cancel below always lands while the request is in flight. The delay is never
    // waited out: cancelling makes `stopLoading()` drop the pending response.
    mock.delay = .seconds(10)
    mock.onRequestHandler = OnRequestHandler(requestCallback: { _ in onRequestStarted.yield() })
    mock.register()

    let task = Task { try await sut.invoke("hello_world") }
    for await _ in requestStarted { break }
    task.cancel()

    do {
      try await task.value
      Issue.record("Expected failure")
    } catch is CancellationError {
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  /// A non-2xx body is collected up to `FunctionsAPI.maxErrorBodyBytes`, keeping the
  /// prefix, so an unbounded error response cannot hold the call open or exhaust memory
  /// (SDK-1840).
  @Test
  func invoke_serverErrorBody_isCappedKeepingThePrefix() async {
    let sut = makeSUT()
    let cap = FunctionsAPI.maxErrorBodyBytes
    let body = Data((0..<(cap + 4096)).map { UInt8(truncatingIfNeeded: $0) })

    Mock(
      url: url.appendingPathComponent("hello_world"),
      statusCode: 500,
      data: [.post: body]
    )
    .register()

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .server)
      #expect(error.response?.body == body.prefix(cap))
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func invoke_customFetchError_isNotWrapped() async {
    struct FetchError: Error {}
    let sut = makeSUT { _, _ in throw FetchError() }

    await #expect(throws: FetchError.self) {
      try await sut.invoke("hello_world")
    }
  }

  @Test
  func invoke_undecodableBody_wrapsDecodingError() async {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("hello_world"),
      statusCode: 200,
      data: [.post: Data("not json".utf8)]
    )
    .register()

    do {
      let _: [String: String] = try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .decoding)
      #expect(error.response == nil)
      #expect(error.underlyingError is DecodingError)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func invokeWithTimeoutOverride() async throws {
    let box = CapturedRequestBox()
    let sut = makeClient(
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeout: RequestTimeout.current)
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }))

    try await sut.invoke("hello-world", options: .init(timeout: .seconds(30)))

    let capturedTimeout = await box.timeout
    #expect(capturedTimeout == .seconds(30))
  }

  @Test
  func invokeWithDefaultTimeout() async throws {
    let box = CapturedRequestBox()
    let sut = makeClient(
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeout: RequestTimeout.current)
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }))

    try await sut.invoke("hello-world")

    let capturedTimeout = await box.timeout
    #expect(capturedTimeout == FunctionsClient.requestIdleTimeout)
  }

  @Test
  func configuredTimeoutIntervalReplacesTheFunctionsDefault() async throws {
    let box = CapturedRequestBox()
    let sut = makeClient(
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeout: RequestTimeout.current)
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        },
        timeout: .seconds(20)))

    try await sut.invoke("hello-world")
    let configuredTimeout = await box.timeout
    #expect(configuredTimeout == .seconds(20))

    try await sut.invoke("hello-world", options: .init(timeout: .seconds(30)))
    let perInvocationTimeout = await box.timeout
    #expect(perInvocationTimeout == .seconds(30))
  }

  @Test
  func accessTokenProviderSetsAuthorizationHeader() async throws {
    let box = CapturedRequestBox()
    let sut = makeClient(
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeout: nil)
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }),
      accessToken: { "access.token" }
    )

    try await sut.invoke("hello-world")

    let capturedRequest = await box.request
    #expect(capturedRequest?.headerFields[.authorization] == "Bearer access.token")
  }

  @Test
  func accessTokenProviderIsResolvedPerInvoke() async throws {
    actor TokenBox {
      var token = "first.token"
      func update(_ newValue: String) { token = newValue }
    }
    actor Capture {
      var authorizationHeaders: [String?] = []
      func record(_ value: String?) { authorizationHeaders.append(value) }
    }

    let tokenBox = TokenBox()
    let capture = Capture()

    let sut = makeClient(
      http: .init(
        transport: ClosureTransport { request, _ in
          await capture.record(request.headerFields[.authorization])
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }),
      accessToken: { await tokenBox.token }
    )

    try await sut.invoke("hello-world")
    await tokenBox.update("second.token")
    try await sut.invoke("hello-world")

    let recorded = await capture.authorizationHeaders
    #expect(recorded == ["Bearer first.token", "Bearer second.token"])
  }

  @Test
  func invokeOptionsHeaderOverridesAccessTokenProvider() async throws {
    let box = CapturedRequestBox()
    let sut = makeClient(
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeout: nil)
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }),
      accessToken: { "provider.token" }
    )

    try await sut.invoke(
      "hello-world",
      options: .init(headers: [.authorization: "Bearer override.token"])
    )

    let capturedRequest = await box.request
    #expect(capturedRequest?.headerFields[.authorization] == "Bearer override.token")
  }

  @Test
  func accessTokenProviderErrorPropagatesToInvoke() async throws {
    struct TokenError: Error {}

    let sut = makeClient(
      http: .init(
        transport: ClosureTransport { _, _ in
          Issue.record("transport should not be called when the access token provider throws")
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }),
      accessToken: { throw TokenError() }
    )

    await #expect(throws: TokenError.self) {
      try await sut.invoke("hello-world")
    }
  }

  @Test
  func streamReturnsTheHeadBeforeTheBodyAndYieldsEachChunk() async throws {
    let (chunks, continuation) = AsyncStream<ArraySlice<UInt8>>.makeStream()
    let sut = makeSUT { _, _ in
      (
        HTTPTypes.HTTPResponse(
          status: .ok,
          headerFields: [.contentType: "text/event-stream", .xSbEdgeRegion: "eu-central-2"]),
        HTTPBody(chunks, length: .unknown, iterationBehavior: .single)
      )
    }

    // Nothing has been yielded yet, so the head can only have come back on its own.
    let response = try await sut.stream("stream")
    #expect(response.status == .ok)
    #expect(response.contentType == "text/event-stream")
    #expect(response.region == .euCentral2)

    continuation.yield(ArraySlice("hello ".utf8))
    continuation.yield(ArraySlice("world".utf8))
    continuation.finish()
    var received: [ArraySlice<UInt8>] = []
    for try await chunk in response.body { received.append(chunk) }
    #expect(received.count == 2)
    #expect(Data(received.joined()) == Data("hello world".utf8))
  }

  @Test
  func streamWithNoBodyYieldsAnEmptyBody() async throws {
    let sut = makeSUT { _, _ in (HTTPTypes.HTTPResponse(status: .ok), nil) }

    let response = try await sut.stream("stream")

    #expect(try await Data(collecting: response.body, upTo: 1) == Data())
  }

  /// End to end through `URLSessionTransport`. Mocker hands the whole payload over at once, so
  /// the chunk count is not asserted.
  @Test
  func streamDeliversAMockedEventStreamAsBytes() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("stream"),
      statusCode: 200,
      data: [.post: Data("data: a\n\nevent: delta\ndata: b\n\n".utf8)],
      additionalHeaders: ["Content-Type": "text/event-stream"]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/stream"
      """#
    }
    .register()

    let response = try await sut.stream("stream")

    #expect(response.contentType == "text/event-stream")
    #expect(
      try await Data(collecting: response.body, upTo: 1024)
        == Data("data: a\n\nevent: delta\ndata: b\n\n".utf8))
  }

  @Test
  func streamUsesAccessTokenProvider() async throws {
    let sut = makeSUT(accessToken: { "stream.token" })

    Mock(
      url: url.appendingPathComponent("stream"),
      statusCode: 200,
      data: [.post: Data("hello world".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer stream.token" \
      	--header "X-Client-Info: functions-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/stream"
      """#
    }
    .register()

    let response = try await sut.stream("stream")

    #expect(try await Data(collecting: response.body, upTo: 1024) == Data("hello world".utf8))
  }

  @Test
  func streamDoesNotWrapAccessTokenError() async {
    let sut = makeClient(
      http: .init(
        transport: ClosureTransport { _, _ in
          Issue.record("transport should not be called when the access token provider throws")
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }),
      accessToken: { throw URLError(.userAuthenticationRequired) }
    )

    do {
      _ = try await sut.stream("stream")
      Issue.record("expected the stream to fail")
    } catch let error as URLError {
      #expect(error.code == .userAuthenticationRequired)
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  /// A non-2xx head throws from `stream` itself, carrying the first
  /// `FunctionsAPI.maxErrorBodyBytes` of the body (SDK-1840), so no body is ever exposed.
  @Test
  func stream_serverErrorBody_isCappedKeepingThePrefix() async {
    let sut = makeSUT()
    let cap = FunctionsAPI.maxErrorBodyBytes
    let body = Data((0..<(cap + 4096)).map { UInt8(truncatingIfNeeded: $0) })

    Mock(
      url: url.appendingPathComponent("stream"),
      statusCode: 500,
      data: [.post: body]
    )
    .register()

    do {
      _ = try await sut.stream("stream")
      Issue.record("Expected failure")
    } catch let error as FunctionsError {
      #expect(error.kind == .server)
      #expect(error.response?.statusCode == 500)
      #expect(error.response?.body == body.prefix(cap))
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func streamRelayErrorThrowsRelay() async {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("stream"),
      statusCode: 200,
      data: [.post: Data("relay failed".utf8)],
      additionalHeaders: ["x-relay-error": "true"]
    )
    .register()

    do {
      _ = try await sut.stream("stream")
      Issue.record("Expected failure")
    } catch let error as FunctionsError {
      #expect(error.kind == .relay)
      #expect(error.response?.body == Data("relay failed".utf8))
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  /// The network layer's own failures while the body streams are `.transport`, as on `invoke`.
  @Test
  func streamBodyTransportFailureIsWrapped() async throws {
    let chunks = AsyncThrowingStream<ArraySlice<UInt8>, any Error> {
      $0.yield(ArraySlice("partial".utf8))
      $0.finish(throwing: URLError(.networkConnectionLost))
    }
    let sut = makeSUT { _, _ in
      (
        HTTPTypes.HTTPResponse(status: .ok),
        HTTPBody(chunks, length: .unknown, iterationBehavior: .single)
      )
    }

    let response = try await sut.stream("stream")
    var received = Data()
    do {
      for try await chunk in response.body { received.append(contentsOf: chunk) }
      Issue.record("Expected failure")
    } catch let error as FunctionsError {
      #expect(error.kind == .transport)
      #expect((error.underlyingError as? URLError)?.code == .networkConnectionLost)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
    #expect(received == Data("partial".utf8))
  }

  @Test
  func streamCancellingTheIteratingTaskThrowsCancellationError() async throws {
    let (chunks, continuation) = AsyncStream<ArraySlice<UInt8>>.makeStream()
    let sut = makeSUT { _, _ in
      (
        HTTPTypes.HTTPResponse(status: .ok),
        HTTPBody(chunks, length: .unknown, iterationBehavior: .single)
      )
    }
    let (pulled, onPulled) = AsyncStream<Void>.makeStream()

    let task = Task {
      let response = try await sut.stream("stream")
      for try await _ in response.body { onPulled.yield() }
    }
    continuation.yield(ArraySlice("first".utf8))
    for await _ in pulled { break }
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
