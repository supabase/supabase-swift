//
//  AssertHTTPRequestsTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Foundation
import HTTPRuntime
import Testing

@testable import HTTPRuntimeTestHelpers

@Suite
struct AssertHTTPRequestsTests {
  @Test(
    .http(stubs: [
      .get("https://example.com/a") { .empty },
      .get("https://example.com/b") { .empty },
      .get("https://example.com/c") { .empty },
    ]))
  func onlyCapturesRequestsMadeDuringItsOwnOperation() async throws {
    // Fires one request *before* any assertHTTPRequests call — must not leak
    // into the slice captured below.
    _ = try await HTTPTransportStub.current.send(
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), uploadProgress: nil)

    try await assertHTTPRequests {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/b")!), uploadProgress: nil)
    } matches: {
      #"""
      curl \
      	"https://example.com/b"
      """#
    }

    // A second call must only see requests made after the first one returned.
    try await assertHTTPRequests {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/c")!), uploadProgress: nil)
    } matches: {
      #"""
      curl \
      	"https://example.com/c"
      """#
    }
  }

  @Test(
    .http(stubs: [
      .get("https://example.com/first") { .empty },
      .post("https://example.com/second") { .empty },
    ]))
  func rendersMultipleRequestsJoinedByBlankLine() async throws {
    try await assertHTTPRequests {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/first")!),
        uploadProgress: nil)
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .post, url: URL(string: "https://example.com/second")!),
        uploadProgress: nil)
    } matches: {
      #"""
      curl \
      	"https://example.com/first"

      curl \
      	--request POST \
      	"https://example.com/second"
      """#
    }
  }
}
