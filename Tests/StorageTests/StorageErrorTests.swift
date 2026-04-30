import Foundation
import XCTest

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class StorageErrorTests: XCTestCase {

  // MARK: - StorageErrorCode

  func testErrorCodeRawRepresentable() {
    let code = StorageErrorCode("ObjectNotFound")
    XCTAssertEqual(code.rawValue, "ObjectNotFound")
  }

  func testErrorCodeInitFromRawValue() {
    let code = StorageErrorCode(rawValue: "BucketNotFound")
    XCTAssertEqual(code, .bucketNotFound)
  }

  func testErrorCodeEquality() {
    XCTAssertEqual(StorageErrorCode("ObjectNotFound"), .objectNotFound)
    XCTAssertNotEqual(StorageErrorCode("ObjectNotFound"), .bucketNotFound)
  }

  func testUnknownCodeRoundTrips() {
    let code = StorageErrorCode("SomeFutureCode")
    XCTAssertEqual(code.rawValue, "SomeFutureCode")
    XCTAssertNotEqual(code, .unknown)
  }

  // MARK: - StorageError initialisation

  func testAPIErrorWithFullHTTPContext() throws {
    let response = try XCTUnwrap(
      HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 404,
        httpVersion: nil,
        headerFields: nil
      )
    )
    let data = Data("not found".utf8)

    let error = StorageError(
      message: "Object not found",
      errorCode: .objectNotFound,
      statusCode: 404,
      underlyingResponse: response,
      underlyingData: data
    )

    XCTAssertEqual(error.message, "Object not found")
    XCTAssertEqual(error.errorCode, .objectNotFound)
    XCTAssertEqual(error.statusCode, 404)
    XCTAssertEqual(error.underlyingResponse?.statusCode, 404)
    XCTAssertEqual(error.underlyingData, data)
  }

  func testClientSideErrorHasNoHTTPContext() {
    let error = StorageError.noTokenReturned
    XCTAssertEqual(error.message, "No token returned by API")
    XCTAssertEqual(error.errorCode, .noTokenReturned)
    XCTAssertNil(error.statusCode)
    XCTAssertNil(error.underlyingResponse)
    XCTAssertNil(error.underlyingData)
  }

  // MARK: - LocalizedError

  func testErrorDescriptionEqualsMessage() {
    let error = StorageError(
      message: "Bucket not found",
      errorCode: .bucketNotFound,
      statusCode: 404
    )
    XCTAssertEqual(error.errorDescription, "Bucket not found")
  }

  // MARK: - isNotFound

  func testIsNotFoundStatus404() {
    let error = StorageError(message: "x", errorCode: .unknown, statusCode: 404)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundStatus400() {
    let error = StorageError(message: "x", errorCode: .unknown, statusCode: 400)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundObjectNotFoundCode() {
    let error = StorageError(message: "x", errorCode: .objectNotFound, statusCode: 200)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundBucketNotFoundCode() {
    let error = StorageError(message: "x", errorCode: .bucketNotFound, statusCode: 200)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundGenericNotFoundCode() {
    let error = StorageError(message: "x", errorCode: .notFound, statusCode: 200)
    XCTAssertTrue(error.isNotFound)
  }

  func testIsNotFoundFalseForServerError() {
    let error = StorageError(message: "x", errorCode: .unknown, statusCode: 500)
    XCTAssertFalse(error.isNotFound)
  }

  // MARK: - isUnauthorized

  func testIsUnauthorized401() {
    let error = StorageError(message: "x", errorCode: .unauthorized, statusCode: 401)
    XCTAssertTrue(error.isUnauthorized)
  }

  func testIsUnauthorized403() {
    let error = StorageError(message: "x", errorCode: .unauthorized, statusCode: 403)
    XCTAssertTrue(error.isUnauthorized)
  }

  func testIsUnauthorizedFalseForOtherStatus() {
    let error = StorageError(message: "x", errorCode: .objectNotFound, statusCode: 404)
    XCTAssertFalse(error.isUnauthorized)
  }
}
