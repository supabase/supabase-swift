//
//  StorageClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 07/05/24.
//

import Foundation
import Storage
import Testing

@Suite(.serialized)
struct StorageClientIntegrationTests {
  let storage = StorageClient(
    url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
    configuration: StorageClientConfiguration(
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
      ],
      logger: nil
    )
  )

  @Test func bucketCRUD() async throws {
    let bucketName = "test-bucket"

    // Clean up any leftover from a previous failed run to make test idempotent.
    try? await storage.emptyBucket(bucketName)
    try? await storage.deleteBucket(bucketName)

    var buckets = try await storage.listBuckets()
    #expect(!buckets.contains(where: { $0.name == bucketName }))

    try await storage.createBucket(bucketName, options: .init(isPublic: true))

    var bucket = try await storage.getBucket(bucketName)
    #expect(bucket.name == bucketName)
    #expect(bucket.id == bucketName)
    #expect(bucket.isPublic == true)

    buckets = try await storage.listBuckets()
    #expect(buckets.contains { $0.id == bucket.id })

    try await storage.updateBucket(
      bucketName, options: BucketOptions(allowedMimeTypes: ["image/jpeg"]))

    bucket = try await storage.getBucket(bucketName)
    #expect(bucket.allowedMimeTypes == ["image/jpeg"])

    try await storage.deleteBucket(bucketName)

    buckets = try await storage.listBuckets()
    #expect(!buckets.contains { $0.id == bucket.id })
  }

  @Test func getBucketWithWrongId() async {
    do {
      _ = try await storage.getBucket("not-exist-id")
      Issue.record("Unexpected success")
    } catch let error as StorageError {
      #expect(error.statusCode == 404)
      #expect(error.message == "Bucket not found")
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }
}
