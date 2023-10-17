import Mocker
import XCTest

@testable import Functions

final class FunctionsClientTests: XCTestCase {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey = "supabase.anon.key"

  lazy var sut = FunctionsClient(url: url, headers: ["apikey": apiKey])

  func testInvoke() async throws {
    let url = URL(string: "http://localhost:5432/functions/v1/hello_world")!
    var _request: URLRequest?

    var mock = Mock(url: url, dataType: .json, statusCode: 200, data: [.post: Data()])
    mock.onRequestHandler = .init { _request = $0 }
    mock.register()

    let body = ["name": "Supabase"]

    try await sut.invoke(
      functionName: "hello_world",
      invokeOptions: .init(headers: ["X-Custom-Key": "value"], body: body)
    )

    let request = try XCTUnwrap(_request)

    XCTAssertEqual(request.url, url)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), apiKey)
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom-Key"), "value")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "X-Client-Info"),
      "functions-swift/\(Functions.version)"
    )
  }

  func testInvoke_shouldThrow_URLError_badServerResponse() async {
    let url = URL(string: "http://localhost:5432/functions/v1/hello_world")!
    let mock = Mock(
      url: url, dataType: .json, statusCode: 200, data: [.post: Data()],
      requestError: URLError(.badServerResponse))
    mock.register()

    do {
      try await sut.invoke(functionName: "hello_world")
    } catch let urlError as URLError {
      XCTAssertEqual(urlError.code, .badServerResponse)
    } catch {
      XCTFail("Unexpected error thrown \(error)")
    }
  }

  func testInvoke_shouldThrow_FunctionsError_httpError() async {
    let url = URL(string: "http://localhost:5432/functions/v1/hello_world")!
    let mock = Mock(
      url: url, dataType: .json, statusCode: 300, data: [.post: "error".data(using: .utf8)!])
    mock.register()

    do {
      try await sut.invoke(functionName: "hello_world")
      XCTFail("Invoke should fail.")
    } catch let FunctionsError.httpError(code, data) {
      XCTAssertEqual(code, 300)
      XCTAssertEqual(data, "error".data(using: .utf8))
    } catch {
      XCTFail("Unexpected error thrown \(error)")
    }
  }

  func testInvoke_shouldThrow_FunctionsError_relayError() async {
    let url = URL(string: "http://localhost:5432/functions/v1/hello_world")!
    let mock = Mock(
      url: url, dataType: .json, statusCode: 200, data: [.post: Data()],
      additionalHeaders: ["x-relay-error": "true"])
    mock.register()

    do {
      try await sut.invoke(functionName: "hello_world")
      XCTFail("Invoke should fail.")
    } catch FunctionsError.relayError {
    } catch {
      XCTFail("Unexpected error thrown \(error)")
    }
  }

  func test_setAuth() async {
    await sut.setAuth(token: "access.token")
    let headers = await sut.headers
    XCTAssertEqual(headers["Authorization"], "Bearer access.token")
  }
}
