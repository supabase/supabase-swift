//
//  AssertHTTPRequestsTests.swift
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
      HTTPRequest(method: .get, url: URL(string: "https://example.com/a")!), body: nil,
      uploadProgress: nil)

    try await assertHTTPRequests {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/b")!), body: nil,
        uploadProgress: nil)
    } matches: {
      #"""
      curl \
      	"https://example.com/b"
      """#
    }

    // A second call must only see requests made after the first one returned.
    try await assertHTTPRequests {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .get, url: URL(string: "https://example.com/c")!), body: nil,
        uploadProgress: nil)
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
        body: nil, uploadProgress: nil)
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .post, url: URL(string: "https://example.com/second")!),
        body: nil, uploadProgress: nil)
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

  @Test(.http(stubs: [.post("https://example.com/create") { .empty }]))
  func rendersTheRequestBodyAsData() async throws {
    try await assertHTTPRequests {
      _ = try await HTTPTransportStub.current.send(
        HTTPRequest(method: .post, url: URL(string: "https://example.com/create")!),
        body: .data(Data(#"{"a":1}"#.utf8)), uploadProgress: nil)
    } matches: {
      #"""
      curl \
      	--request POST \
      	--data "{\"a\":1}" \
      	"https://example.com/create"
      """#
    }
  }
}
