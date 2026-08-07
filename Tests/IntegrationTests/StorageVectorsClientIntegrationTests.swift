//
//  StorageVectorsClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 06/08/26.
//

import Foundation
import InlineSnapshotTesting
@_spi(Experimental) import Storage
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct StorageVectorsClientIntegrationTests {
  let vectors = SupabaseStorageClient(
    configuration: StorageClientConfiguration(
      url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
      ],
      logger: nil
    )
  ).vectors

  init() async throws {
    // Clean up test-vector-bucket if it exists from a previous failed run
    // to make tests idempotent
    try? await vectors.deleteBucket("test-vector-bucket")
  }

  @Test
  func vectorBucket_CRUD() async throws {
    let bucketName = "test-vector-bucket"

    var page = try await vectors.listBuckets()
    #expect(!page.vectorBuckets.contains { $0.vectorBucketName == bucketName })

    try await vectors.createBucket(bucketName)

    let bucket = try await vectors.getBucket(bucketName)
    #expect(bucket.vectorBucketName == bucketName)

    page = try await vectors.listBuckets()
    #expect(page.vectorBuckets.contains { $0.vectorBucketName == bucketName })

    try await vectors.deleteBucket(bucketName)

    page = try await vectors.listBuckets()
    #expect(!page.vectorBuckets.contains { $0.vectorBucketName == bucketName })
  }

  @Test
  func listBucketsWithPrefix() async throws {
    let bucketName = "test-vector-bucket"
    try await vectors.createBucket(bucketName)

    let matching = try await vectors.listBuckets(prefix: "test-vector-")
    #expect(matching.vectorBuckets.contains { $0.vectorBucketName == bucketName })

    let nonMatching = try await vectors.listBuckets(prefix: "no-such-prefix-")
    #expect(!nonMatching.vectorBuckets.contains { $0.vectorBucketName == bucketName })

    try await vectors.deleteBucket(bucketName)
  }

  @Test
  func getBucketWithWrongName() async {
    do {
      _ = try await vectors.getBucket("not-exist-bucket")
      Issue.record("Unexpected success")
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        ▿ StorageError
          ▿ error: Optional<String>
            - some: "NotFoundException"
          - message: "resource \\"not-exist-bucket\\" not found"
          ▿ statusCode: Optional<String>
            - some: "404"

        """
      }
    }
  }
}
