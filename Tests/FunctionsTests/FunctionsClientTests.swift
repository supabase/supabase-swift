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
  var timeoutInterval: TimeInterval?

  func set(_ request: HTTPTypes.HTTPRequest, timeoutInterval: TimeInterval?) {
    self.request = request
    self.timeoutInterval = timeoutInterval
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

  private func makeSUT(
    region: String? = nil,
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) -> FunctionsClient {
    Mocker.removeAll()

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: sessionConfiguration)
    return FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
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
    FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      region: nil,
      http: .init(transport: ClosureTransport(handler: transport)),
      accessToken: nil
    )
  }

  @Test
  func `init`() async {
    let client = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      region: .saEast1
    )
    #expect(client.region == "sa-east-1")

    #expect(client.headers[.init("apikey")!] == apiKey)
    #expect(client.headers[.init("X-Client-Info")!] != nil)
  }

  @Test
  func initWithCustomDecoder() async {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let client = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      decoder: decoder
    )

    #expect(client.decoder === decoder)
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
      options: .init(headers: ["X-Custom-Key": "value"], body: ["name": "Supabase"])
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
    let sut = makeSUT(region: FunctionRegion.caCentral1.rawValue)

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
  func invoke_shouldThrow_URLError_badServerResponse() async {
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
      #expect(error.kind == .http)
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
    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeoutInterval: RequestTimeout.current)
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }))

    try await sut.invoke("hello-world", options: .init(timeoutInterval: 30))

    let capturedTimeout = await box.timeoutInterval
    #expect(capturedTimeout == 30)
  }

  @Test
  func invokeWithDefaultTimeout() async throws {
    let box = CapturedRequestBox()
    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeoutInterval: RequestTimeout.current)
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }))

    try await sut.invoke("hello-world")

    let capturedTimeout = await box.timeoutInterval
    #expect(capturedTimeout == FunctionsClient.requestIdleTimeout)
  }

  @Test
  func accessTokenProviderSetsAuthorizationHeader() async throws {
    let box = CapturedRequestBox()
    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeoutInterval: nil)
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

    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
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
    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      http: .init(
        transport: ClosureTransport { request, _ in
          await box.set(request, timeoutInterval: nil)
          return (HTTPTypes.HTTPResponse(status: .ok), nil)
        }),
      accessToken: { "provider.token" }
    )

    try await sut.invoke(
      "hello-world",
      options: .init(headers: ["Authorization": "Bearer override.token"])
    )

    let capturedRequest = await box.request
    #expect(capturedRequest?.headerFields[.authorization] == "Bearer override.token")
  }

  @Test
  func accessTokenProviderErrorPropagatesToInvoke() async throws {
    struct TokenError: Error {}

    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
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
  func invokeWithStreamedResponseUsesAccessTokenProvider() async throws {
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

    let stream = sut._invokeWithStreamedResponse("stream")

    for try await value in stream {
      #expect(String(decoding: value, as: UTF8.self) == "hello world")
    }
  }

  @Test
  func invokeWithStreamedResponse() async throws {
    // `_invokeWithStreamedResponse` now streams through the client's `transport`, and `makeSUT`
    // wires `MockingURLProtocol` into the session backing it.
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("stream"),
      statusCode: 200,
      data: [.post: Data("hello world".utf8)]
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

    let stream = sut._invokeWithStreamedResponse("stream")

    var chunks: [Data] = []
    for try await value in stream {
      chunks.append(value)
    }

    // Assert on the collected chunks, not inside the loop: a stream that yields nothing would
    // pass an in-loop assertion vacuously. The payload has no newline and is under 16 KiB, so
    // the transport delivers it as one chunk.
    #expect(chunks.count == 1)
    #expect(chunks.reduce(Data(), +) == Data("hello world".utf8))
  }

  @Test
  func invokeWithStreamedResponseHTTPError() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("stream"),
      statusCode: 300,
      data: [.post: Data()]
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

    let stream = sut._invokeWithStreamedResponse("stream")

    do {
      for try await _ in stream {
        Issue.record("should throw error")
      }
    } catch let error as FunctionsError {
      #expect(error.kind == .http)
      #expect(error.response?.statusCode == 300)
    }
  }

  @Test
  func invokeWithStreamedResponseRelayError() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("stream"),
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
      	"http://localhost:5432/functions/v1/stream"
      """#
    }
    .register()

    let stream = sut._invokeWithStreamedResponse("stream")

    do {
      for try await _ in stream {
        Issue.record("should throw error")
      }
    } catch let error as FunctionsError {
      #expect(error.kind == .relay)
    }
  }

  @Test
  func invokeWithStreamedResponseRelayErrorWithNon2xxStatus() async throws {
    let sut = makeSUT()

    Mock(
      url: url.appendingPathComponent("stream"),
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
      	"http://localhost:5432/functions/v1/stream"
      """#
    }
    .register()

    let stream = sut._invokeWithStreamedResponse("stream")

    do {
      for try await _ in stream {
        Issue.record("should throw error")
      }
    } catch let error as FunctionsError {
      #expect(error.kind == .relay)
    }
  }
}
