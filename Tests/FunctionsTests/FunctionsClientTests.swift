import Alamofire
import ConcurrencyExtras
import Foundation
import InlineSnapshotTesting
import Mocker
import SnapshotTestingCustomDump
import TestHelpers
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite struct FunctionsClientTests {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

  let sessionConfiguration: URLSessionConfiguration = {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    return sessionConfiguration
  }()

  private var _region: FunctionRegion? = nil
  
  var region: FunctionRegion? {
    get { _region }
    set { _region = newValue }
  }

  var sut: FunctionsClient {
    FunctionsClient(
      url: url,
      headers: HTTPHeaders(["apikey": apiKey]),
      region: _region,
      session: Alamofire.Session(configuration: sessionConfiguration)
    )
  }

  @Test("Initialize FunctionsClient with correct properties")
  func testInit() async {
    let client = FunctionsClient(
      url: url,
      headers: HTTPHeaders(["apikey": apiKey]),
      region: .usEast1
    )
    #expect(await client.region?.rawValue == "us-east-1")

    #expect(await client.headers["apikey"] == apiKey)
    #expect(await client.headers["X-Client-Info"] != nil)
  }

  @Test("Invoke function with custom body and headers")
  func testInvoke() async throws {
    Mock(
      url: self.url.appendingPathComponent("hello_world"),
      statusCode: 200,
      data: [
        .post: #"{"message":"Hello, world!","status":"ok"}"#.data(using: .utf8)!
      ]
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

    let bodyData = try! JSONEncoder().encode(["name": "Supabase"])
    try await sut.invoke("hello_world") { options in
      options.setBody(bodyData)
      options.headers["X-Custom-Key"] = "value"
    }
  }

  @Test("Invoke function returning decodable response")
  func testInvokeReturningDecodable() async throws {
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

  @Test("Invoke function with custom decoding closure")
  func testInvokeWithCustomDecodingClosure() async throws {
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

    let response = try await sut.invoke("hello") { data, _ in
      try JSONDecoder().decode(Payload.self, from: data)
    }
    #expect(response.message == "Hello, world!")
    #expect(response.status == "ok")
  }

  @Test("Invoke function with decoding error")
  func testInvokeDecodingThrowsError() async throws {
    Mock(
      url: url.appendingPathComponent("hello"),
      statusCode: 200,
      data: [
        .post: #"{"message":"invalid"}"#.data(using: .utf8)!
      ]
    )
    .register()

    struct Payload: Decodable {
      var message: String
      var status: String
    }

    do {
      _ = try await sut.invoke("hello") as Payload
      Issue.record("Should throw error")
    } catch {
      assertInlineSnapshot(of: error, as: .customDump) {
        """
        FunctionsError.unknown(
          .keyNotFound(
            .CodingKeys(stringValue: "status", intValue: nil),
            DecodingError.Context(
              codingPath: [],
              debugDescription: #"No value associated with key CodingKeys(stringValue: "status", intValue: nil) ("status")."#,
              underlyingError: nil
            )
          )
        )
        """
      }
    }
  }

  @Test("Invoke function with custom HTTP method")
  func testInvokeWithCustomMethod() async throws {
    Mock(
      url: url.appendingPathComponent("hello-world"),
      statusCode: 204,
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

    try await sut.invoke("hello-world") { options in
      options.method = .delete
    }
  }

  @Test("Invoke function with query parameters")
  func testInvokeWithQuery() async throws {
    Mock(
      url: url.appendingPathComponent("hello-world"),
      ignoreQuery: true,
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
      	"http://localhost:5432/functions/v1/hello-world?key=value"
      """#
    }
    .register()

    try await sut.invoke("hello-world") { options in
      options.query = [URLQueryItem(name: "key", value: "value")]
    }
  }

  @Test("Invoke function with region defined in client")
  func testInvokeWithRegionDefinedInClient() async throws {
    let clientWithRegion = FunctionsClient(
      url: url,
      headers: HTTPHeaders(["apikey": apiKey]),
      region: .usEast1,
      session: Alamofire.Session(configuration: sessionConfiguration)
    )

    Mock(
      url: url.appendingPathComponent("hello-world"),
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
      	--header "X-Region: us-east-1" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }
    .register()

    try await clientWithRegion.invoke("hello-world")
  }

  @Test("Invoke function with region in options")
  func testInvokeWithRegion() async throws {
    Mock(
      url: url.appendingPathComponent("hello-world"),
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
      	--header "X-Region: us-east-1" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }
    .register()

    try await sut.invoke("hello-world") { options in
      options.region = .usEast1
    }
  }

  @Test("Invoke function with region using string literal")
  func testInvokeWithRegion_usingExpressibleByLiteral() async throws {
    Mock(
      url: url.appendingPathComponent("hello-world"),
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
      	--header "X-Region: ca-central-1" \
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }
    .register()

    try await sut.invoke("hello-world") { options in
      options.region = "ca-central-1"
    }
  }

  @Test("Invoke function without region")
  func testInvokeWithoutRegion() async throws {
    let clientWithoutRegion = FunctionsClient(
      url: url,
      headers: HTTPHeaders(["apikey": apiKey]),
      region: nil,
      session: Alamofire.Session(configuration: sessionConfiguration)
    )

    Mock(
      url: url.appendingPathComponent("hello-world"),
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
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }
    .register()

    try await clientWithoutRegion.invoke("hello-world")
  }

  @Test("Invoke function should throw error on request failure")
  func testInvoke_shouldThrow_error() async throws {
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
      Issue.record("Should throw error")
    } catch let FunctionsError.unknown(underlyingError) {
      guard case let AFError.sessionTaskFailed(urleError as URLError) = underlyingError else {
        Issue.record("Expected AFError.sessionTaskFailed with URLError")
        return
      }

      #expect(urleError.code == .badServerResponse)
    } catch {
      Issue.record("Expected FunctionsError.unknown, got \(error)")
    }
  }

  @Test("Invoke function should throw HTTP error")
  func testInvoke_shouldThrow_FunctionsError_httpError() async {
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
      Issue.record("Should throw error")
    } catch {
      assertInlineSnapshot(of: error, as: .description) {
        """
        httpError(code: 300, data: 0 bytes)
        """
      }
    }
  }

  @Test("Invoke function should throw relay error")
  func testInvoke_shouldThrow_FunctionsError_relayError() async {
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
      Issue.record("Should throw error")
    } catch {
      assertInlineSnapshot(of: error, as: .description) {
        """
        relayError
        """
      }
    }
  }

  @Test("Set and clear authentication token")
  func test_setAuth() async {
    await sut.setAuth(token: "access.token")
    #expect(await sut.headers["Authorization"] == "Bearer access.token")

    await sut.setAuth(token: nil)
    #expect(await sut.headers["Authorization"] == nil)
  }

  @Test("Invoke function with streamed response")
  func testInvokeWithStreamedResponse() async throws {
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

    let stream = await sut.invokeWithStreamedResponse("stream")

    for try await value in stream {
      #expect(String(decoding: value, as: UTF8.self) == "hello world")
    }
  }

  @Test("Invoke function with streamed response HTTP error")
  func testInvokeWithStreamedResponseHTTPError() async throws {
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

    let stream = await sut.invokeWithStreamedResponse("stream")

    do {
      for try await _ in stream {
        Issue.record("Should not receive data")
      }
    } catch {
      assertInlineSnapshot(of: error, as: .description) {
        """
        httpError(code: 300, data: 0 bytes)
        """
      }
    }
  }

  @Test("Invoke function with streamed response relay error")
  func testInvokeWithStreamedResponseRelayError() async throws {
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

    let stream = await sut.invokeWithStreamedResponse("stream")

    do {
      for try await _ in stream {
        Issue.record("Should not receive data")
      }
    } catch {
      assertInlineSnapshot(of: error, as: .description) {
        """
        relayError
        """
      }
    }
  }
}
