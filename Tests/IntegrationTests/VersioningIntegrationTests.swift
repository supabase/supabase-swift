//
//  VersioningIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation
import Storage
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The `versionId` parameters reach Storage. The buckets keep versioning off, so each object has
/// one version, its current one, and the tests address it by its id.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct VersioningIntegrationTests {
  @Test
  func readsAndSignsAVersion() async throws {
    let name = try await StorageIntegration.newBucket("versioning")
    defer { StorageIntegration.dropBucket(name) }
    let bucket = StorageIntegration.admin.from(name)
    try await bucket.upload(path: "a.txt", data: Data("a".utf8))
    let version = try await bucket.info(path: "a.txt").version

    let info = try await bucket.info(path: "a.txt", versionId: version)
    #expect(info.version == version)

    let missing = await StorageIntegration.storageError {
      _ = try await bucket.info(path: "a.txt", versionId: UUID().uuidString)
    }
    #expect(missing?.isNotFound == true)

    let signed = try await bucket.createSignedURL(
      path: "a.txt", expiresIn: .seconds(60), versionId: version)
    let (signedData, signedResponse) = try await StorageIntegration.fetch(signed)
    #expect(signedResponse.statusCode == 200)
    #expect(signedData == Data("a".utf8))

    let (publicData, publicResponse) = try await StorageIntegration.fetch(
      bucket.publicURL(path: "a.txt", versionId: version))
    #expect(publicResponse.statusCode == 200)
    #expect(publicData == Data("a".utf8))
  }

  @Test
  func copiesMovesAndRemovesAVersion() async throws {
    let name = try await StorageIntegration.newBucket("versioning")
    defer { StorageIntegration.dropBucket(name) }
    let bucket = StorageIntegration.admin.from(name)
    try await bucket.upload(path: "a.txt", data: Data("a".utf8))
    let version = try await bucket.info(path: "a.txt").version

    try await bucket.copy(from: "a.txt", to: "b.txt", sourceVersionId: version)
    let copyVersion = try await bucket.info(path: "b.txt").version
    try await bucket.move(from: "b.txt", to: "c.txt", sourceVersionId: copyVersion)
    #expect(try await bucket.exists(path: "c.txt"))
    #expect(try await bucket.exists(path: "b.txt") == false)

    let removed = try await bucket.remove(versions: [
      ObjectVersion(path: "a.txt", versionId: version)
    ])
    #expect(removed.map(\.name) == ["a.txt"])
    #expect(try await bucket.exists(path: "a.txt") == false)
  }
}

/// A bucket's versioning status goes through create, update and read.
///
/// Storage reports the status from v1.81.0. An older stack ignores it, so the suite runs only
/// where Storage reports one. Turning versioning on also needs `STORAGE_VERSIONING_ENABLED`, which
/// `scripts/enable-storage-test-features.sh` sets.
@Suite(
  .enabled("Storage reports a bucket's versioning status") {
    guard ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil else { return false }
    let name = try await StorageIntegration.newBucket("versioning-probe")
    defer { StorageIntegration.dropBucket(name) }
    return try await StorageIntegration.admin.bucket(name).versioningStatus != nil
  })
struct BucketVersioningIntegrationTests {
  @Test
  func aNewBucketStartsDisabled() async throws {
    let name = try await StorageIntegration.newBucket("versioning")
    defer { StorageIntegration.dropBucket(name) }

    #expect(try await StorageIntegration.admin.bucket(name).versioningStatus == .disabled)
  }

  @Test(.enabled(if: StorageIntegration.hasTestFeatures))
  func enablesSuspendsAndReenables() async throws {
    let storage = StorageIntegration.admin
    let name = "versioning-\(UUID().uuidString.lowercased())"
    await StorageIntegration.finishPendingDrops()
    try await storage.createBucket(name, options: CreateBucketOptions(versioningStatus: .enabled))
    defer { StorageIntegration.dropBucket(name) }
    #expect(try await storage.bucket(name).versioningStatus == .enabled)

    try await storage.updateBucket(name, options: UpdateBucketOptions(versioningStatus: .suspended))
    #expect(try await storage.bucket(name).versioningStatus == .suspended)

    try await storage.updateBucket(name, options: UpdateBucketOptions(versioningStatus: .enabled))
    let buckets = try await storage.listBuckets(options: BucketListOptions(search: name))
    #expect(buckets.map(\.versioningStatus) == [.enabled])
  }

  @Test(.enabled(if: !StorageIntegration.hasTestFeatures))
  func refusesToEnableVersioningWhenStorageHasItOff() async throws {
    let name = "versioning-\(UUID().uuidString.lowercased())"
    await StorageIntegration.finishPendingDrops()

    let error = await StorageIntegration.storageError {
      try await StorageIntegration.admin.createBucket(
        name, options: CreateBucketOptions(versioningStatus: .enabled))
    }
    #expect(error?.code == .featureNotEnabled)
  }

  @Test(.enabled(if: StorageIntegration.hasTestFeatures))
  func refusesToSuspendABucketThatNeverHadVersioning() async throws {
    let name = try await StorageIntegration.newBucket("versioning")
    defer { StorageIntegration.dropBucket(name) }

    let error = await StorageIntegration.storageError {
      try await StorageIntegration.admin.updateBucket(
        name, options: UpdateBucketOptions(versioningStatus: .suspended))
    }
    #expect(error != nil)
    #expect(try await StorageIntegration.admin.bucket(name).versioningStatus == .disabled)
  }
}
