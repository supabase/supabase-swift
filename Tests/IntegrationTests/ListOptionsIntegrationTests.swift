//
//  ListOptionsIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation
import Storage
import Testing

/// `list(path:options:)` sends `ListOptions` the way Storage's `object/list` route reads it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct ListOptionsIntegrationTests {
  @Test
  func sortSearchAndPagingApply() async throws {
    let name = try await StorageIntegration.newBucket("list-options")
    defer { StorageIntegration.dropBucket(name) }
    let bucket = StorageIntegration.admin.from(name)
    for file in ["a.txt", "b.txt", "c.txt", "other.png"] {
      try await bucket.upload(path: "dir/\(file)", data: Data(file.utf8))
    }

    let descending = try await bucket.list(
      path: "dir", options: ListOptions(sortBy: .name, order: .descending))
    #expect(descending.map(\.name) == ["other.png", "c.txt", "b.txt", "a.txt"])

    let paged = try await bucket.list(
      path: "dir", options: ListOptions(limit: 2, offset: 1, sortBy: .name, order: .ascending))
    #expect(paged.map(\.name) == ["b.txt", "c.txt"])

    let searched = try await bucket.list(path: "dir", options: ListOptions(search: "other"))
    #expect(searched.map(\.name) == ["other.png"])

    let byCreation = try await bucket.list(
      path: "dir", options: ListOptions(sortBy: .createdAt, order: .ascending))
    #expect(byCreation.map(\.name) == ["a.txt", "b.txt", "c.txt", "other.png"])
  }

  @Test
  func versionFiltersAreAccepted() async throws {
    let name = try await StorageIntegration.newBucket("list-versions")
    defer { StorageIntegration.dropBucket(name) }
    let bucket = StorageIntegration.admin.from(name)
    try await bucket.upload(path: "a.txt", data: Data("a".utf8))

    // Versioning is off on the local stack, so every filter that keeps current objects
    // returns the one upload, and `.only` returns nothing.
    let included = try await bucket.list(
      options: ListOptions(versions: .include, deleteMarkers: .include))
    #expect(included.map(\.name) == ["a.txt"])

    let excluded = try await bucket.list(
      options: ListOptions(versions: .exclude, deleteMarkers: .exclude))
    #expect(excluded.map(\.name) == ["a.txt"])

    let onlyVersions = try await bucket.list(options: ListOptions(versions: .only))
    #expect(onlyVersions.isEmpty)
  }
}
