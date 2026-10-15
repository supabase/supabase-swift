//
//  BucketRequestTests.swift
//  Storage
//
//  Created by Guilherme Souza on 14/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Storage

/// The bucket routes, checked at the request and response level.
@Suite
struct BucketRequestTests {
  struct Sent: Sendable {
    var request: HTTPRequest
    var body: String?
  }

  /// A client whose transport records each request and answers with `response`.
  static func makeClient(
    sent: LockIsolated<[Sent]> = .init([]),
    status: HTTPResponse.Status = .ok,
    response: String
  ) -> StorageClient {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { request, body in
            var text: String?
            if let body {
              text = String(decoding: try await Data(collecting: body, upTo: .max), as: UTF8.self)
            }
            sent.withValue { [text] in $0.append(Sent(request: request, body: text)) }
            return (
              HTTPResponse(status: status, headerFields: [.contentType: "application/json"]),
              HTTPBody(Data(response.utf8))
            )
          }))
    )
  }

  @Test
  func listBucketsSendsTheOptionsAsQueryItems() async throws {
    let sent = LockIsolated<[Sent]>([])
    let storage = Self.makeClient(sent: sent, response: "[]")

    _ = try await storage.listBuckets(
      options: BucketListOptions(
        limit: 10, offset: 20, sortBy: .createdAt, order: .descending, search: "av"))

    #expect(
      sent.value.map(\.request.path) == [
        "/storage/v1/bucket?limit=10&offset=20&sortColumn=created_at&sortOrder=desc&search=av"
      ])
  }

  @Test
  func listBucketsWithoutOptionsSendsNoQuery() async throws {
    let sent = LockIsolated<[Sent]>([])
    let storage = Self.makeClient(sent: sent, response: "[]")

    _ = try await storage.listBuckets()

    #expect(sent.value.map(\.request.path) == ["/storage/v1/bucket"])
  }

  @Test
  func bucketDecodesTypeAndOwnerId() async throws {
    let storage = Self.makeClient(
      response: """
        [{"id":"a","name":"a","type":"ANALYTICS","owner_id":"u1","owner":"","public":false,
          "created_at":"2024-01-01T00:00:00.000Z","updated_at":"2024-01-01T00:00:00.000Z"},
         {"id":"b","name":"b","public":true,
          "created_at":"2024-01-01T00:00:00.000Z","updated_at":"2024-01-01T00:00:00.000Z"}]
        """)

    let buckets = try await storage.listBuckets()

    #expect(buckets.map(\.type) == [.analytics, nil])
    #expect(buckets.map(\.ownerId) == ["u1", nil])
  }

  @Test
  func createBucketSendsTheType() async throws {
    let sent = LockIsolated<[Sent]>([])
    let storage = Self.makeClient(sent: sent, response: #"{"name":"t"}"#)

    try await storage.createBucket("t", options: BucketOptions(type: .analytics))

    #expect(sent.value.map(\.body) == [#"{"id":"t","name":"t","type":"ANALYTICS"}"#])
  }

  @Test
  func updateBucketRefusesATypeBeforeSending() async throws {
    let sent = LockIsolated<[Sent]>([])
    let storage = Self.makeClient(sent: sent, response: #"{"message":"ok"}"#)

    let error = await #expect(throws: StorageError.self) {
      try await storage.updateBucket("t", options: BucketOptions(isPublic: true, type: .standard))
    }

    #expect(error?.kind == .invalidRequest)
    #expect(sent.value.isEmpty)
  }

  @Test
  func purgeCacheWithoutABucketPurgesTheTenant() async throws {
    let sent = LockIsolated<[Sent]>([])
    let storage = Self.makeClient(sent: sent, response: #"{"message":"success"}"#)

    try await storage.purgeCache(bucket: nil, includingTransformations: true)

    #expect(sent.value.map(\.request.method) == [.delete])
    #expect(sent.value.map(\.request.path) == ["/storage/v1/cdn/?transformations=true"])
  }
}
