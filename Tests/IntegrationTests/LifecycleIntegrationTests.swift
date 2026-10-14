//
//  LifecycleIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 14/10/26.
//

import Foundation
import Storage
import Testing

/// Object lifecycles need `STORAGE_LIFECYCLE_ENABLED`. Only the Docker stack sets it, after
/// `scripts/enable-storage-test-features.sh`; the native stack refuses each call with
/// `FeatureNotEnabled`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct LifecycleIntegrationTests {
  let storage = StorageIntegration.admin

  @Test(.enabled(if: StorageIntegration.hasTestFeatures))
  func setReadAndDeleteAPolicy() async throws {
    let name = try await StorageIntegration.newBucket("lifecycle")
    defer { StorageIntegration.dropBucket(name) }

    #expect(try await storage.lifecycle(forBucket: name) == nil)

    let stored = try await storage.setLifecycle(
      LifecycleConfiguration(rules: [
        LifecycleRule(
          id: "keep-3",
          noncurrentVersionExpiration: NoncurrentVersionExpiration(
            noncurrentDays: 7, newerNoncurrentVersions: 3)),
        LifecycleRule(
          status: .disabled,
          noncurrentVersionExpiration: NoncurrentVersionExpiration(noncurrentDays: 30)),
      ]),
      forBucket: name)

    #expect(stored.rules.count == 2)
    #expect(stored.rules[0].id == "keep-3")
    #expect(stored.rules[0].noncurrentVersionExpiration.newerNoncurrentVersions == 3)
    #expect(stored.rules[1].id != nil)
    #expect(stored.rules[1].status == .disabled)
    #expect(try await storage.lifecycle(forBucket: name) == stored)

    try await storage.deleteLifecycle(forBucket: name)
    #expect(try await storage.lifecycle(forBucket: name) == nil)
    // Deleting a policy that is not there still succeeds.
    try await storage.deleteLifecycle(forBucket: name)
  }

  @Test(.enabled(if: StorageIntegration.hasTestFeatures))
  func storageRejectsAnInvalidRule() async throws {
    let name = try await StorageIntegration.newBucket("lifecycle")
    defer { StorageIntegration.dropBucket(name) }

    let error = await StorageIntegration.storageError {
      try await storage.setLifecycle(
        LifecycleConfiguration(rules: [
          LifecycleRule(noncurrentVersionExpiration: NoncurrentVersionExpiration(noncurrentDays: 0))
        ]),
        forBucket: name)
    }

    #expect(error?.kind == .server)
  }

  @Test(.enabled(if: StorageIntegration.hasTestFeatures), arguments: [0, 1001])
  func storageRefusesARuleCountOutsideOneTo1000(count: Int) async throws {
    let name = try await StorageIntegration.newBucket("lifecycle")
    defer { StorageIntegration.dropBucket(name) }
    let rules = (0..<count).map {
      LifecycleRule(
        id: "r\($0)",
        noncurrentVersionExpiration: NoncurrentVersionExpiration(noncurrentDays: 30))
    }

    let error = await StorageIntegration.storageError {
      try await storage.setLifecycle(LifecycleConfiguration(rules: rules), forBucket: name)
    }

    #expect(error?.kind == .server)
    #expect(error?.code == .invalidRequest)
  }

  @Test(.enabled(if: !StorageIntegration.hasTestFeatures))
  func aStackWithoutLifecyclesRefusesEveryCall() async throws {
    let name = try await StorageIntegration.newBucket("lifecycle")
    defer { StorageIntegration.dropBucket(name) }
    let configuration = LifecycleConfiguration(rules: [
      LifecycleRule(noncurrentVersionExpiration: NoncurrentVersionExpiration(noncurrentDays: 30))
    ])

    // `lifecycle(forBucket:)` keeps `nil` for a bucket with no policy and throws this refusal.
    let errors = [
      await StorageIntegration.storageError { _ = try await storage.lifecycle(forBucket: name) },
      await StorageIntegration.storageError {
        try await storage.setLifecycle(configuration, forBucket: name)
      },
      await StorageIntegration.storageError { try await storage.deleteLifecycle(forBucket: name) },
    ]

    #expect(errors.map { $0?.code } == Array(repeating: .featureNotEnabled, count: 3))
  }
}
