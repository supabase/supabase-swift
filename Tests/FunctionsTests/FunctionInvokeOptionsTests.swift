import XCTest

@testable import Functions

final class FunctionInvokeOptionsTests: XCTestCase {
  func test_defaultInit() {
    let options = FunctionInvokeOptions()
    XCTAssertNil(options.method)
    XCTAssertEqual(options.headers, [:])
    XCTAssertNil(options.body)
    XCTAssertNil(options.region)
    XCTAssertEqual(options.query, [:])
  }

  func test_setMethod() {
    var options = FunctionInvokeOptions()
    options.method = .delete
    XCTAssertEqual(options.method, .delete)
  }

  func test_setBody() {
    var options = FunctionInvokeOptions()
    options.body = Data("hello".utf8)
    options.headers["Content-Type"] = "text/plain"
    XCTAssertEqual(options.headers["Content-Type"], "text/plain")
    XCTAssertNotNil(options.body)
  }

  func test_setRegion() {
    var options = FunctionInvokeOptions()
    options.region = .saEast1
    XCTAssertEqual(options.region, .saEast1)
  }
}
