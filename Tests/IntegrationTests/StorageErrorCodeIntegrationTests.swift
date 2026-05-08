//
//  StorageErrorCodeIntegrationTests.swift
//  Storage
//
//  Created by Guilherme Souza on 08/05/26.
//

import Storage
import XCTest

// Verifies that every StorageErrorCode constant matches what the live storage server
// actually emits in the `error` JSON field.
final class StorageErrorCodeIntegrationTests: XCTestCase {

  // Service-role client — full access for setup and teardown.
  let storage = StorageClient(
    url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
    configuration: StorageClientConfiguration(
      headers: ["Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"],
      logger: nil
    )
  )

  // Anon client — used to trigger authorization errors.
  let anonStorage = StorageClient(
    url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
    configuration: StorageClientConfiguration(
      headers: ["Authorization": "Bearer \(DotEnv.SUPABASE_PUBLISHABLE_KEY)"],
      logger: nil
    )
  )

  // Client with a deliberately invalid JWT — gateway returns Unauthorized before
  // storage ever validates the JWT itself, so this triggers .unauthorized, not .invalidJWT.
  let badAuthStorage = StorageClient(
    url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
    configuration: StorageClientConfiguration(
      headers: ["Authorization": "Bearer not.a.valid.jwt"],
      logger: nil
    )
  )

  var bucketName = ""

  override func setUp() async throws {
    try await super.setUp()

    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil,
      "INTEGRATION_TESTS not defined."
    )

