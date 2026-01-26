//
//  StorageClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import InlineSnapshotTesting
import Storage
import XCTest

final class StorageClientIntegrationTests: XCTestCase {
  let storage = SupabaseStorageClient(
    configuration: StorageClientConfiguration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SERVICE_ROLE_KEY)"
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
  }

  func testBucket_CRUD() async throws {
    let bucketName = "test-bucket"

    var buckets = try await storage.listBuckets()
    XCTAssertFalse(buckets.contains(where: { $0.name == bucketName }))

    try await storage.createBucket(bucketName, options: .init(public: true))

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
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        ▿ StorageError
          ▿ error: Optional<String>
            - some: "Bucket not found"
          - message: "Bucket not found"
          ▿ statusCode: Optional<String>
            - some: "404"

        """
      }
    }
  }
}
