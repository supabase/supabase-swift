//
//  LifecycleTests.swift
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
struct LifecycleTests {
  typealias Sent = BucketRequestTests.Sent

  @Test
  func lifecycleDecodesTheRules() async throws {
    let sent = LockIsolated<[Sent]>([])
    let storage = BucketRequestTests.makeClient(
      sent: sent,
      response: """
        {"rules":[{"id":"r1","status":"Disabled","filter":{},
          "noncurrentVersionExpiration":{"noncurrentDays":7,"newerNoncurrentVersions":3}}]}
        """)

    let configuration = try await storage.lifecycle(forBucket: "docs")

    #expect(
      configuration
        == LifecycleConfiguration(rules: [
          LifecycleRule(
            id: "r1", status: .disabled,
            noncurrentVersionExpiration: NoncurrentVersionExpiration(
              noncurrentDays: 7, newerNoncurrentVersions: 3))
        ]))
    #expect(sent.value.map(\.request.method) == [.get])
    #expect(sent.value.map(\.request.path) == ["/storage/v1/bucket/docs/lifecycle"])
  }

  @Test
  func lifecycleIsNilWithoutAPolicy() async throws {
    let storage = BucketRequestTests.makeClient(
      status: .notFound,
      response:
        #"{"statusCode":"404","code":"NoSuchLifecycleConfiguration","error":"not_found","message":"none"}"#
    )

    #expect(try await storage.lifecycle(forBucket: "docs") == nil)
  }

  @Test
  func lifecycleRethrowsOtherErrors() async throws {
    let storage = BucketRequestTests.makeClient(
      status: .badRequest,
      response: #"{"statusCode":"400","code":"FeatureNotEnabled","error":"x","message":"off"}"#)

    await #expect(throws: StorageError.self) {
      try await storage.lifecycle(forBucket: "docs")
    }
  }

  @Test
  func setLifecycleSendsTheRulesWithAnEmptyFilter() async throws {
    let sent = LockIsolated<[Sent]>([])
    let storage = BucketRequestTests.makeClient(
      sent: sent,
      response: """
        {"rules":[{"id":"gen","status":"Enabled","filter":{},
          "noncurrentVersionExpiration":{"noncurrentDays":30}}]}
        """)

    let stored = try await storage.setLifecycle(
      LifecycleConfiguration(rules: [
        LifecycleRule(noncurrentVersionExpiration: NoncurrentVersionExpiration(noncurrentDays: 30))
      ]),
      forBucket: "docs")

    #expect(stored.rules.map(\.id) == ["gen"])
    #expect(sent.value.map(\.request.method) == [.put])
    #expect(
      sent.value.map(\.body) == [
        #"{"rules":[{"filter":{},"noncurrentVersionExpiration":{"noncurrentDays":30},"status":"Enabled"}]}"#
      ])
  }

  @Test
  func deleteLifecycleSendsDelete() async throws {
    let sent = LockIsolated<[Sent]>([])
    let storage = BucketRequestTests.makeClient(
      sent: sent, response: #"{"message":"Successfully deleted"}"#)

    try await storage.deleteLifecycle(forBucket: "a b")

    #expect(sent.value.map(\.request.method) == [.delete])
    #expect(sent.value.map(\.request.path) == ["/storage/v1/bucket/a%20b/lifecycle"])
  }
}
