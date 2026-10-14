//
//  BucketListingIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation
import Storage
import Testing

/// `listBuckets(options:)` sends `BucketListOptions` as the query Storage's `bucket` route reads,
/// and buckets decode their `type`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct BucketListingIntegrationTests {
  @Test
  func searchSortAndPagingApply() async throws {
    let prefix = "bucket-listing-\(UUID().uuidString.lowercased().prefix(8))"
    let names = ["\(prefix)-a", "\(prefix)-b", "\(prefix)-c"]
    for name in names {
      try await StorageIntegration.admin.createBucket(name, options: BucketOptions(type: .standard))
    }
    defer { names.forEach(StorageIntegration.dropBucket) }

    let descending = try await StorageIntegration.admin.listBuckets(
      options: BucketListOptions(sortBy: .name, order: .descending, search: prefix))
    #expect(descending.map(\.name) == names.reversed())
    #expect(descending.allSatisfy { $0.type == .standard })

    let middle = try await StorageIntegration.admin.listBuckets(
      options: BucketListOptions(
        limit: 1, offset: 1, sortBy: .createdAt, order: .ascending, search: prefix))
    #expect(middle.map(\.name) == [names[1]])
  }
}
