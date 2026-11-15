import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private actor CapturedRequestBox {
  var request: HTTPTypes.HTTPRequest?
  var timeout: Duration?

  func set(_ request: HTTPTypes.HTTPRequest, timeout: Duration?) {
    self.request = request
    self.timeout = timeout
  }
}

@Suite
struct FunctionsClientTests {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
  let transport = RecordingTransport()

  private var headers: HTTPFields { [.apikey: apiKey] }

  private func makeSUT(
    region: FunctionRegion? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) throws -> FunctionsClient {
    try makeClient(region: region, http: .init(transport: transport), accessToken: accessToken)
  }

  private func makeSUT(
    transport:
      @escaping @Sendable (HTTPTypes.HTTPRequest, HTTPBody?) async throws -> (
        HTTPTypes.HTTPResponse, HTTPBody?
      )
  ) throws -> FunctionsClient {
    try makeClient(http: .init(transport: ClosureTransport(handler: transport)))
  }

  private func makeClient(
    region: FunctionRegion? = nil,
    http: HTTPClientConfiguration,
    decoder: JSONDecoder = .supabase(),
    headers extraHeaders: HTTPFields = [:],
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) throws -> FunctionsClient {
    var http = http
    if let accessToken {
      http.middlewares.append(AccessTokenMiddleware(getAccessToken: accessToken))
    }
    return try FunctionsClient(
      configuration: .init(
        url: url, headers: headers.merging(with: extraHeaders), region: region, http: http,
        decoder: decoder))
  }

  @Test
  func `init`() async throws {
    let client = try FunctionsClient(
      configuration: .init(url: url, headers: headers, region: .saEast1))

    #expect(client.configuration.region == .saEast1)
    #expect(client.configuration.headers[.apikey] == apiKey)
    #expect(client.configuration.url == url)
  }

