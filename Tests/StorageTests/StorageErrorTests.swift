import XCTest

@testable import Storage

final class StorageErrorTests: XCTestCase {
  func testErrorInitialization() {
    let error = StorageError(
      statusCode: "404",
      message: "File not found",
      error: "NotFound"
    )

    XCTAssertEqual(error.statusCode, "404")
    XCTAssertEqual(error.message, "File not found")
    XCTAssertEqual(error.error, "NotFound")
  }

  func XXXtestLocalizedError() {
    let error = StorageError(
      statusCode: "500",
      message: "Internal server error",
      error: nil
    )

    XCTAssertEqual(error.errorDescription, "Internal server error")
  }

  func XXXtestDecoding() throws {
    let json = """
      {
          "statusCode": "403",
          "message": "Unauthorized access",
          "error": "Forbidden"
      }
      """.data(using: .utf8)!

    let error = try JSONDecoder().decode(StorageError.self, from: json)

    XCTAssertEqual(error.statusCode, "403")
    XCTAssertEqual(error.message, "Unauthorized access")
    XCTAssertEqual(error.error, "Forbidden")
  }
}
