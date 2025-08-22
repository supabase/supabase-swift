import Alamofire
import HTTPTypes
import XCTest

@testable import Functions

final class FunctionInvokeOptionsTests: XCTestCase {
  func test_initWithStringBody() {
    let options = FunctionInvokeOptions(body: "string value")
    XCTAssertEqual(options.headers["Content-Type"], "text/plain")
    XCTAssertNotNil(options.body)
  }

  func test_initWithDataBody() {
    let options = FunctionInvokeOptions(body: "binary value".data(using: .utf8)!)
    XCTAssertEqual(options.headers["Content-Type"], "application/octet-stream")
    XCTAssertNotNil(options.body)
  }

  func test_initWithEncodableBody() {
    struct Body: Encodable {
      let value: String
    }
    let options = FunctionInvokeOptions(body: Body(value: "value"))
    XCTAssertEqual(options.headers["Content-Type"], "application/json")
    XCTAssertNotNil(options.body)
  }

  func test_initWithCustomContentType() {
    let boundary = "Boundary-\(UUID().uuidString)"
    let contentType = "multipart/form-data; boundary=\(boundary)"
    let options = FunctionInvokeOptions(
      headers: ["Content-Type": contentType],
      body: "binary value".data(using: .utf8)!
    )
    XCTAssertEqual(options.headers["Content-Type"], contentType)
    XCTAssertNotNil(options.body)
  }

  func testMethod() {
    let testCases: [FunctionInvokeOptions.Method: Alamofire.HTTPMethod] = [
      .get: .get,
      .post: .post,
      .put: .put,
      .patch: .patch,
      .delete: .delete,
    ]

    for (method, expected) in testCases {
      XCTAssertEqual(FunctionInvokeOptions.httpMethod(method), expected)
    }
  }
}
