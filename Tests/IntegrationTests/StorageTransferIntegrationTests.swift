//
//  StorageTransferIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 04/05/26.
//

import Foundation
import Storage
import Testing

// Requires: supabase start && supabase db reset (from Tests/IntegrationTests/)
// Run with: make test-integration

@Suite(.serialized)
final class StorageTransferIntegrationTests {

  let storage = StorageClient(
    url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
    configuration: StorageClientConfiguration(
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
      ],
      logger: nil
    )
  )

  init() throws {
    try #require(
      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil,
      "INTEGRATION_TESTS not defined."
    )
  }

  /// Creates a fresh bucket, runs the test body, then cleans up regardless of success or failure.
  private func withBucket(_ body: (String) async throws -> Void) async throws {
    let bucketId = "transfer-test-\(UUID().uuidString.lowercased())"
    try await storage.createBucket(bucketId, options: BucketOptions(isPublic: false))
    do {
      try await body(bucketId)
    } catch {
      try? await storage.emptyBucket(bucketId)
      try? await storage.deleteBucket(bucketId)
      throw error
    }
    try? await storage.emptyBucket(bucketId)
    try? await storage.deleteBucket(bucketId)
  }

  @Test func tusUploadCompletesAndFileExists() async throws {
    try await withBucket { bucket in
      let data = Data(repeating: 0xAB, count: 512 * 1024)  // 512 KB (fast, < 6 MB chunk)
      let path = "integration/\(UUID().uuidString).bin"

      let response = try await storage.from(bucket).upload(path, data: data).value
      #expect(response.path == path)

      let downloaded = try await storage.from(bucket).downloadData(path: path).value
      #expect(downloaded == data)

      try await storage.from(bucket).remove(paths: [path])
    }
  }

  @Test func tusUploadLargeFileInChunks() async throws {
    try await withBucket { bucket in
      // 13 MB → 3 chunks (needs real TUS multi-chunk behavior)
      let data = Data(repeating: 0xCD, count: 13 * 1024 * 1024)
      let path = "integration/large-\(UUID().uuidString).bin"

      var progressValues: [Double] = []
      let task = storage.from(bucket).upload(path, data: data)

      for await event in task.events {
        if case .progress(let p) = event {
          progressValues.append(p.fractionCompleted)
        }
      }

      #expect(!progressValues.isEmpty)
      #expect(progressValues.count >= 2)
      // Progress values should be ascending
      #expect(progressValues == progressValues.sorted())

      // Verify the upload actually completed successfully
      _ = try await task.value

      try await storage.from(bucket).remove(paths: [path])
    }
  }

  @Test func downloadDataMatchesUploadedContent() async throws {
    try await withBucket { bucket in
      let original = Data("hello integration test".utf8)
      let path = "integration/\(UUID().uuidString).txt"

      _ = try await storage.from(bucket).upload(
        path, data: original, options: FileOptions(contentType: "text/plain")
      ).value
      let downloaded = try await storage.from(bucket).downloadData(path: path).value

      #expect(downloaded == original)
      try await storage.from(bucket).remove(paths: [path])
    }
  }

  @Test func cancelledUploadDoesNotCreateObject() async throws {
    try await withBucket { bucket in
      let data = Data(repeating: 0xEF, count: 13 * 1024 * 1024)
      let path = "integration/cancelled-\(UUID().uuidString).bin"

      let task = storage.from(bucket).upload(path, data: data)
      task.cancel()

      // Wait briefly to let the cancellation propagate
      do {
        _ = try await task.value
      } catch let error as StorageError where error.errorCode == .cancelled {
        // Expected: task was cancelled
      } catch {
        throw error  // Unexpected error — surface it
      }

      let exists = try await storage.from(bucket).exists(path: path)
      #expect(!exists)
    }
  }
}
