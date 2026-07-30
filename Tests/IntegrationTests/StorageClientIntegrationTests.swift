//
//  StorageClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import InlineSnapshotTesting
import Storage
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct StorageClientIntegrationTests {
  let storage = SupabaseStorageClient(
    configuration: StorageClientConfiguration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
      ],
      logger: nil
    )
  )

  init() async throws {
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

  @Test
  func bucket_CRUD() async throws {
    let bucketName = "test-bucket"

    var buckets = try await storage.listBuckets()
    #expect(!buckets.contains(where: { $0.name == bucketName }))

    try await storage.createBucket(bucketName, options: .init(public: true))

    var bucket = try await storage.getBucket(bucketName)
    #expect(bucket.name == bucketName)
    #expect(bucket.id == bucketName)
    #expect(bucket.isPublic == true)

    buckets = try await storage.listBuckets()
    #expect(buckets.contains { $0.id == bucket.id })

    try await storage.updateBucket(
      bucketName, options: BucketOptions(isPublic: false, allowedMimeTypes: ["image/jpeg"]))

    bucket = try await storage.getBucket(bucketName)
    #expect(bucket.allowedMimeTypes == ["image/jpeg"])

    try await storage.deleteBucket(bucketName)

    buckets = try await storage.listBuckets()
    #expect(!buckets.contains { $0.id == bucket.id })
  }

  @Test
  func getBucketWithWrongId() async {
    do {
      _ = try await storage.getBucket("not-exist-id")
      Issue.record("Unexpected success")
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
