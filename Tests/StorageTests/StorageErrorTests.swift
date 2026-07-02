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

  func testLocalizedError() {
    let error = StorageError(
      statusCode: "500",
      message: "Internal server error",
      error: nil
    )

    XCTAssertEqual(error.errorDescription, "Internal server error")
  }

  func testDecoding() throws {
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

  func testErrorCode_objectNotFound() {
    let error = StorageError(statusCode: "404", message: "not found", error: "not_found")
    XCTAssertEqual(error.errorCode, .objectNotFound)
  }

  func testErrorCode_unauthorized() {
    let error = StorageError(statusCode: "401", message: "unauthorized", error: "Unauthorized")
    XCTAssertEqual(error.errorCode, .unauthorized)
  }

  func testErrorCode_entityTooLarge() {
    let error = StorageError(statusCode: "413", message: "too large", error: "Payload too large")
    XCTAssertEqual(error.errorCode, .entityTooLarge)
  }

  func testErrorCode_unknownFallback() {
    let error = StorageError(statusCode: nil, message: "oops", error: nil)
    XCTAssertEqual(error.errorCode, .unknown)
  }

  func testErrorCode_customString() {
    let error = StorageError(statusCode: "400", message: "bad", error: "some_new_server_code")
    XCTAssertEqual(error.errorCode.rawValue, "some_new_server_code")
  }

  func testIsNotFound_objectNotFound() {
    let error = StorageError(statusCode: "404", message: "not found", error: "not_found")
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFound_bucketNotFound() {
    let error = StorageError(
      statusCode: "404", message: "bucket not found", error: "Bucket not found")
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFound_falseForOtherErrors() {
    let error = StorageError(statusCode: "403", message: "unauthorized", error: "Unauthorized")
    XCTAssertFalse(error.isNotFound)
  }

  func testIsUnauthorized() {
    let error = StorageError(statusCode: "401", message: "bad jwt", error: "InvalidJWT")
    XCTAssertTrue(error.isUnauthorized)
  }

  func testIsEntityTooLarge() {
    let error = StorageError(statusCode: "413", message: "too large", error: "Payload too large")
    XCTAssertTrue(error.isEntityTooLarge)
  }
}
