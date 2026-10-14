//
//  VectorListingTests.swift
//  Storage
//
//  Created by Guilherme Souza on 14/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@_spi(Experimental) @testable import Storage

@Suite
struct VectorListingTests {
  /// A vectors client whose transport answers each request with the next of `responses` and
  /// records the request bodies.
  static func makeVectors(bodies: LockIsolated<[String]> = .init([]), responses: [String])
    -> StorageVectorsClient
  {
    StorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: "http://localhost:54321/storage/v1")!,
        headers: [:],
        http: .init(
          transport: ClosureTransport { _, body in
            let sent = try await Data(collecting: try #require(body), upTo: .max)
            let index = bodies.withValue {
              $0.append(String(decoding: sent, as: UTF8.self))
              return $0.count - 1
            }
            return (
              HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
              HTTPBody(Data(responses[index].utf8))
            )
          }))
    )
    .vectors
  }

  @Test
  func listBucketsFollowsNextTokenAcrossPages() async throws {
    let bodies = LockIsolated<[String]>([])
    let vectors = Self.makeVectors(
      bodies: bodies,
      responses: [
        #"{"vectorBuckets":[{"vectorBucketName":"a","creationTime":1730000000}],"nextToken":"t1"}"#,
        #"{"vectorBuckets":[{"vectorBucketName":"b"}]}"#,
      ])

    var buckets: [VectorBucket] = []
    for try await bucket in vectors.listBuckets(prefix: "x", maxResults: 1) {
      buckets.append(bucket)
    }

    #expect(buckets.map(\.vectorBucketName) == ["a", "b"])
    #expect(buckets.first?.creationTime == Date(timeIntervalSince1970: 1_730_000_000))
    #expect(
      bodies.value == [
        #"{"maxResults":1,"prefix":"x"}"#,
        #"{"maxResults":1,"nextToken":"t1","prefix":"x"}"#,
      ])
  }

  @Test
  func listIndexesPagesEndWithoutNextToken() async throws {
    let vectors = Self.makeVectors(responses: [
      #"{"indexes":[{"indexName":"i1","vectorBucketName":"b"}],"nextToken":"t1"}"#,
      #"{"indexes":[{"indexName":"i2","vectorBucketName":"b"}]}"#,
    ])

    var pages: [ListVectorIndexesResponse] = []
    for try await page in vectors.from("b").listIndexes().pages {
      pages.append(page)
    }

    #expect(pages.map { $0.indexes.map(\.indexName) } == [["i1"], ["i2"]])
    #expect(pages.map(\.nextToken) == ["t1", nil])
  }

  @Test
  func listVectorsPageAfterSendsTheToken() async throws {
    let bodies = LockIsolated<[String]>([])
    let vectors = Self.makeVectors(bodies: bodies, responses: [#"{"vectors":[{"key":"k"}]}"#])

    let page = try await vectors.from("b").index("i").listVectors().page(after: "t9")

    #expect(page.vectors.map(\.key) == ["k"])
    #expect(
      bodies.value == [
        #"{"indexName":"i","nextToken":"t9","returnData":false,"returnMetadata":false,"vectorBucketName":"b"}"#
      ])
  }
}
