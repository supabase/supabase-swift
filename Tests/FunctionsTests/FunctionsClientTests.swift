import ConcurrencyExtras
import HTTPTypes
import InlineSnapshotTesting
import Mocker
import TestHelpers
import XCTest

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class FunctionsClientTests: XCTestCase {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

  let sessionConfiguration: URLSessionConfiguration = {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
    return sessionConfiguration
  }()

  lazy var session = URLSession(configuration: sessionConfiguration)

  var region: String?

  lazy var sut = FunctionsClient(
    url: url,
    headers: [
      "apikey": apiKey
    ],
    region: region.flatMap(FunctionRegion.init(rawValue:)),
    fetch: { [session] request in
      try await session.data(for: request)
    },
    sessionConfiguration: sessionConfiguration
  )

  override func setUp() {
    super.setUp()
    //    isRecording = true
  }

  func testInit() async {
    let client = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      region: .saEast1
    )

    let region = await client.region
    XCTAssertEqual(region?.rawValue, "sa-east-1")

    let headers = await client.headers
    XCTAssertEqual(headers[.init("apikey")!], apiKey)
    XCTAssertNotNil(headers[.init("X-Client-Info")!])
  }

  func testInvoke() async throws {
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
    XCTAssertEqual(response.message, "Hello, world!")
    XCTAssertEqual(response.status, "ok")
  }

  func testInvokeWithCustomMethod() async throws {
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

  func testInvokeWithQuery() async throws {
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

  func testInvokeWithRegionDefinedInClient() async throws {
    region = FunctionRegion.caCentral1.rawValue

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

  func testInvokeWithRegion() async throws {
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

  func testInvokeWithRegion_usingExpressibleByLiteral() async throws {
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

    try await sut.invoke("hello-world", options: .init(region: "ca-central-1"))
  }

  func testInvokeWithoutRegion() async throws {
    region = nil

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

  func testInvoke_shouldThrow_URLError_badServerResponse() async {
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
      XCTFail("Invoke should fail.")
    } catch let urlError as URLError {
      XCTAssertEqual(urlError.code, .badServerResponse)
    } catch {
      XCTFail("Unexpected error thrown \(error)")
    }
  }

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
      XCTFail("Invoke should fail.")
    } catch let FunctionsError.httpError(code, _) {
      XCTAssertEqual(code, 300)
    } catch {
      XCTFail("Unexpected error thrown \(error)")
    }
  }

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
      XCTFail("Invoke should fail.")
    } catch FunctionsError.relayError {
    } catch {
      XCTFail("Unexpected error thrown \(error)")
    }
  }

  func test_setAuth() async {
    await sut.setAuth(token: "access.token")

    var headers = await sut.headers
    XCTAssertEqual(headers[.authorization], "Bearer access.token")

    await sut.setAuth(token: nil)
    headers = await sut.headers
    XCTAssertNil(headers[.authorization])
  }

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

    for try await value in await sut._invokeWithStreamedResponse("stream") {
      XCTAssertEqual(String(decoding: value, as: UTF8.self), "hello world")
    }
  }

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

    do {
      for try await _ in await sut._invokeWithStreamedResponse("stream") {
        XCTFail("should throw error")
      }
    } catch let FunctionsError.httpError(code, _) {
      XCTAssertEqual(code, 300)
    }
  }

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

    do {
      for try await _ in await sut._invokeWithStreamedResponse("stream") {
        XCTFail("should throw error")
      }
    } catch FunctionsError.relayError {
    }
  }
}
