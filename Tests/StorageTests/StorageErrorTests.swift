import Foundation
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct StorageErrorTests {

  // MARK: - StorageErrorCode

  @Test func errorCodeRawRepresentable() {
    let code = StorageErrorCode("SomeFutureCode")
    #expect(code.rawValue == "SomeFutureCode")
  }

  @Test func errorCodeInitFromRawValue() {
    let code = StorageErrorCode(rawValue: "Bucket not found")
    #expect(code == .bucketNotFound)
  }

  @Test func errorCodeEquality() {
    #expect(StorageErrorCode("not_found") == .objectNotFound)
    #expect(StorageErrorCode("not_found") != .bucketNotFound)
  }

  @Test func unknownCodeRoundTrips() {
    let code = StorageErrorCode("SomeFutureCode")
    #expect(code.rawValue == "SomeFutureCode")
    #expect(code != .unknown)
  }

  // MARK: - StorageError initialisation

  @Test func apiErrorWithFullHTTPContext() throws {
    let response = try #require(
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

    #expect(error.message == "Object not found")
    #expect(error.errorCode == .objectNotFound)
    #expect(error.statusCode == 404)
    #expect(error.underlyingResponse?.statusCode == 404)
    #expect(error.underlyingData == data)
  }

  @Test func clientSideErrorHasNoHTTPContext() {
    let error = StorageError.noTokenReturned
    #expect(error.message == "No token returned by API")
    #expect(error.errorCode == .noTokenReturned)
    #expect(error.statusCode == nil)
    #expect(error.underlyingResponse == nil)
    #expect(error.underlyingData == nil)
  }

  // MARK: - LocalizedError

  @Test func errorDescriptionEqualsMessage() {
    let error = StorageError(
      message: "Bucket not found",
      errorCode: .bucketNotFound,
      statusCode: 404
    )
    #expect(error.errorDescription == "Bucket not found")
  }

  // MARK: - isNotFound

  @Test func isNotFoundStatus404() {
    let error = StorageError(message: "x", errorCode: .unknown, statusCode: 404)
    #expect(error.isNotFound)
  }

  @Test func isNotFoundStatus400() {
    // 400 is intentionally excluded from isNotFound — exists() handles it directly
    // because the Storage server returns 400 (not 404) for HEAD on non-existent objects.
    let error = StorageError(message: "x", errorCode: .unknown, statusCode: 400)
    #expect(!error.isNotFound)
  }

  @Test func isNotFoundObjectNotFoundCode() {
    let error = StorageError(message: "x", errorCode: .objectNotFound, statusCode: 200)
    #expect(error.isNotFound)
  }

  @Test func isNotFoundBucketNotFoundCode() {
    let error = StorageError(message: "x", errorCode: .bucketNotFound, statusCode: 200)
    #expect(error.isNotFound)
  }

  @Test func isNotFoundFalseForServerError() {
    let error = StorageError(message: "x", errorCode: .unknown, statusCode: 500)
    #expect(!error.isNotFound)
  }

  // MARK: - isUnauthorized

  @Test func isUnauthorized401() {
    let error = StorageError(message: "x", errorCode: .unauthorized, statusCode: 401)
    #expect(error.isUnauthorized)
  }

  @Test func isUnauthorized403() {
    let error = StorageError(message: "x", errorCode: .unauthorized, statusCode: 403)
    #expect(error.isUnauthorized)
  }

  @Test func isUnauthorizedFalseForOtherStatus() {
    let error = StorageError(message: "x", errorCode: .objectNotFound, statusCode: 404)
    #expect(!error.isUnauthorized)
  }
}
