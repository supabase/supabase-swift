//
//  VersioningTests.swift
//  Storage
//
//  Created by Guilherme Souza on 14/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Testing

@testable import Storage

/// `versionId` on every object route that takes one.
@Suite
struct VersioningTests {
  typealias Sent = BucketRequestTests.Sent

  static func makeBucket(sent: LockIsolated<[Sent]>, response: String) -> StorageBucket {
    BucketRequestTests.makeClient(sent: sent, response: response).from("bucket")
  }

  @Test
  func infoSendsTheVersion() async throws {
    let sent = LockIsolated<[Sent]>([])
    let bucket = Self.makeBucket(
      sent: sent,
      response: #"{"id":"8B1F9F4E-2C61-4E3A-9D53-0F1D2B4C6A7E","version":"v1","name":"a.png"}"#)

    let info = try await bucket.info(path: "a.png", versionId: "v1")

    #expect(info.version == "v1")
    #expect(sent.value.map(\.request.path) == ["/storage/v1/object/info/bucket/a.png?versionId=v1"])
  }

  @Test
  func createSignedURLSendsTheVersion() async throws {
    let sent = LockIsolated<[Sent]>([])
    let bucket = Self.makeBucket(
      sent: sent, response: #"{"signedURL":"/object/sign/bucket/a.png?token=t"}"#)

    _ = try await bucket.createSignedURL(path: "a.png", expiresIn: .seconds(60), versionId: "v1")

    #expect(sent.value.map(\.body) == [#"{"expiresIn":60,"versionId":"v1"}"#])
  }

  @Test
  func publicURLCarriesTheVersion() {
    let bucket = Self.makeBucket(sent: .init([]), response: "")

    let url = bucket.publicURL(path: "a.png", versionId: "v1", cacheNonce: "n")

    #expect(
      url.absoluteString
        == "http://localhost:54321/storage/v1/object/public/bucket/a.png?cacheNonce=n&versionId=v1")
  }

  @Test
  func moveAndCopySendTheBucketAndSourceVersion() async throws {
    let sent = LockIsolated<[Sent]>([])
    let bucket = Self.makeBucket(sent: sent, response: #"{"Key":"other/b.png"}"#)

    try await bucket.move(from: "a.png", to: "b.png", toBucket: "other", sourceVersionId: "v1")
    try await bucket.copy(from: "a.png", to: "b.png", toBucket: "other", sourceVersionId: "v1")

    let body =
      #"{"bucketId":"bucket","destinationBucket":"other","destinationKey":"b.png","sourceKey":"a.png","sourceVersionId":"v1"}"#
    #expect(
      sent.value.map(\.request.path) == ["/storage/v1/object/move", "/storage/v1/object/copy"])
    #expect(sent.value.map(\.body) == [body, body])
  }

  @Test
  func removeVersionsSendsPathAndVersionPairs() async throws {
    let sent = LockIsolated<[Sent]>([])
    let bucket = Self.makeBucket(sent: sent, response: "[]")

    try await bucket.remove(versions: [
      ObjectVersion(path: "/a//b.png", versionId: "v1"),
      ObjectVersion(path: "c.png", versionId: "v2"),
    ])

    #expect(sent.value.map(\.request.method) == [.delete])
    #expect(
      sent.value.map(\.body) == [
        #"{"prefixes":[{"path":"a\/b.png","versionId":"v1"},{"path":"c.png","versionId":"v2"}]}"#
      ])
  }
}
