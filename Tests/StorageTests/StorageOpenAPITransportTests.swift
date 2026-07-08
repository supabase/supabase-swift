import HTTPTypes
import OpenAPIRuntime
import XCTest

@testable import Storage

final class StorageOpenAPITransportTests: XCTestCase {
  func testSendJoinsBaseURLAndPathAndQuery() async throws {
    var capturedRequest: Helpers.HTTPRequest?

    let transport = StorageOpenAPITransport(execute: { request in
      capturedRequest = request
      return Helpers.HTTPResponse(
        data: Data(#"{"ok":true}"#.utf8),
        response: HTTPURLResponse(
          url: URL(string: "http://localhost/storage/v1/bucket")!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    let (response, body) = try await transport.send(
      HTTPTypes.HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/bucket?limit=10"),
      body: nil,
      baseURL: URL(string: "http://localhost/storage/v1")!,
      operationID: "bucketList"
    )

    XCTAssertEqual(
      capturedRequest?.url.absoluteString, "http://localhost/storage/v1/bucket?limit=10")
    XCTAssertEqual(capturedRequest?.method, .get)
    XCTAssertEqual(response.status.code, 200)
    let data = try await Data(collecting: body ?? HTTPBody(""), upTo: .max)
    XCTAssertEqual(data, Data(#"{"ok":true}"#.utf8))
  }

  func testSendPropagatesBodyBytes() async throws {
    var capturedRequest: Helpers.HTTPRequest?

    let transport = StorageOpenAPITransport(execute: { request in
      capturedRequest = request
      return Helpers.HTTPResponse(
        data: Data(),
        response: HTTPURLResponse(
          url: URL(string: "http://localhost/storage/v1/bucket")!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    _ = try await transport.send(
      HTTPTypes.HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/bucket"),
      body: HTTPBody(#"{"name":"avatars"}"#),
      baseURL: URL(string: "http://localhost/storage/v1")!,
      operationID: "bucketCreate"
    )

    XCTAssertEqual(capturedRequest?.body, Data(#"{"name":"avatars"}"#.utf8))
  }

  func testSendDropsAcceptHeader() async throws {
    var capturedRequest: Helpers.HTTPRequest?

    let transport = StorageOpenAPITransport(execute: { request in
      capturedRequest = request
      return Helpers.HTTPResponse(
        data: Data(),
        response: HTTPURLResponse(
          url: URL(string: "http://localhost/storage/v1/bucket")!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    var request = HTTPTypes.HTTPRequest(
      method: .get, scheme: nil, authority: nil, path: "/bucket")
    request.headerFields[.accept] = "application/json"

    _ = try await transport.send(
      request,
      body: nil,
      baseURL: URL(string: "http://localhost/storage/v1")!,
      operationID: "bucketList"
    )

    XCTAssertNil(capturedRequest?.headers[.accept])
  }

  func testSendNormalizesJSONContentTypeCharset() async throws {
    var capturedRequest: Helpers.HTTPRequest?

    let transport = StorageOpenAPITransport(execute: { request in
      capturedRequest = request
      return Helpers.HTTPResponse(
        data: Data(),
        response: HTTPURLResponse(
          url: URL(string: "http://localhost/storage/v1/bucket")!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )!
      )
    })

    var request = HTTPTypes.HTTPRequest(
      method: .post, scheme: nil, authority: nil, path: "/bucket")
    request.headerFields[.contentType] = "application/json; charset=utf-8"

    _ = try await transport.send(
      request,
      body: HTTPBody(#"{"name":"avatars"}"#),
      baseURL: URL(string: "http://localhost/storage/v1")!,
      operationID: "bucketCreate"
    )

    XCTAssertEqual(capturedRequest?.headers[.contentType], "application/json")
  }
}
