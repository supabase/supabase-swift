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
        "Authorization": "Bearer \(DotEnv.SUPABASE_SERVICE_ROLE_KEY)",
      ],
      logger: nil
    )
  )

  func testBucket_CRUD() async throws {
    let bucketName = "test-bucket"

    var buckets = try await storage.listBuckets()
    XCTAssertEqual(buckets, [])

    try await storage.createBucket(bucketName, options: .init(public: true))

    var bucket = try await storage.getBucket(bucketName)
    XCTAssertEqual(bucket.name, bucketName)
    XCTAssertEqual(bucket.id, bucketName)
    XCTAssertEqual(bucket.isPublic, true)

    buckets = try await storage.listBuckets()
    XCTAssertEqual(buckets, [bucket])

    try await storage.updateBucket(bucketName, options: BucketOptions(allowedMimeTypes: ["image/jpeg"]))

    bucket = try await storage.getBucket(bucketName)
    XCTAssertEqual(bucket.allowedMimeTypes, ["image/jpeg"])

    try await storage.deleteBucket(bucketName)

    buckets = try await storage.listBuckets()
    XCTAssertEqual(buckets, [])
  }

  func testGetBucketWithWrongId() async {
    do {
      _ = try await storage.getBucket("not-exist-id")
      XCTFail("Unexpected success")
    } catch let error as StorageError {
      assertInlineSnapshot(of: error, as: .description) {
        """
        StorageError(statusCode: Optional("404"), message: "Bucket not found", error: Optional("Bucket not found"))
        """
      }
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func findOrCreateBucket(name: String, isPublic: Bool = true) async throws -> String {
    do {
      _ = try await storage.getBucket(name)
    } catch {
      try await storage.createBucket(name, options: .init(public: isPublic))
    }

    return name
  }

  private func uploadFileURL(_ fileName: String) -> URL {
    URL(fileURLWithPath: #file)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Upload")
      .appendingPathComponent(fileName)
  }
}
