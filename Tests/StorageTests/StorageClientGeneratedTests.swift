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
  @Test("listBuckets returns decoded buckets")
  func listBuckets() async throws {
    // Arrange: mock transport returning one bucket wrapped in {items:[...]} as the Smithy spec requires
    let json = """
      {"items":[{"id":"avatars","name":"avatars","public":true}]}
      """.data(using: .utf8)!
    let transport = MockTransport(responseData: json, statusCode: 200)
    let client = StorageClient(
      url: URL(string: "https://x.supabase.co/storage/v1")!,
      configuration: StorageClientConfiguration(headers: [:]),
      transport: transport
    )

    // Act
    let buckets = try await client.listBuckets()

    // Assert
    #expect(buckets.count == 1)
    #expect(buckets[0].id == "avatars")
    #expect(buckets[0].isPublic == true)
  }

  @Test("listBuckets throws StorageError on 400")
  func listBucketsBadRequest() async throws {
    let json = """
      {"message":"Permission denied","error":"Unauthorized","statusCode":"400"}
      """.data(using: .utf8)!
    let transport = MockTransport(responseData: json, statusCode: 400)
    let client = StorageClient(
      url: URL(string: "https://x.supabase.co/storage/v1")!,
      configuration: StorageClientConfiguration(headers: [:]),
      transport: transport
    )

    await #expect(throws: StorageError.self) {
      try await client.listBuckets()
    }
  }
}
