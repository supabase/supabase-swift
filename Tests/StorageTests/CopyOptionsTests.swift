//
//  CopyOptionsTests.swift
//  Storage
//
//  Created by Guilherme Souza on 14/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Testing

@testable import Storage

@Suite
struct CopyOptionsTests {
  typealias Sent = BucketRequestTests.Sent

  static func makeBucket(sent: LockIsolated<[Sent]>, response: String) -> StorageBucket {
    BucketRequestTests.makeClient(sent: sent, response: response).from("bucket")
  }

  @Test
  func defaultsSendNothingExtra() async throws {
    let sent = LockIsolated<[Sent]>([])
    let bucket = Self.makeBucket(
      sent: sent, response: #"{"Id":"8B1F9F4E-2C61-4E3A-9D53-0F1D2B4C6A7E","Key":"bucket/b.png"}"#)

    let copy = try await bucket.copy(from: "a.png", to: "/b.png")

    #expect(copy.id == UUID(uuidString: "8B1F9F4E-2C61-4E3A-9D53-0F1D2B4C6A7E"))
    #expect(copy.path == "b.png")
    #expect(copy.fullPath == "bucket/b.png")
    let request = try #require(sent.value.first?.request)
    #expect(request.headerFields[.xUpsert] == nil)
    #expect(request.headerFields[.xMetadata] == nil)
    #expect(
      sent.value.map(\.body) == [
        #"{"bucketId":"bucket","destinationKey":"b.png","sourceKey":"a.png"}"#
      ])
  }

  @Test
  func sendsUpsertMetadataAndOverrides() async throws {
    let sent = LockIsolated<[Sent]>([])
    let bucket = Self.makeBucket(sent: sent, response: #"{"Key":"bucket/b.png"}"#)

    try await bucket.copy(
      from: "a.png", to: "b.png",
      options: CopyOptions(
        upsert: true, copyMetadata: false, metadata: ["k": "v"], contentType: "image/png",
        cacheControl: .noCache))

    let request = try #require(sent.value.first?.request)
    #expect(request.headerFields[.xUpsert] == "true")
    let metadata = try #require(request.headerFields[.xMetadata])
    #expect(Data(base64Encoded: metadata) == Data(#"{"k":"v"}"#.utf8))
    #expect(
      sent.value.map(\.body) == [
        #"{"bucketId":"bucket","copyMetadata":false,"destinationKey":"b.png","metadata":{"cacheControl":"no-cache","mimetype":"image\/png"},"sourceKey":"a.png"}"#
      ])
  }
}
