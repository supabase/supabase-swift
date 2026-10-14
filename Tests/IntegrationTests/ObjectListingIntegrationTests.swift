//
//  ObjectListingIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation
import Storage
import Testing

/// `objects(prefix:options:)` pages through Storage's `object/list-v2` route.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct ObjectListingIntegrationTests {
  static let keys = ["2026/a.txt", "2026/b.txt", "2026/c.txt", "2026/deep/d.txt", "2026-old/e.txt"]

  static func seededBucket() async throws -> (name: String, bucket: StorageBucket) {
    let name = try await StorageIntegration.newBucket("object-listing")
    let bucket = StorageIntegration.admin.from(name)
    for key in keys {
      try await bucket.upload(path: key, data: Data(key.utf8))
    }
    return (name, bucket)
  }

  @Test
  func iteratingFollowsTheCursorAcrossPages() async throws {
    let (name, bucket) = try await Self.seededBucket()
    defer { StorageIntegration.dropBucket(name) }

    var pages: [ObjectListing.Page] = []
    for try await page in bucket.objects(
      prefix: "2026/", options: ObjectListingOptions(pageSize: 2)
    ).pages {
      pages.append(page)
    }

    #expect(pages.count == 2)
    #expect(pages.flatMap { $0.objects.map(\.name) } == ["2026/a.txt", "2026/b.txt", "2026/c.txt"])
    #expect(pages.flatMap(\.folders) == ["2026/deep/"])
    #expect(pages.last?.nextCursor == nil)
  }

  @Test
  func flatListingReturnsEveryDepth() async throws {
    let (name, bucket) = try await Self.seededBucket()
    defer { StorageIntegration.dropBucket(name) }

    var names: [String] = []
    for try await object in bucket.objects(
      prefix: "2026", options: ObjectListingOptions(pageSize: 2, delimited: false))
    {
      names.append(object.name)
    }

    #expect(names == Self.keys.sorted())
  }

  @Test
  func pageAfterResumesFromAKeptCursor() async throws {
    let (name, bucket) = try await Self.seededBucket()
    defer { StorageIntegration.dropBucket(name) }
    let listing = bucket.objects(
      prefix: "2026/", options: ObjectListingOptions(pageSize: 1, delimited: false))

    let first = try await listing.page()
    let second = try await listing.page(after: try #require(first.nextCursor))

    #expect(first.objects.map(\.name) == ["2026/a.txt"])
    #expect(second.objects.map(\.name) == ["2026/b.txt"])
  }
}
