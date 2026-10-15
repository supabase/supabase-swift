//
//  CopyOptionsIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation
import Storage
import Testing

/// `copy` sends `CopyOptions` the way Storage's `object/copy` route reads them, and returns the
/// copy as an `UploadedObject`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct CopyOptionsIntegrationTests {
  static func seededBucket() async throws -> (name: String, bucket: StorageBucket) {
    let name = try await StorageIntegration.newBucket("copy-options")
    let bucket = StorageIntegration.admin.from(name)
    try await bucket.upload(
      path: "src.txt", data: Data("src".utf8),
      options: UploadOptions(contentType: "text/plain", metadata: ["k": "v"]))
    return (name, bucket)
  }

  @Test
  func copyReturnsTheObjectAndKeepsTheMetadata() async throws {
    let (name, bucket) = try await Self.seededBucket()
    defer { StorageIntegration.dropBucket(name) }

    let copy = try await bucket.copy(from: "src.txt", to: "dir/dst.txt")

    #expect(copy.path == "dir/dst.txt")
    #expect(copy.fullPath == "\(name)/dir/dst.txt")
    let info = try await bucket.info(path: "dir/dst.txt")
    #expect(copy.id == info.id)
    #expect(info.userMetadata == ["k": "v"])
    #expect(info.contentType == "text/plain")
  }

  @Test
  func upsertReplacesAnExistingDestination() async throws {
    let (name, bucket) = try await Self.seededBucket()
    defer { StorageIntegration.dropBucket(name) }
    try await bucket.upload(path: "dst.txt", data: Data("old".utf8))

    let error = await StorageIntegration.storageError {
      try await bucket.copy(from: "src.txt", to: "dst.txt")
    }
    #expect(error?.kind == .server)

    try await bucket.copy(from: "src.txt", to: "dst.txt", options: CopyOptions(upsert: true))
    let body = try await bucket.download(path: "dst.txt").data()
    #expect(body == Data("src".utf8))
  }

  @Test
  func copyCanReplaceTheMetadata() async throws {
    let (name, bucket) = try await Self.seededBucket()
    defer { StorageIntegration.dropBucket(name) }

    try await bucket.copy(
      from: "src.txt", to: "dst.txt",
      options: CopyOptions(
        copyMetadata: false, metadata: ["n": 1], contentType: "application/json",
        cacheControl: .maxAge(.seconds(60))))

    let info = try await bucket.info(path: "dst.txt")
    #expect(info.userMetadata == ["n": 1])
    #expect(info.contentType == "application/json")
    #expect(info.cacheControl == "max-age=60")
  }

  @Test
  func removeLeavesTheBatchLimitToStorage() async throws {
    let (name, bucket) = try await Self.seededBucket()
    defer { StorageIntegration.dropBucket(name) }

    // The limit is a project setting, off on the local stack, so 1001 paths go through.
    let paths = ["src.txt"] + (1...1000).map { "missing-\($0).txt" }
    let removed = try await bucket.remove(paths: paths)
    #expect(removed.map(\.name) == ["src.txt"])

    let error = await StorageIntegration.storageError {
      _ = try await bucket.remove(paths: [])
    }
    #expect(error?.kind == .server)
    #expect(error?.code == .invalidRequest)
  }
}
