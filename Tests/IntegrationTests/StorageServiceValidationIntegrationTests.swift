//
//  StorageServiceValidationIntegrationTests.swift
//
//
//  Created by Guilherme Souza on 17/11/26.
//

import Foundation
import Storage
import Testing

/// Values the SDK sends as written, with Storage's own answer: "Validation belongs to the
/// service".
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
final class StorageServiceValidationIntegrationTests {
  let storage = StorageIntegration.admin
  var bucketName = ""

  init() async throws {
    bucketName = try await StorageIntegration.newBucket("validation")
  }

  deinit {
    StorageIntegration.dropBucket(bucketName)
  }

  @Test
  func updateBucketWithNoFieldReturnsTheServiceError() async throws {
    let error = await StorageIntegration.storageError {
      try await storage.updateBucket(bucketName, options: UpdateBucketOptions())
    }

    #expect(error?.kind == .server)
    #expect(error?.code == .invalidRequest)
    #expect(error?.serverError?.statusCode == 400)
  }

  @Test(arguments: [Duration.zero, .milliseconds(999), .seconds(-5)])
  func signedURLUnderOneSecondReturnsTheServiceError(expiresIn: Duration) async throws {
    let bucket = storage.from(bucketName)
    _ = try await bucket.upload(path: "f.txt", data: Data("hello".utf8))

    let single = await StorageIntegration.storageError {
      _ = try await bucket.createSignedURL(path: "f.txt", expiresIn: expiresIn)
    }
    let batch = await StorageIntegration.storageError {
      _ = try await bucket.createSignedURLs(paths: ["f.txt"], expiresIn: expiresIn)
    }

    for error in [single, batch] {
      #expect(error?.kind == .server)
      #expect(error?.code == .invalidRequest)
      #expect(error?.message.contains("expiresIn must be >= 1") == true)
    }
  }

  @Test
  func anEmptyPathGetsInvalidKeyOnItsOwnRoute() async throws {
    let bucket = storage.from(bucketName)
    _ = try await bucket.upload(path: "keep.txt", data: Data("keep".utf8))

    for call in [
      { _ = try await bucket.upload(path: "", data: Data("x".utf8)) },
      { _ = try await bucket.download(path: "") },
      { _ = try await bucket.info(path: "") },
      { _ = try await bucket.createSignedURL(path: "", expiresIn: .seconds(60)) },
      { try await bucket.move(from: "keep.txt", to: "") },
      { _ = try await bucket.copy(from: "", to: "copy.txt") },
    ] as [@Sendable () async throws -> Void] {
      let error = await StorageIntegration.storageError(call)
      #expect(error?.kind == .server)
      #expect(error?.code == .invalidKey)
    }

    // The batch routes answer per key: nothing to delete, nothing to sign.
    #expect(try await bucket.remove(paths: [""]).isEmpty)
    let signed = try await bucket.createSignedURLs(paths: [""], expiresIn: .seconds(60))
    #expect(signed.count == 1)
    if case .success = signed.first { Issue.record("Signed an empty path") }

    // Nothing else in the bucket was touched.
    #expect(try await bucket.download(path: "keep.txt").data() == Data("keep".utf8))
  }

  @Test
  func rawSlashesRoundTripAsTheirOwnKey() async throws {
    let bucket = storage.from(bucketName)
    let key = "/a//b/"

    let uploaded = try await bucket.upload(path: key, data: Data("slashes".utf8))

    #expect(uploaded.path == key)
    #expect(uploaded.fullPath == "\(bucketName)/\(key)")
    #expect(try await bucket.download(path: key).data() == Data("slashes".utf8))
    #expect(try await bucket.exists(path: "a/b") == false)
    let names = try await bucket.objects(options: ObjectListingOptions(delimited: false)).page()
      .objects.map(\.name)
    #expect(names == [key])

    try await bucket.remove(paths: [key])
    #expect(try await bucket.exists(path: key) == false)
  }

  @Test
  func aDotSegmentReachesTheServiceAndChangesNoOtherKey() async throws {
    let bucket = storage.from(bucketName)
    _ = try await bucket.upload(path: "d/y.txt", data: Data("original".utf8))

    for path in ["d/x/../y.txt", "d/./y.txt"] {
      let error = await StorageIntegration.storageError {
        _ = try await bucket.upload(
          path: path, data: Data("other".utf8), options: UploadOptions(upsert: true))
      }
      // The local file backend refuses the key (`InvalidKey`), but its failed cleanup masks the
      // answer as a 500 `InternalError`. Either way the refusal is Storage's, not the SDK's.
      #expect(error?.kind == .server)
      #expect([.invalidKey, .internalError].contains(error?.code))
    }

    #expect(try await bucket.download(path: "d/y.txt").data() == Data("original".utf8))
    let names = try await bucket.objects(options: ObjectListingOptions(delimited: false)).page()
      .objects.map(\.name)
    #expect(names == ["d/y.txt"])
  }
}