    bucketName = "error-codes-\(UUID().uuidString)"
    try await storage.createBucket(bucketName, options: BucketOptions(isPublic: false))
  }

  override func tearDown() async throws {
    try? await storage.emptyBucket(bucketName)
    try? await storage.deleteBucket(bucketName)
    try await super.tearDown()
  }

  // MARK: - Helpers

  private func jpegData() throws -> Data {
    try Data(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Upload/sadcat.jpg")
    )
  }

  private func assertStorageError(
    _ block: () async throws -> Void,
    expectedCode: StorageErrorCode,
    expectedStatus: Int,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      try await block()
      XCTFail("Expected StorageError but call succeeded", file: file, line: line)
    } catch let error as StorageError {
      XCTAssertEqual(
        error.errorCode, expectedCode,
        "errorCode mismatch — got rawValue '\(error.errorCode.rawValue)'",
        file: file, line: line
      )
      XCTAssertEqual(error.statusCode, expectedStatus, file: file, line: line)
    } catch {
      XCTFail("Unexpected error type: \(error)", file: file, line: line)
    }
  }

  // MARK: - Authentication / authorisation

  // Sending a malformed token triggers the gateway's auth rejection, which the storage
  // server surfaces as AccessDenied ("Unauthorized"), not InvalidJWT.
  // InvalidJWT is only emitted when the token structure is valid but the storage layer
  // itself rejects it (e.g. wrong secret for signed-URL validation), not for Bearer tokens.
  func testErrorCode_unauthorized_malformedToken() async {
    await assertStorageError(
      { _ = try await self.badAuthStorage.listBuckets() },
      expectedCode: .unauthorized,
      expectedStatus: 403
    )
  }

  // Anon key cannot create buckets — RLS on the buckets table rejects the insert.
  func testErrorCode_unauthorized_insufficientRole() async {
    await assertStorageError(
      {
        try await self.anonStorage.createBucket(
          "anon-bucket-\(UUID().uuidString)", options: BucketOptions(isPublic: false))
      },
      expectedCode: .unauthorized,
      expectedStatus: 403
    )
  }

  // MARK: - Object / bucket not found

  func testErrorCode_objectNotFound() async {
    await assertStorageError(
      { _ = try await self.storage.from(self.bucketName).download(path: "does-not-exist.jpg") },
      expectedCode: .objectNotFound,
      expectedStatus: 404
    )
  }

  func testErrorCode_objectNotFound_isNotFound() async throws {
    do {
      _ = try await storage.from(bucketName).download(path: "does-not-exist.jpg")
      XCTFail("Expected StorageError")
    } catch let error as StorageError {
      XCTAssertTrue(error.isNotFound)
    }
  }

  func testErrorCode_bucketNotFound() async {
    await assertStorageError(
      { _ = try await self.storage.getBucket("bucket-that-does-not-exist-\(UUID().uuidString)") },
      expectedCode: .bucketNotFound,
      expectedStatus: 404
    )
  }

  func testErrorCode_bucketNotFound_isNotFound() async throws {
    do {
      _ = try await storage.getBucket("bucket-that-does-not-exist-\(UUID().uuidString)")
      XCTFail("Expected StorageError")
    } catch let error as StorageError {
      XCTAssertTrue(error.isNotFound)
    }
  }

  // MARK: - Duplicate resources

  func testErrorCode_objectAlreadyExists() async throws {
    let path = "folder/file-\(UUID().uuidString).jpg"
    let data = try jpegData()
    try await storage.from(bucketName).upload(path, data: data)

    await assertStorageError(
      { try await self.storage.from(self.bucketName).upload(path, data: data) },
      expectedCode: .objectAlreadyExists,
      expectedStatus: 409
    )
  }

  func testErrorCode_bucketAlreadyExists() async {
    await assertStorageError(
      {
        try await self.storage.createBucket(
          self.bucketName, options: BucketOptions(isPublic: false))
      },
      expectedCode: .bucketAlreadyExists,
      expectedStatus: 409
    )
  }

  // Both objectAlreadyExists and bucketAlreadyExists share the "Duplicate" wire value —
  // the server does not distinguish between the two in the error field.
  func testBucketAndObjectAlreadyExistsShareWireValue() {
    XCTAssertEqual(StorageErrorCode.objectAlreadyExists, StorageErrorCode.bucketAlreadyExists)
  }

  // MARK: - Invalid bucket name

  // Empty bucket name fails the server's name-validation check.
  func testErrorCode_invalidBucketName() async {
    await assertStorageError(
      { try await self.storage.createBucket("", options: BucketOptions(isPublic: false)) },
      expectedCode: .invalidBucketName,
      expectedStatus: 400
    )
  }

  // MARK: - Upload errors

  func testErrorCode_entityTooLarge() async throws {
    let tinyBucket = "tiny-\(UUID().uuidString)"
    try await storage.createBucket(
      tinyBucket, options: BucketOptions(isPublic: true, fileSizeLimit: .kilobytes(1)))

    let data = try jpegData()  // ~28 KB, well above 1 KB limit
    await assertStorageError(
      {
        try await self.storage.from(tinyBucket).upload(
          "file.jpg", data: data, options: FileOptions(contentType: "image/jpeg"))
      },
      expectedCode: .entityTooLarge,
      expectedStatus: 413
    )

    try? await storage.deleteBucket(tinyBucket)
  }

  func testErrorCode_invalidMimeType() async throws {
    let strictBucket = "mime-\(UUID().uuidString)"
    try await storage.createBucket(
      strictBucket,
      options: BucketOptions(isPublic: true, allowedMimeTypes: ["image/png"])
    )

    let data = try jpegData()
    await assertStorageError(
      {
        try await self.storage.from(strictBucket).upload(
          "file.jpg", data: data, options: FileOptions(contentType: "image/jpeg"))
      },
      expectedCode: .invalidMimeType,
      expectedStatus: 415
    )

    try? await storage.deleteBucket(strictBucket)
  }

  // MARK: - Leading-slash path normalisation (#2)

  // _getFinalPath must strip leading slashes so "/folder/file.jpg" doesn't produce
  // the URL "bucket//folder/file.jpg", which would 404 even if the file exists.
  func testLeadingSlashPathNormalization() async throws {
    let data = try jpegData()
    let path = "folder/file-\(UUID().uuidString).jpg"

    try await storage.from(bucketName).upload(path, data: data)

    let downloaded = try await storage.from(bucketName).download(path: "/\(path)")
    XCTAssertEqual(downloaded, data)
  }
}
