//
//  HTTPTransportStubTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import HTTPRuntime
import Testing

@testable import HTTPRuntimeTestHelpers

@Suite
struct HTTPTransportStubTests {
  @Test
  func matchesAndReturnsStubbedResponse() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/a", status: 201, headers: ["X": "1"]) { .string("hi") }
    ])
    let response = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), uploadProgress: nil)
    #expect(response.head.status == 201)
    #expect(response.head.headers == ["X": "1"])
    #expect(response.body == Data("hi".utf8))
  }

  @Test
  func consumesStubsInOrder() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/a") { .string("first") },
      .get("https://example.com/b") { .string("second") },
    ])
    let first = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), uploadProgress: nil)
    let second = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/b")!), uploadProgress: nil)
    #expect(first.body == Data("first".utf8))
    #expect(second.body == Data("second".utf8))
  }

  @Test
  func mismatchRecordsIssueAndThrows() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/expected") { .empty }
    ])
    await withKnownIssue {
      _ = try await transport.send(
        HTTPRequest(method: .post, url: URL(string: "https://example.com/actual")!),
        uploadProgress: nil)
    }
  }

  @Test
  func exhaustedQueueRecordsIssueAndThrows() async throws {
    let transport = HTTPTransportStub(stubs: [])
    await withKnownIssue {
      _ = try await transport.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!), uploadProgress: nil)
    }
  }

  @Test
  func assertAllConsumedRecordsIssueForLeftoverStubs() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/never-called") { .empty }
    ])
    await withKnownIssue {
      await transport.assertAllConsumed()
    }
  }

  @Test
  func currentOutsideScopeRecordsIssueAndReturnsUsableTransport() async throws {
    await withKnownIssue {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!), uploadProgress: nil)
    }
  }

  @Test
  func streamYieldsStubbedChunks() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/a") { .data(Data("chunk".utf8)) }
    ])
    let responseStream = try await transport.stream(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!))
    var collected = Data()
    for try await chunk in responseStream.body { collected.append(chunk) }
    #expect(collected == Data("chunk".utf8))
  }
}
