//
//  PurgeCacheIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation
import Storage
import Testing

/// CDN purge needs `CDN_PURGE_ENDPOINT_URL`. On the Docker stack,
/// `scripts/enable-storage-test-features.sh` points it at a stub that records each purge Storage
/// forwards. The native stack has no endpoint, so Storage answers `MissingParameter` once a
/// request matches a purge route; an unmatched path would get a 404 instead.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil), .serialized)
struct PurgeCacheIntegrationTests {
  let storage = StorageIntegration.admin

  @Test(.enabled(if: StorageIntegration.hasTestFeatures), arguments: [false, true])
  func storageForwardsEachScope(includingTransformations: Bool) async throws {
    let name = try await StorageIntegration.newBucket("purge")
    defer { StorageIntegration.dropBucket(name) }
    try await StorageIntegration.clearForwardedPurges()

    try await storage.purgeCache(bucket: nil, includingTransformations: includingTransformations)
    try await storage.purgeCache(bucket: name, includingTransformations: includingTransformations)
    try await storage.from(name).purgeCache(
      path: "dir/a file.png", includingTransformations: includingTransformations)

    // Deleting other suites' buckets forwards purges too, so keep this test's own.
    let purges = try await StorageIntegration.forwardedPurges()
      .filter { $0.body.bucketId == nil || $0.body.bucketId == name }
    let suffix = includingTransformations ? "-transforms" : ""
    #expect(
      purges.map(\.body) == [
        .init(type: "tenant\(suffix)"),
        .init(type: "bucket\(suffix)", bucketId: name),
        .init(type: "object\(suffix)", bucketId: name, objectName: "dir/a file.png"),
      ])
  }

  @Test(.enabled(if: !StorageIntegration.hasTestFeatures), arguments: [false, true])
  func everyScopeReachesThePurgeRoute(includingTransformations: Bool) async throws {
    let name = try await StorageIntegration.newBucket("purge")
    defer { StorageIntegration.dropBucket(name) }

    let errors = [
      await StorageIntegration.storageError {
        try await storage.purgeCache(
          bucket: nil, includingTransformations: includingTransformations)
      },
      await StorageIntegration.storageError {
        try await storage.purgeCache(
          bucket: name, includingTransformations: includingTransformations)
      },
      await StorageIntegration.storageError {
        try await storage.from(name).purgeCache(
          path: "dir/a file.png", includingTransformations: includingTransformations)
      },
    ]

    #expect(errors.map { $0?.code } == Array(repeating: .missingParameter, count: 3))
    #expect(errors.allSatisfy { $0?.message.contains("CDN_PURGE_ENDPOINT_URL") == true })
  }
}
