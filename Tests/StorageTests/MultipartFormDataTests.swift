import XCTest

@testable import Storage

final class MultipartFormDataTests: XCTestCase {
  func testBoundaryGeneration() {
    let formData = MultipartFormData()
    XCTAssertFalse(formData.boundary.isEmpty)
    XCTAssertTrue(formData.contentType.contains("multipart/form-data; boundary="))
  }

  func testAppendingData() {
    let formData = MultipartFormData()
    let testData = "Hello World".data(using: .utf8)!

    formData.append(testData, withName: "test", fileName: "test.txt", mimeType: "text/plain")

    XCTAssertGreaterThan(formData.contentLength, 0)
  }

  func testContentHeaders() {
    let formData = MultipartFormData()
    let testData = "Test".data(using: .utf8)!

    formData.append(
      testData,
      withName: "file",
      fileName: "test.txt",
      mimeType: "text/plain"
    )

    XCTAssertTrue(formData.contentType.hasPrefix("multipart/form-data"))
  }
}
