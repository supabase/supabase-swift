//
//  ObjectListingTests.swift
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

@Suite
struct ObjectListingTests {
  /// A bucket whose transport answers each request with the next of `responses` and records the
  /// request bodies.
  static func makeBucket(
    bodies: LockIsolated<[String]> = .init([]),
    status: HTTPResponse.Status = .ok,
    responses: [String]
  ) -> StorageBucket {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { request, body in
            #expect(request.method == .post)
            #expect(request.path == "/storage/v1/object/list-v2/bucket")
            let sent = try await Data(collecting: try #require(body), upTo: .max)
            let index = bodies.withValue {
              $0.append(String(decoding: sent, as: UTF8.self))
              return $0.count - 1
            }
            return (
              HTTPResponse(status: status, headerFields: [.contentType: "application/json"]),
              HTTPBody(Data(responses[index].utf8))
            )
          }))
    )
    .from("bucket")
  }

  static let firstPage = #"""
    {"hasNext":true,"nextCursor":"c1","folders":[{"name":"2026/a/"}],
     "objects":[{"name":"2026/x.png","id":"8B1F9F4E-2C61-4E3A-9D53-0F1D2B4C6A7E"}]}
    """#

  static let lastPage = #"""
    {"hasNext":false,"folders":[],
     "objects":[{"name":"2026/y.png","id":"5C6E2B1A-7D3F-4A9B-8E21-3B4C5D6E7F80"}]}
    """#

  @Test
  func pagesFollowTheCursorToTheEndWithTheSameOptions() async throws {
    let bodies = LockIsolated<[String]>([])
    let bucket = Self.makeBucket(bodies: bodies, responses: [Self.firstPage, Self.lastPage])

    var pages: [ObjectListing.Page] = []
    for try await page in bucket.objects(
      prefix: "2026/", options: ObjectListingOptions(pageSize: 1, sortBy: .createdAt)
    ).pages {
      pages.append(page)
    }

    #expect(pages.map(\.objects).map { $0.map(\.name) } == [["2026/x.png"], ["2026/y.png"]])
    #expect(pages.map(\.folders) == [["2026/a/"], []])
    #expect(pages.map(\.hasNext) == [true, false])
    #expect(
      bodies.value == [
        #"{"limit":1,"prefix":"2026\/","sortBy":{"column":"created_at","order":"asc"},"with_delimiter":true}"#,
        #"{"cursor":"c1","limit":1,"prefix":"2026\/","sortBy":{"column":"created_at","order":"asc"},"with_delimiter":true}"#,
      ])
  }

  @Test
  func iteratingYieldsTheObjectsOfEveryPage() async throws {
    let bucket = Self.makeBucket(responses: [Self.firstPage, Self.lastPage])

    var names: [String] = []
    for try await object in bucket.objects(prefix: "2026/") {
      names.append(object.name)
    }

    #expect(names == ["2026/x.png", "2026/y.png"])
  }

  @Test
  func stopsWhenHasNextIsFalseEvenWithACursor() async throws {
    let bodies = LockIsolated<[String]>([])
    let bucket = Self.makeBucket(
      bodies: bodies, responses: [#"{"hasNext":false,"nextCursor":"stale","objects":[]}"#])

    var count = 0
    for try await _ in bucket.objects().pages { count += 1 }

    #expect(count == 1)
    #expect(bodies.value.count == 1)
  }

  @Test
  func sendsTheFlatListingAndFilters() async throws {
    let bodies = LockIsolated<[String]>([])
    let bucket = Self.makeBucket(bodies: bodies, responses: [#"{"hasNext":false,"objects":[]}"#])

    _ = try await bucket.objects(
      prefix: "//a//b",
      options: ObjectListingOptions(
        delimited: false, order: .descending, exactMatch: true, versions: .only,
        deleteMarkers: .include)
    ).page()

    #expect(
      bodies.value == [
        #"{"deleteMarkers":"include","exactMatch":true,"noncurrentVersions":"only","prefix":"a\/b","sortBy":{"column":"name","order":"desc"},"with_delimiter":false}"#
      ])
  }

  @Test
  func pageAfterSendsTheCursor() async throws {
    let bodies = LockIsolated<[String]>([])
    let bucket = Self.makeBucket(bodies: bodies, responses: [Self.lastPage])

    let page = try await bucket.objects().page(after: "c9")

    #expect(page.nextCursor == nil)
    #expect(bodies.value == [#"{"cursor":"c9","prefix":"","with_delimiter":true}"#])
  }

  @Test
  func anOldProjectThrowsFeatureNotEnabled() async throws {
    let bucket = Self.makeBucket(
      status: .badRequest,
      responses: [
        #"{"statusCode":"400","error":"FeatureNotEnabled","code":"FeatureNotEnabled","message":"not enabled"}"#
      ])

    let error = await #expect(throws: StorageError.self) {
      for try await _ in bucket.objects() {}
    }
    #expect(error?.code == .featureNotEnabled)
  }

  @Test
  func aDotSegmentThrowsWhenIterated() async throws {
    let bucket = Self.makeBucket(responses: [])

    let error = await #expect(throws: StorageError.self) {
      _ = try await bucket.objects(prefix: "a/../b").page()
    }
    #expect(error?.kind == .invalidRequest)
  }
}
