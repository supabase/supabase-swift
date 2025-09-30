import Alamofire
import ConcurrencyExtras
import HTTPTypes
import InlineSnapshotTesting
import Mocker
import SnapshotTestingCustomDump
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

  var region: String?

  lazy var sut = FunctionsClient(
    url: url,
    headers: [
      "apikey": apiKey
    ],
    region: region,
    session: Alamofire.Session(configuration: sessionConfiguration)
  )

  func testInit() async {
    let client = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      region: .saEast1
    )
    XCTAssertEqual(client.region, "sa-east-1")

    XCTAssertEqual(client.headers["apikey"], apiKey)
    XCTAssertNotNil(client.headers["X-Client-Info"])
  }

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
    XCTAssertEqual(response.message, "Hello, world!")
    XCTAssertEqual(response.status, "ok")
  }

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
      XCTFail("Should throw error")
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

    try await sut.invoke("hello-world", options: .init(method: .delete))
  }

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
      	--header "X-Region: ca-central-1" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }
    .register()

    try await sut.invoke("hello-world")
  }

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
      	--header "X-Region: ca-central-1" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:5432/functions/v1/hello-world"
      """#
    }
    .register()

    try await sut.invoke("hello-world", options: .init(region: .caCentral1))
  }

  func testInvokeWithoutRegion() async throws {
    region = nil

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

    try await sut.invoke("hello-world")
  }

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
      XCTFail("Invoke should fail.")
    } catch let FunctionsError.unknown(error) {
      guard case let AFError.sessionTaskFailed(underlyingError as URLError) = error else {
        XCTFail()
        return
      }

      XCTAssertEqual(underlyingError.code, .badServerResponse)
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
    } catch {
      assertInlineSnapshot(of: error, as: .description) {
        """
        httpError(code: 300, data: 0 bytes)
        """
      }
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
    } catch {
      assertInlineSnapshot(of: error, as: .description) {
        """
        relayError
        """
      }
    }
  }

  func test_setAuth() {
    sut.setAuth(token: "access.token")
    XCTAssertEqual(sut.headers["Authorization"], "Bearer access.token")

    sut.setAuth(token: nil)
    XCTAssertNil(sut.headers["Authorization"])
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

    let stream = sut.invokeWithStreamedResponse("stream")

    for try await value in stream {
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

    let stream = sut.invokeWithStreamedResponse("stream")

    do {
      for try await _ in stream {
        XCTFail("should throw error")
      }
    } catch {
      assertInlineSnapshot(of: error, as: .description) {
        """
        httpError(code: 300, data: 0 bytes)
        """
      }
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

    let stream = sut.invokeWithStreamedResponse("stream")

    do {
      for try await _ in stream {
        XCTFail("should throw error")
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
