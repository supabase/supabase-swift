import HTTPTypes
import XCTest

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

class PostgrestResponseTests: XCTestCase {
  func testInit() {
    // Prepare data and response
    let data = Data()
    let response = HTTPResponse(
      status: .init(code: 200),
      headerFields: [.contentRange: "bytes 0-100/200"]
    )
    let value = "Test Value"

    // Create the PostgrestResponse instance
    let postgrestResponse = PostgrestResponse(data: data, response: response, value: value)

    // Assert the properties
    XCTAssertEqual(postgrestResponse.data, data)
    XCTAssertEqual(postgrestResponse.response, response)
    XCTAssertEqual(postgrestResponse.value, value)
    XCTAssertEqual(postgrestResponse.status, 200)
    XCTAssertEqual(postgrestResponse.count, 200)
  }

  func testInitWithNoCount() {
    // Prepare data and response
    let data = Data()
    let response = HTTPResponse(
      status: .init(code: 200),
      headerFields: [.contentRange: "*"]
    )
    let value = "Test Value"

    // Create the PostgrestResponse instance
    let postgrestResponse = PostgrestResponse(data: data, response: response, value: value)

    // Assert the properties
    XCTAssertEqual(postgrestResponse.data, data)
    XCTAssertEqual(postgrestResponse.response, response)
    XCTAssertEqual(postgrestResponse.value, value)
    XCTAssertEqual(postgrestResponse.status, 200)
    XCTAssertNil(postgrestResponse.count)
  }
}
