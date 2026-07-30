//
//  HTTPStubTraitTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import HTTPRuntime
import Testing

@testable import HTTPRuntimeTestHelpers

@Suite
struct HTTPStubTraitTests {
  @Test(.http(stubs: [.get("https://example.com/x", status: 200) { .string("ok") }]))
  func bindsCurrentForTestBody() async throws {
    let response = try await HTTPTransportStub.current.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!), uploadProgress: nil)
    #expect(response.body == Data("ok".utf8))
  }

  @Test
  func leftoverStubRecordsIssueAtScopeExit() async throws {
    let trait = http(stubs: [.get("https://example.com/never-called") { .empty }])
    await withKnownIssue {
      try await trait.provideScope(for: Test.current!, testCase: Test.Case.current) {
        // Deliberately consume nothing.
      }
    }
  }

  @Test
  func suiteAndTestStubsMergeInOrder() async throws {
    let suiteLevelTrait = http(stubs: [.get("https://example.com/first") { .string("1") }])
    let testLevelTrait = http(stubs: [.get("https://example.com/second") { .string("2") }])
    try await suiteLevelTrait.provideScope(for: Test.current!, testCase: Test.Case.current) {
      try await testLevelTrait.provideScope(for: Test.current!, testCase: Test.Case.current) {
        let first = try await HTTPTransportStub.current.send(
          HTTPRequest(method: .get, url: URL(string: "https://example.com/first")!),
          uploadProgress: nil)
        let second = try await HTTPTransportStub.current.send(
          HTTPRequest(method: .get, url: URL(string: "https://example.com/second")!),
          uploadProgress: nil)
        #expect(first.body == Data("1".utf8))
        #expect(second.body == Data("2".utf8))
      }
    }
  }
}