  @Test(arguments: [
    "project-ref", "https:///v1", "//project-ref.supabase.co/v1", "mailto:someone@example.com",
  ])
  func initThrowsWhenTheURLHasNoSchemeOrHost(url: String) throws {
    let url = try #require(URL(string: url))
    let error = #expect(throws: FunctionsError.self) {
      try FunctionsClient(configuration: .init(url: url))
    }
    #expect(error?.kind == .invalidConfiguration)
  }

  @Test
  func initWithCustomDecoder() async throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let client = try FunctionsClient(
      configuration: .init(url: url, headers: headers, decoder: decoder))

    #expect(client.configuration.decoder === decoder)
  }

  @Test
  func invokeReturnsTheResponseHead() async throws {
    let sut = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("hello"),
      data: Data("hi".utf8),
      headers: [
        .contentType: "text/plain",
        .xSbEdgeRegion: "eu-central-2",
        .xDenoExecutionID: "exec-1",
      ]
    )

    let response = try await sut.invoke("hello")

    #expect(response.status == .ok)
    #expect(response.contentType == "text/plain")
    #expect(response.region == .euCentral2)
    #expect(response.executionID == "exec-1")
    #expect(response.text == "hi")
  }

  @Test
  func invokeDecodesISO8601DatesByDefault() async throws {
    let sut = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("hello"),
      data: Data(#"{"at":"2026-10-05T12:34:56.789Z"}"#.utf8)
    )

    struct Payload: Decodable {
      var at: Date
    }

    let payload: Payload = try await sut.invoke("hello")
    #expect(payload.at == Date(timeIntervalSince1970: 1_791_203_696.789))
  }

  @Test
  func perCallDecoderWinsOverTheClientDecoder() async throws {
    let sut = try makeSUT()

    transport.stub(
      .post, url.appendingPathComponent("hello"), data: Data(#"{"user_name":"a"}"#.utf8))

    struct Payload: Decodable {
      var userName: String
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let payload = try await sut.invoke("hello", as: Payload.self, decoder: decoder)
    #expect(payload.userName == "a")
  }

  @Test
  func invokeWithABodyThatFailsToEncodeSendsNothing() async throws {
    struct Failing: Encodable {
      struct Reason: Error {}
      func encode(to encoder: any Encoder) throws { throw Reason() }
    }
    let sut = try makeSUT { _, _ in
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
    let sut = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("hello_world")) {
      #"""
      curl \
      	--request POST \
      	--header "Content-Length: 19" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "X-Custom-Key: value" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--data "{\"name\":\"Supabase\"}" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }

    try await sut.invoke(
      "hello_world",
      body: .json(["name": "Supabase"]),
      options: .init(headers: [.init("X-Custom-Key")!: "value"])
    )
  }

  @Test
  func invokeReturningDecodable() async throws {
    let sut = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("hello"),
      data: #"{"message":"Hello, world!","status":"ok"}"#.data(using: .utf8)!
    ) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello"
      """#
    }

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
    let sut = try makeSUT()

    transport.stub(.delete, url.appendingPathComponent("hello-world")) {
      #"""
      curl \
      	--request DELETE \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }

    try await sut.invoke("hello-world", options: .init(method: .delete))
  }

  @Test
  func invokeWithQuery() async throws {
    let sut = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("hello-world")) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world?key=value"
      """#
    }

    try await sut.invoke(
      "hello-world",
      options: .init(
        query: [URLQueryItem(name: "key", value: "value")]
      )
    )
  }

  @Test
  func invokeWithRegionDefinedInClient() async throws {
    let sut = try makeSUT(region: .caCentral1)

    transport.stub(.post, url.appendingPathComponent("hello-world")) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-region: ca-central-1" \
      	"http://localhost:5432/functions/v1/hello-world?forceFunctionRegion=ca-central-1"
      """#
    }

    try await sut.invoke("hello-world")
  }

  @Test
  func invokeWithRegion() async throws {
    let sut = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("hello-world")) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	--header "x-region: ca-central-1" \
      	"http://localhost:5432/functions/v1/hello-world?forceFunctionRegion=ca-central-1"
      """#
    }

    try await sut.invoke("hello-world", options: .init(region: .caCentral1))
  }

  @Test
  func invokeWithoutRegion() async throws {
    let sut = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("hello-world")) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }

    try await sut.invoke("hello-world")
  }

  @Test
  func invoke_badServerResponse_wrapsAsTransport() async throws {
    let sut = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("hello_world")) { _, _ in
      throw URLError(.badServerResponse)
    }

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .transport)
      #expect((error.underlyingError as? URLError)?.code == .badServerResponse)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }

    try transport.assertFirstRequestSnapshot(.post, url.appendingPathComponent("hello_world")) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }
  }

  @Test
  func invoke_shouldThrow_FunctionsError_httpError() async throws {
    let sut = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("hello_world"), status: .multipleChoices) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let error as FunctionsError {
      #expect(error.kind == .server)
      #expect(error.response?.status == 300)
      #expect(error.response?.body == Data())
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func invoke_shouldThrow_FunctionsError_relayError() async throws {
    let sut = try makeSUT()

    transport.stub(
      .post, url.appendingPathComponent("hello_world"), headers: [.xRelayError: "true"]
    ) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }

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
  func invoke_relayErrorWithNon2xxStatus_shouldThrowRelayError() async throws {
    let sut = try makeSUT()

    transport.stub(
      .post, url.appendingPathComponent("hello_world"), status: .internalServerError,
      headers: [.xRelayError: "true"]
    ) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello_world"
      """#
    }

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
  func invoke_transportFailure_wrapsURLError() async throws {
    let sut = try makeSUT { _, _ in throw URLError(.notConnectedToInternet) }

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
  func invoke_cancellation_isNotWrapped() async throws {
    let sut = try makeSUT { _, _ in throw CancellationError() }

    await #expect(throws: CancellationError.self) {
      try await sut.invoke("hello_world")
    }
  }

  @Test
  func invoke_cancelledURLErrorWithoutTaskCancellation_isWrapped() async throws {
    let sut = try makeSUT { _, _ in throw URLError(.cancelled) }

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

  @Test
  func invoke_cancellingTheTask_throwsCancellationError() async throws {
    let sut = try makeSUT()
    let inFlight = Gate()

    // URLSession fails a cancelled task with `URLError(.cancelled)`, not `CancellationError`.
    transport.stub(.post, url.appendingPathComponent("hello_world")) { _, _ in
      await inFlight.pass()
      throw URLError(.cancelled)
    }

    let task = Task { try await sut.invoke("hello_world") }
    await inFlight.arrivals(1)
    task.cancel()

    do {
      try await task.value
      Issue.record("Expected failure")
    } catch is CancellationError {
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test
  func invoke_serverErrorBody_isCappedKeepingThePrefix() async throws {
    let sut = try makeSUT()
    let cap = HTTPClient.maxErrorBodyBytes
    let body = Data((0..<(cap + 4096)).map { UInt8(truncatingIfNeeded: $0) })

    transport.stub(
      .post, url.appendingPathComponent("hello_world"), status: .internalServerError, data: body)

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
  func invoke_customFetchError_isNotWrapped() async throws {
    struct FetchError: Error {}
    let sut = try makeSUT { _, _ in throw FetchError() }

    await #expect(throws: FetchError.self) {
      try await sut.invoke("hello_world")
    }
  }

  @Test
  func invoke_undecodableBody_wrapsDecodingError() async throws {
    let sut = try makeSUT()

    transport.stub(.post, url.appendingPathComponent("hello_world"), data: Data("not json".utf8))

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
    let sut = try makeClient(
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
    let sut = try makeClient(
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
    let sut = try makeClient(
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
    let sut = try makeClient(
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

    let sut = try makeClient(
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
    let sut = try makeClient(
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
  func staticAuthorizationHeaderWinsOverTheAccessTokenMiddleware() async throws {
    let box = CapturedRequestBox()
    let sut = try makeClient(
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeout: nil)
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }),
      headers: [.authorization: "Bearer static"],
      accessToken: { "provider.token" }
    )

    try await sut.invoke("hello-world")

    let capturedRequest = await box.request
    #expect(capturedRequest?.headerFields[.authorization] == "Bearer static")
  }

  @Test
  func accessTokenProviderErrorFailsInvokeAsAFunctionsError() async throws {
    struct TokenError: Error {}

    let sut = try makeClient(
      http: .init(
        transport: ClosureTransport { _, _ in
          Issue.record("transport should not be called when the access token provider throws")
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }),
      accessToken: { throw TokenError() }
    )

    let error = await #expect(throws: FunctionsError.self) {
      try await sut.invoke("hello-world")
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is TokenError)
  }

  @Test
  func streamReturnsTheHeadBeforeTheBodyAndYieldsEachChunk() async throws {
    let (chunks, continuation) = AsyncStream<ArraySlice<UInt8>>.makeStream()
    let sut = try makeSUT { _, _ in
      (
        HTTPTypes.HTTPResponse(
          status: .ok,
          headerFields: [.contentType: "text/event-stream", .xSbEdgeRegion: "eu-central-2"]),
        HTTPBody(chunks, length: .unknown, iterationBehavior: .single)
      )
    }

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
    let sut = try makeSUT { _, _ in (HTTPTypes.HTTPResponse(status: .ok), nil) }

    let response = try await sut.stream("stream")

    #expect(try await Data(collecting: response.body, upTo: 1) == Data())
  }

  @Test
  func streamDeliversAMockedEventStreamAsBytes() async throws {
    let sut = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("stream"),
      data: Data("data: a\n\nevent: delta\ndata: b\n\n".utf8),
      headers: [.contentType: "text/event-stream"]
    ) {
      #"""
      curl \
      	--request POST \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/stream"
      """#
    }

    let response = try await sut.stream("stream")

    #expect(response.contentType == "text/event-stream")
    #expect(
      try await Data(collecting: response.body, upTo: 1024)
        == Data("data: a\n\nevent: delta\ndata: b\n\n".utf8))
  }

  @Test
  func streamUsesAccessTokenProvider() async throws {
    let sut = try makeSUT(accessToken: { "stream.token" })

    transport.stub(.post, url.appendingPathComponent("stream"), data: Data("hello world".utf8)) {
      #"""
      curl \
      	--request POST \
      	--header "Authorization: Bearer stream.token" \
      	--header "X-Client-Info: functions-swift/0.0.0; platform=macOS; platform-version=0.0.0; runtime=swift; runtime-version=0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/stream"
      """#
    }

    let response = try await sut.stream("stream")

    #expect(try await Data(collecting: response.body, upTo: 1024) == Data("hello world".utf8))
  }

  @Test
  func accessTokenProviderErrorFailsStreamAsAFunctionsError() async throws {
    struct TokenError: Error {}
    let sut = try makeClient(
      http: .init(
        transport: ClosureTransport { _, _ in
          Issue.record("transport should not be called when the access token provider throws")
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }),
      accessToken: { throw TokenError() }
    )

    let error = await #expect(throws: FunctionsError.self) {
      try await sut.stream("stream")
    }
    #expect(error?.kind == .accessToken)
    #expect(error?.underlyingError is TokenError)
  }

  @Test
  func stream_serverErrorBody_isCappedKeepingThePrefix() async throws {
    let sut = try makeSUT()
    let cap = HTTPClient.maxErrorBodyBytes
    let body = Data((0..<(cap + 4096)).map { UInt8(truncatingIfNeeded: $0) })

    transport.stub(
      .post, url.appendingPathComponent("stream"), status: .internalServerError, data: body)

    do {
      _ = try await sut.stream("stream")
      Issue.record("Expected failure")
    } catch let error as FunctionsError {
      #expect(error.kind == .server)
      #expect(error.response?.status == 500)
      #expect(error.response?.body == body.prefix(cap))
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func streamRelayErrorThrowsRelay() async throws {
    let sut = try makeSUT()

    transport.stub(
      .post,
      url.appendingPathComponent("stream"),
      data: Data("relay failed".utf8),
      headers: [.xRelayError: "true"]
    )

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

  @Test
  func streamBodyTransportFailureIsWrapped() async throws {
    let chunks = AsyncThrowingStream<ArraySlice<UInt8>, any Error> {
      $0.yield(ArraySlice("partial".utf8))
      $0.finish(throwing: URLError(.networkConnectionLost))
    }
    let sut = try makeSUT { _, _ in
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
    let sut = try makeSUT { _, _ in
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
