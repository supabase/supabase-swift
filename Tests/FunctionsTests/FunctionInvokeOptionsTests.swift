import Alamofire
import XCTest

@testable import Functions

final class FunctionInvokeOptionsTests: XCTestCase {
  func test_initWithStringBody() {
    let bodyData = "string value".data(using: .utf8)!
    let options = FunctionInvokeOptions(body: bodyData)
    XCTAssertEqual(options.headers.first { $0.name == "Content-Type" }?.value, "text/plain")
    XCTAssertNotNil(options.body)
  }

  func test_initWithDataBody() {
    let bodyData = "binary value".data(using: .utf8)!
    let options = FunctionInvokeOptions(body: bodyData)
    XCTAssertEqual(options.headers.first { $0.name == "Content-Type" }?.value, "application/octet-stream")
    XCTAssertNotNil(options.body)
  }

  func test_initWithEncodableBody() {
    struct Body: Encodable {
      let value: String
    }
    let bodyData = try! JSONEncoder().encode(Body(value: "value"))
    let options = FunctionInvokeOptions(body: bodyData)
    XCTAssertEqual(options.headers.first { $0.name == "Content-Type" }?.value, "application/json")
    XCTAssertNotNil(options.body)
  }

  func test_initWithCustomContentType() {
    let boundary = "Boundary-\(UUID().uuidString)"
    let contentType = "multipart/form-data; boundary=\(boundary)"
    let bodyData = "binary value".data(using: .utf8)!
    let options = FunctionInvokeOptions(
      body: bodyData,
      headers: [HTTPHeader(name: "Content-Type", value: contentType)]
    )
    XCTAssertEqual(options.headers.first { $0.name == "Content-Type" }?.value, contentType)
    XCTAssertNotNil(options.body)
  }

  func testMethod() {
    let testCases: [HTTPMethod] = [.get, .post, .put, .patch, .delete]

    for method in testCases {
      let options = FunctionInvokeOptions(method: method)
      XCTAssertEqual(options.method, method)
    }
  }
}
