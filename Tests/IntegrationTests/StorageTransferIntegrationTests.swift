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
struct StorageTransferIntegrationTests {

  let storage = StorageClient(
    url: URL(string: "\(DotEnv.SUPABASE_URL)/storage/v1")!,
    configuration: StorageClientConfiguration(
      headers: [
        "Authorization": "Bearer \(DotEnv.SUPABASE_SECRET_KEY)"
      ],
      logger: nil
    )
  )

  let bucket = "transfer-test-\(UUID().uuidString)"

  init() async throws {
    try #require(
      ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil,
      "INTEGRATION_TESTS not defined."
    )

    do {
      _ = try await storage.getBucket(bucket)
    } catch {
      try await storage.createBucket(bucket, options: BucketOptions(isPublic: false))
    }
  }

  @Test func tusUploadCompletesAndFileExists() async throws {
    let data = Data(repeating: 0xAB, count: 512 * 1024)  // 512 KB (fast, < 6 MB chunk)
    let path = "integration/\(UUID().uuidString).bin"

    let response = try await storage.from(bucket).upload(path, data: data).result
    #expect(response.path == path)

    let downloaded = try await storage.from(bucket).downloadData(path: path).result
    #expect(downloaded == data)

    try await storage.from(bucket).remove(paths: [path])
  }

  @Test func tusUploadLargeFileInChunks() async throws {
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
    // Progress values should be ascending
    #expect(progressValues == progressValues.sorted())

    try await storage.from(bucket).remove(paths: [path])
  }

  @Test func downloadDataMatchesUploadedContent() async throws {
    let original = Data("hello integration test".utf8)
    let path = "integration/\(UUID().uuidString).txt"

    _ = try await storage.from(bucket).upload(
      path, data: original, options: FileOptions(contentType: "text/plain")
    ).result
    let downloaded = try await storage.from(bucket).downloadData(path: path).result

    #expect(downloaded == original)
    try await storage.from(bucket).remove(paths: [path])
  }

  @Test func cancelledUploadDoesNotCreateObject() async throws {
    let data = Data(repeating: 0xEF, count: 13 * 1024 * 1024)
    let path = "integration/cancelled-\(UUID().uuidString).bin"

    let task = storage.from(bucket).upload(path, data: data)
    task.cancel()

    // Wait briefly to let the cancellation propagate
    do {
      _ = try await task.result
    } catch {
      // Expected: task was cancelled
    }

    let exists = try await storage.from(bucket).exists(path: path)
    #expect(!exists)
  }
}
