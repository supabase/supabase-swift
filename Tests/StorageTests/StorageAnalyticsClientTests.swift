//
//  StorageAnalyticsClientTests.swift
//  Storage
//
//  Created by Guilherme Souza on 14/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Testing

@_spi(Experimental) @testable import Storage

@Suite
struct StorageAnalyticsClientTests {
  typealias Sent = BucketRequestTests.Sent

  static func makeAnalytics(
    sent: LockIsolated<[Sent]> = .init([]),
    status: HTTPResponse.Status = .ok,
    response: String
  ) -> StorageAnalyticsClient {
    BucketRequestTests.makeClient(sent: sent, status: status, response: response).analytics
  }

  @Test
  func createBucketPostsTheNameAndDecodesTheBucket() async throws {
    let sent = LockIsolated<[Sent]>([])
    let analytics = Self.makeAnalytics(
      sent: sent,
      response: #"""
        {"id":"events","name":"events","created_at":"2026-01-01T00:00:00.000Z",
         "updated_at":"2026-01-02T00:00:00.000Z"}
        """#)

    let bucket = try await analytics.createBucket("events")

    #expect(bucket.id == "events")
    #expect(bucket.updatedAt > bucket.createdAt)
    #expect(sent.value.map(\.request.method) == [.post])
    #expect(sent.value.map(\.request.path) == ["/storage/v1/iceberg/bucket"])
    #expect(sent.value.map(\.body) == [#"{"name":"events"}"#])
  }

  @Test
  func listBucketsSendsTheOptions() async throws {
    let sent = LockIsolated<[Sent]>([])
    let analytics = Self.makeAnalytics(sent: sent, response: "[]")

    let buckets = try await analytics.listBuckets(
      options: BucketListOptions(limit: 5, sortBy: .name, order: .ascending))

    #expect(buckets.isEmpty)
    #expect(
      sent.value.map(\.request.path) == [
        "/storage/v1/iceberg/bucket?limit=5&sortColumn=name&sortOrder=asc"
      ])
  }

  @Test
  func deleteBucketEncodesTheName() async throws {
    let sent = LockIsolated<[Sent]>([])
    let analytics = Self.makeAnalytics(sent: sent, response: #"{"message":"Successfully deleted"}"#)

    try await analytics.deleteBucket("a b")

    #expect(sent.value.map(\.request.method) == [.delete])
    #expect(sent.value.map(\.request.path) == ["/storage/v1/iceberg/bucket/a%20b"])
  }

  @Test
  func anIcebergErrorBodyBecomesAStorageError() async throws {
    let analytics = Self.makeAnalytics(
      status: .forbidden,
      response:
        #"{"error":{"message":"Forbidden","type":"ForbiddenException","code":403}}"#)

    let error = await #expect(throws: StorageError.self) {
      _ = try await analytics.listBuckets()
    }
    #expect(error?.message == "Forbidden")
    #expect(error?.response?.statusCode == 403)
  }
}
