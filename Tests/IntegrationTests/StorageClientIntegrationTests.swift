//
//  StorageClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import Storage
import XCTest

final class StorageClientIntegrationTests: XCTestCase {
  let storage = StorageClient(
    url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
    configuration: StorageClientConfiguration(
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
      ],
      logger: nil
    )
  )

  override func setUp() async throws {
    try await super.setUp()

    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil,
      "INTEGRATION_TESTS not defined."
    )

    // Clean up test-bucket if it exists from a previous failed run
    // to make tests idempotent
    let testBucketName = "test-bucket"
    do {
      // First empty the bucket (required before deletion)
      let files = try await storage.from(testBucketName).list()
      if !files.isEmpty {
        let filePaths = files.map { $0.name }
        try await storage.from(testBucketName).remove(paths: filePaths)
      }
      try await storage.deleteBucket(testBucketName)
    } catch {
      // Ignore errors - bucket may not exist, which is expected
    }
  }

  func testBucket_CRUD() async throws {
    let bucketName = "test-bucket"

    var buckets = try await storage.listBuckets()
    XCTAssertFalse(buckets.contains(where: { $0.name == bucketName }))

    try await storage.createBucket(bucketName, options: .init(isPublic: true))

    var bucket = try await storage.getBucket(bucketName)
    XCTAssertEqual(bucket.name, bucketName)
    XCTAssertEqual(bucket.id, bucketName)
    XCTAssertEqual(bucket.isPublic, true)

    buckets = try await storage.listBuckets()
    XCTAssertTrue(buckets.contains { $0.id == bucket.id })

    try await storage.updateBucket(
      bucketName, options: BucketOptions(allowedMimeTypes: ["image/jpeg"]))

    bucket = try await storage.getBucket(bucketName)
    XCTAssertEqual(bucket.allowedMimeTypes, ["image/jpeg"])

    try await storage.deleteBucket(bucketName)

    buckets = try await storage.listBuckets()
    XCTAssertFalse(buckets.contains { $0.id == bucket.id })
  }

  func testGetBucketWithWrongId() async {
    do {
      _ = try await storage.getBucket("not-exist-id")
      XCTFail("Unexpected success")
    } catch let error as StorageError {
      XCTAssertEqual(error.statusCode, 404)
      XCTAssertEqual(error.message, "Bucket not found")
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }
}
