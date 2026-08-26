//
//  HTTPRequestBuilderTests.swift
//  HTTPRuntime
//
//  Created by Guilherme Souza on 25/08/26.
//

import Foundation
import HTTPTypes
import Testing

@testable import HTTPRuntime

@Suite
struct HTTPRequestBuilderTests {
  // Query values stay inside the unreserved set on purpose. Whether
  // `URLComponents` and `CFURLGetBytes` percent-encode a sub-delimiter such as
  // `*` is not what these tests are pinning down.
  @Test
  func buildPreservesQueryString() throws {
    var builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "https://example.com")!, path: "/rest/v1/todos")
    builder.addQuery("select", "name")
    builder.addQuery("id", "eq.1")
    let request = try builder.build()
    #expect(request.path == "/rest/v1/todos?select=name&id=eq.1")
  }

  @Test
  func buildPreservesRepeatedQueryKeys() throws {
    var builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "https://example.com")!, path: "/x")
    builder.addQuery("tag", ["a", "b"])
    let request = try builder.build()
    #expect(request.path == "/x?tag=a&tag=b")
  }

  @Test
  func buildPreservesNonDefaultPort() throws {
    let builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "http://127.0.0.1:54321")!, path: "/auth/v1/token")
    let request = try builder.build()
    #expect(request.authority == "127.0.0.1:54321")
  }

  @Test
  func buildPreservesGreedyPathSlashes() throws {
    let builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "https://example.com")!,
      path: "/storage/v1/object/bucket/a/b/c.txt")
    let request = try builder.build()
    #expect(request.path == "/storage/v1/object/bucket/a/b/c.txt")
  }

  @Test
  func addHeaderAppendsToExistingValue() throws {
    var builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "https://example.com")!, path: "/x")
    builder.addHeader(.prefer, value: "returning=minimal")
    builder.addHeader(.prefer, value: "count=exact")
    let request = try builder.build()
    #expect(request.headerFields[.prefer] == "returning=minimal,count=exact")
  }

  @Test
  func addHeaderReplacesMatchingDirectiveKey() throws {
    var builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "https://example.com")!, path: "/x")
    builder.addHeader(.prefer, value: "count=exact")
    builder.addHeader(.prefer, value: "returning=minimal")
    builder.addHeader(.prefer, value: "count=planned")
    let request = try builder.build()
    #expect(request.headerFields[.prefer] == "count=planned,returning=minimal")
  }

  @Test
  func addHeaderSetsWhenAbsent() throws {
    var builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "https://example.com")!, path: "/x")
    builder.addHeader(.prefer, value: "returning=minimal")
    let request = try builder.build()
    #expect(request.headerFields[.prefer] == "returning=minimal")
  }

  @Test
  func addHeaderIgnoresNilValue() throws {
    var builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "https://example.com")!, path: "/x")
    builder.addHeader(.prefer, value: "returning=minimal")
    builder.addHeader(.prefer, value: nil)
    let request = try builder.build()
    #expect(request.headerFields[.prefer] == "returning=minimal")
  }

  // A schemeless base URL clears both `.invalidURL` guards in `build()` —
  // `URLComponents` parses it and hands back a non-nil relative URL — and then
  // aborts the process inside `HTTPTypesFoundation`. This must throw.
  @Test
  func buildRejectsASchemelessBaseURL() {
    let builder = HTTPRequestBuilder(
      method: .get, baseURL: URL(string: "example.com")!, path: "/x")
    #expect(throws: HTTPRuntimeError.self) { try builder.build() }
  }
}
