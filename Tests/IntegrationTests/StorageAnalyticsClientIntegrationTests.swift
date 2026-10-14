//
//  StorageAnalyticsClientIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation
@_spi(Experimental) import Storage
import Testing

/// Analytics buckets need Storage's Iceberg routes. Only the Docker stack serves them, after
/// `scripts/enable-storage-test-features.sh`; the native stack answers 404.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct StorageAnalyticsClientIntegrationTests {
  let analytics = StorageIntegration.admin.analytics

  @Test(.enabled(if: StorageIntegration.hasTestFeatures))
  func bucketCRUD() async throws {
    let name = "analytics-\(UUID().uuidString.lowercased().prefix(8))"

    let created = try await analytics.createBucket(name)
    #expect(created.name == name)
    #expect(created.id == name)

    let listed = try await analytics.listBuckets(options: BucketListOptions(search: name))
    #expect(listed.map(\.name) == [name])
    #expect(listed.first?.createdAt == created.createdAt)

    let duplicate = await StorageIntegration.storageError {
      try await analytics.createBucket(name)
    }
    #expect(duplicate?.kind == .server)

    try await analytics.deleteBucket(name)
    #expect(try await analytics.listBuckets(options: BucketListOptions(search: name)).isEmpty)
  }

  @Test(.enabled(if: !StorageIntegration.hasTestFeatures))
  func aStackWithoutIcebergAnswersNotFound() async throws {
    let error = await StorageIntegration.storageError {
      _ = try await analytics.listBuckets()
    }

    #expect(error?.kind == .server)
    #expect(error?.isNotFound == true)
  }
}
