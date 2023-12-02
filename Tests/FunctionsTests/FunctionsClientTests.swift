import ConcurrencyExtras
import XCTest
@_spi(Internal) import _Helpers
@testable import Functions

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class FunctionsClientTests: XCTestCase {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey = "supabase.anon.key"

  lazy var sut = FunctionsClient(url: url, headers: ["apikey": apiKey])

  func testInvoke() async throws {
    let url = URL(string: "http://localhost:5432/functions/v1/hello_world")!
    let _request = ActorIsolated(URLRequest?.none)

    let sut = FunctionsClient(url: self.url, headers: ["apikey": apiKey]) { request in
      await _request.setValue(request)
      return (
        Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
      )
    }

    let body = ["name": "Supabase"]

    try await sut.invoke(
      "hello_world",
      options: .init(headers: ["X-Custom-Key": "value"], body: body)
    )

    let request = await _request.value

    XCTAssertEqual(request?.url, url)
    XCTAssertEqual(request?.httpMethod, "POST")
    XCTAssertEqual(request?.value(forHTTPHeaderField: "apikey"), apiKey)
    XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Custom-Key"), "value")
    XCTAssertEqual(
      request?.value(forHTTPHeaderField: "X-Client-Info"),
      "functions-swift/\(Functions.version)"
    )
  }

  func testInvoke_shouldThrow_URLError_badServerResponse() async {
    let sut = FunctionsClient(url: url, headers: ["apikey": apiKey]) { _ in
      throw URLError(.badServerResponse)
    }

    do {
      try await sut.invoke("hello_world")
    } catch let urlError as URLError {
      XCTAssertEqual(urlError.code, .badServerResponse)
    } catch {
      XCTFail("Unexpected error thrown \(error)")
    }
  }

  func testInvoke_shouldThrow_FunctionsError_httpError() async {
    let url = URL(string: "http://localhost:5432/functions/v1/hello_world")!

    let sut = FunctionsClient(url: self.url, headers: ["apikey": apiKey]) { _ in
      (
        "error".data(using: .utf8)!,
        HTTPURLResponse(url: url, statusCode: 300, httpVersion: nil, headerFields: nil)!
      )
    }

    do {
      try await sut.invoke("hello_world")
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

    let sut = FunctionsClient(url: self.url, headers: ["apikey": apiKey]) { _ in
      (
        Data(),
        HTTPURLResponse(
          url: url, statusCode: 200, httpVersion: nil, headerFields: ["x-relay-error": "true"]
        )!
      )
    }

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
    let headers = await sut.headers
    XCTAssertEqual(headers["Authorization"], "Bearer access.token")
  }
}
