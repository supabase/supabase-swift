//
//  HTTPTransportStubTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import HTTPRuntime
import HTTPTypes
import HTTPTypesFoundation
import Testing

@testable import HTTPRuntimeTestHelpers

extension HTTPField.Name {
  fileprivate static let xTest = HTTPField.Name("X-Test")!
}

@Suite
struct HTTPTransportStubTests {
  @Test
  func matchesAndReturnsStubbedResponse() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/a", status: 201, headers: [.xTest: "1"]) { .string("hi") }
    ])
    let response = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), body: nil,
      uploadProgress: nil)
    #expect(response.head.status == 201)
    #expect(response.head.headerFields == [.xTest: "1"])
    #expect(response.body == Data("hi".utf8))
  }

  @Test
  func consumesStubsInOrder() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/a") { .string("first") },
      .get("https://example.com/b") { .string("second") },
    ])
    let first = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), body: nil,
      uploadProgress: nil)
    let second = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/b")!), body: nil,
      uploadProgress: nil)
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
        body: nil, uploadProgress: nil)
    }
  }

  @Test
  func exhaustedQueueRecordsIssueAndThrows() async throws {
    let transport = HTTPTransportStub(stubs: [])
    await withKnownIssue {
      _ = try await transport.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!), body: nil,
        uploadProgress: nil)
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
        HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!), body: nil,
        uploadProgress: nil)
    }
  }

  @Test
  func streamYieldsStubbedChunks() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com/a") { .data(Data("chunk".utf8)) }
    ])
    let responseStream = try await transport.stream(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), body: nil)
    var collected = Data()
    for try await chunk in responseStream.body { collected.append(chunk) }
    #expect(collected == Data("chunk".utf8))
  }

  // A request's URL is rebuilt from its pseudo header fields, which turns an
  // empty path into `/`. Without normalizing the stub's URL the same way, a
  // host-only stub could never match, and the mismatch message would show two
  // strings differing only by a slash the test author never typed.
  @Test
  func hostOnlyStubMatchesARootPathRequest() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com") { .string("root") }
    ])
    let response = try await transport.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com")!), body: nil,
      uploadProgress: nil)
    #expect(response.body == Data("root".utf8))
  }

  // The normalization must not make matching sloppy: a genuinely different path
  // still has to fail.
  @Test
  func hostOnlyStubStillRejectsANonRootPath() async throws {
    let transport = HTTPTransportStub(stubs: [
      .get("https://example.com") { .string("root") }
    ])
    await withKnownIssue {
      _ = try await transport.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/x")!), body: nil,
        uploadProgress: nil)
    }
  }

  @Test
  func recordsTheBodyAlongsideTheRequest() async throws {
    let transport = HTTPTransportStub(stubs: [
      .post("https://example.com/a") { .empty }
    ])
    let payload = Data(#"{"a":1}"#.utf8)
    _ = try await transport.send(
      HTTPRequest(method: .post, url: URL(string: "https://example.com/a")!),
      body: .data(payload), uploadProgress: nil)

    let recorded = await transport.requests(since: 0)
    #expect(recorded.count == 1)
    guard case .data(let recordedBody) = recorded[0].body else {
      Issue.record("expected a .data body")
      return
    }
    #expect(recordedBody == payload)
  }
}
