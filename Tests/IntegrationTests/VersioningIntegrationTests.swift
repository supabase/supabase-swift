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

/// The `versionId` parameters reach Storage. Versioning cannot be turned on in the local stack,
/// so each object has one version, its current one, and the tests address it by its id.
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
