import Foundation
import HTTPTypes
import Mocker
import TestHelpers
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Captures the last `URLRequest` seen by a custom fetch handler, for tests that need to inspect
/// properties (like `timeoutInterval`) not surfaced by Mocker's `snapshotRequest` curl output.
private actor CapturedRequestBox {
  var request: URLRequest?

  func set(_ request: URLRequest) {
    self.request = request
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

  private func makeSUT(region: String? = nil) -> FunctionsClient {
    Mocker.removeAll()

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    let session = URLSession(configuration: sessionConfiguration)
    return FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      region: region,
      fetch: { try await session.data(for: $0) },
      sessionConfiguration: sessionConfiguration
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
    } catch let urlError as URLError {
      #expect(urlError.code == .badServerResponse)
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
    } catch let FunctionsError.httpError(code, _) {
      #expect(code == 300)
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
    } catch FunctionsError.relayError {
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
    } catch FunctionsError.relayError {
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
      fetch: { request in
        await box.set(request)
        return (
          Data(),
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      }
    )

    try await sut.invoke("hello-world", options: .init(timeoutInterval: 30))

    let capturedRequest = await box.request
    #expect(capturedRequest?.timeoutInterval == 30)
  }

  @Test
  func invokeWithDefaultTimeout() async throws {
    let box = CapturedRequestBox()
    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      fetch: { request in
        await box.set(request)
        return (
          Data(),
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      }
    )

    try await sut.invoke("hello-world")

    let capturedRequest = await box.request
    #expect(capturedRequest?.timeoutInterval == FunctionsClient.requestIdleTimeout)
  }

  @Test
  func setAuth() {
    let sut = makeSUT()

    sut.setAuth(token: "access.token")
    #expect(sut.headers[.authorization] == "Bearer access.token")

    sut.setAuth(token: nil)
    #expect(sut.headers[.authorization] == nil)
  }

  @Test
  func invokeWithStreamedResponse() async throws {
    // `_invokeWithStreamedResponse` opens its own URLSession from the client's
    // `sessionConfiguration`, and `makeSUT` wires `MockingURLProtocol` into it.
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

    for try await value in stream {
      #expect(String(decoding: value, as: UTF8.self) == "hello world")
    }
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
    } catch let FunctionsError.httpError(code, _) {
      #expect(code == 300)
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
    } catch FunctionsError.relayError {
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
    } catch FunctionsError.relayError {
    }
  }
}
