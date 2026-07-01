//
//  StorageClientGeneratedTests.swift
//  StorageTests
//
//  Created by Guilherme Souza on 30/06/25.
//

import Foundation
import Testing

@testable import Storage

@Suite("StorageClient bucket operations via generated client")
struct StorageClientGeneratedTests {

  // MARK: - Helpers

  private func makeClient(json: String, statusCode: Int) -> StorageClient {
    let data = json.data(using: .utf8)!
    let transport = MockTransport(responseData: data, statusCode: statusCode)
    return StorageClient(
      url: URL(string: "https://x.supabase.co/storage/v1")!,
      configuration: StorageClientConfiguration(headers: [:]),
      transport: transport
    )
  }

  private static let badRequestJSON = """
    {"message":"Permission denied","error":"Unauthorized","statusCode":"400"}
    """

  // MARK: - listBuckets

  @Test("listBuckets returns decoded buckets")
  func listBuckets() async throws {
    let client = makeClient(
      json: #"{"items":[{"id":"avatars","name":"avatars","public":true}]}"#,
      statusCode: 200
    )
    let buckets = try await client.listBuckets()
    #expect(buckets.count == 1)
    #expect(buckets[0].id == "avatars")
    #expect(buckets[0].isPublic == true)
  }

  @Test("listBuckets throws StorageError on 400")
  func listBucketsBadRequest() async throws {
    let client = makeClient(json: Self.badRequestJSON, statusCode: 400)
    await #expect(throws: StorageError.self) {
      try await client.listBuckets()
    }
  }

  // MARK: - getBucket

  @Test("getBucket returns decoded bucket")
  func getBucket() async throws {
    let client = makeClient(
      json: #"{"id":"avatars","name":"avatars","public":false}"#,
      statusCode: 200
    )
    let bucket = try await client.getBucket("avatars")
    #expect(bucket.id == "avatars")
    #expect(bucket.isPublic == false)
  }

  @Test("getBucket throws StorageError on 400")
  func getBucketBadRequest() async throws {
    let client = makeClient(json: Self.badRequestJSON, statusCode: 400)
    await #expect(throws: StorageError.self) {
      try await client.getBucket("avatars")
    }
  }

  // MARK: - createBucket

  @Test("createBucket succeeds on 200")
  func createBucket() async throws {
    let client = makeClient(json: #"{"name":"avatars"}"#, statusCode: 200)
    // Should not throw.
    try await client.createBucket("avatars")
  }

  @Test("createBucket throws StorageError on 400")
  func createBucketBadRequest() async throws {
    let client = makeClient(json: Self.badRequestJSON, statusCode: 400)
    await #expect(throws: StorageError.self) {
      try await client.createBucket("avatars")
    }
  }

  // MARK: - updateBucket

  @Test("updateBucket succeeds on 200")
  func updateBucket() async throws {
    let client = makeClient(json: #"{"message":"Successfully updated"}"#, statusCode: 200)
    // Should not throw.
    try await client.updateBucket("avatars", options: BucketOptions(isPublic: true))
  }

  @Test("updateBucket throws StorageError on 400")
  func updateBucketBadRequest() async throws {
    let client = makeClient(json: Self.badRequestJSON, statusCode: 400)
    await #expect(throws: StorageError.self) {
      try await client.updateBucket("avatars", options: BucketOptions(isPublic: true))
    }
  }

  // MARK: - emptyBucket

  @Test("emptyBucket succeeds on 200")
  func emptyBucket() async throws {
    let client = makeClient(json: #"{"message":"Successfully emptied"}"#, statusCode: 200)
    // Should not throw.
    try await client.emptyBucket("avatars")
  }

  @Test("emptyBucket throws StorageError on 400")
  func emptyBucketBadRequest() async throws {
    let client = makeClient(json: Self.badRequestJSON, statusCode: 400)
    await #expect(throws: StorageError.self) {
      try await client.emptyBucket("avatars")
    }
  }

  // MARK: - deleteBucket

  @Test("deleteBucket succeeds on 200")
  func deleteBucket() async throws {
    let client = makeClient(json: #"{"message":"Successfully deleted"}"#, statusCode: 200)
    // Should not throw.
    try await client.deleteBucket("avatars")
  }

  @Test("deleteBucket throws StorageError on 400")
  func deleteBucketBadRequest() async throws {
    let client = makeClient(json: Self.badRequestJSON, statusCode: 400)
    await #expect(throws: StorageError.self) {
      try await client.deleteBucket("avatars")
    }
  }
}
