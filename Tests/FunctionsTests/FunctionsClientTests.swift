import _Helpers
import ConcurrencyExtras
@testable import Functions
import TestHelpers
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class FunctionsClientTests: XCTestCase {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey = "supabase.anon.key"

  lazy var sut = FunctionsClient(url: url, headers: ["Apikey": apiKey])

  func testInit() async {
    let client = FunctionsClient(
      url: url,
      headers: ["Apikey": apiKey],
      region: .saEast1
    )
    XCTAssertEqual(client.region, "sa-east-1")

    XCTAssertEqual(client.headers["Apikey"], apiKey)
    XCTAssertNotNil(client.headers["X-Client-Info"])
  }

  func testInvoke() async throws {
    let url = URL(string: "http://localhost:5432/functions/v1/hello_world")!

    let http = HTTPClientMock()
      .when {
        $0.url.pathComponents.contains("hello_world")
      } return: { _ in
        try .stub(body: Empty())
      }
    let sut = FunctionsClient(
      url: self.url,
      headers: ["Apikey": apiKey],
      region: nil,
      http: http
    )

    let body = ["name": "Supabase"]

    try await sut.invoke(
      "hello_world",
      options: .init(headers: ["X-Custom-Key": "value"], body: body)
    )

    let request = http.receivedRequests.last

    XCTAssertEqual(request?.url, url)
    XCTAssertEqual(request?.method, .post)
    XCTAssertEqual(request?.headers["Apikey"], apiKey)
    XCTAssertEqual(request?.headers["X-Custom-Key"], "value")
    XCTAssertEqual(request?.headers["X-Client-Info"], "functions-swift/\(Functions.version)")
  }

  func testInvokeWithCustomMethod() async throws {
    let http = HTTPClientMock().any { _ in try .stub(body: Empty()) }

    let sut = FunctionsClient(
      url: self.url,
      headers: ["Apikey": apiKey],
      region: nil,
      http: http
    )

    try await sut.invoke("hello-world", options: .init(method: .delete))

    let request = http.receivedRequests.last
    XCTAssertEqual(request?.method, .delete)
  }

  func testInvokeWithRegionDefinedInClient() async throws {
    let http = HTTPClientMock()
      .any { _ in try .stub(body: Empty()) }

    let sut = FunctionsClient(
      url: url,
      headers: [:],
      region: FunctionRegion.caCentral1.rawValue,
      http: http
    )

    try await sut.invoke("hello-world")

    XCTAssertEqual(http.receivedRequests.last?.headers["x-region"], "ca-central-1")
  }

  func testInvokeWithRegion() async throws {
    let http = HTTPClientMock()
      .any { _ in try .stub(body: Empty()) }

    let sut = FunctionsClient(
      url: url,
      headers: [:],
      region: nil,
      http: http
    )

    try await sut.invoke("hello-world", options: .init(region: .caCentral1))

    XCTAssertEqual(http.receivedRequests.last?.headers["x-region"], "ca-central-1")
  }

  func testInvokeWithoutRegion() async throws {
    let http = HTTPClientMock()
      .any { _ in try .stub(body: Empty()) }

    let sut = FunctionsClient(
      url: url,
      headers: [:],
      region: nil,
      http: http
    )

    try await sut.invoke("hello-world")

    XCTAssertNil(http.receivedRequests.last?.headers["x-region"])
  }

  func testInvoke_shouldThrow_URLError_badServerResponse() async {
    let sut = FunctionsClient(
      url: url,
      headers: ["Apikey": apiKey],
      region: nil,
      http: HTTPClientMock()
        .any { _ in throw URLError(.badServerResponse) }
    )

    do {
      try await sut.invoke("hello_world")
    } catch let urlError as URLError {
      XCTAssertEqual(urlError.code, .badServerResponse)
    } catch {
      XCTFail("Unexpected error thrown \(error)")
    }
  }

  func testInvoke_shouldThrow_FunctionsError_httpError() async {
    let sut = FunctionsClient(
      url: url,
      headers: ["Apikey": apiKey],
      region: nil,
      http: HTTPClientMock()
        .any { _ in try .stub(body: Empty(), statusCode: 300) }
    )
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
    let url = URL(string: "http://localhost:5432/functions/v1/hello_world")!

    let sut = FunctionsClient(
      url: self.url,
      headers: ["Apikey": apiKey],
      region: nil,
      http: HTTPClientMock().any { _ in
        try .stub(
          body: Empty(),
          headers: ["x-relay-error": "true"]
        )
      }
    )

    do {
      try await sut.invoke("hello_world")
      XCTFail("Invoke should fail.")
    } catch FunctionsError.relayError {
    } catch {
      XCTFail("Unexpected error thrown \(error)")
    }
  }

  func test_setAuth() {
    sut.setAuth(token: "access.token")
    XCTAssertEqual(sut.headers["Authorization"], "Bearer access.token")
  }
}

extension HTTPResponse {
  static func stub(
    body: any Encodable,
    statusCode: Int = 200,
    headers: HTTPHeaders = .init()
  ) throws -> HTTPResponse {
    let data = try JSONEncoder().encode(body)
    let response = HTTPURLResponse(
      url: URL(string: "http://127.0.0.1")!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: headers.dictionary
    )!
    return HTTPResponse(
      data: data,
      response: response
    )
  }
}

struct Empty: Codable {}
