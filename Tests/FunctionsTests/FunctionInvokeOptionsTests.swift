import XCTest

@testable import Functions

final class FunctionInvokeOptionsTests: XCTestCase {
  func test_initWithStringBody() {
    let options = FunctionInvokeOptions(body: "string value")
    XCTAssertEqual(options.headers[.contentType], "text/plain")
    XCTAssertNotNil(options.body)
  }

  func test_initWithDataBody() {
    let options = FunctionInvokeOptions(body: "binary value".data(using: .utf8)!)
    XCTAssertEqual(options.headers[.contentType], "application/octet-stream")
    XCTAssertNotNil(options.body)
  }

  func test_initWithEncodableBody() {
    struct Body: Encodable {
      let value: String
    }
    let options = FunctionInvokeOptions(body: Body(value: "value"))
    XCTAssertEqual(options.headers[.contentType], "application/json")
    XCTAssertNotNil(options.body)
  }

  func test_initWithCustomContentType() {
    let boundary = "Boundary-\(UUID().uuidString)"
    let contentType = "multipart/form-data; boundary=\(boundary)"
    let options = FunctionInvokeOptions(
      headers: [.contentType: contentType],
      body: Data("binary value".utf8)
    )
    XCTAssertEqual(options.headers[.contentType], contentType)
    XCTAssertNotNil(options.body)
  }
}
