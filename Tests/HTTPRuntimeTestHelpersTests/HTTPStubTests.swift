//
//  HTTPStubTests.swift
//  HTTPRuntimeTestHelpers
//
//  Created by Guilherme Souza on 11/07/26.
//
import Testing

@testable import HTTPRuntimeTestHelpers

@Suite
struct HTTPStubTests {
  @Test
  func getBuildsExpectedStub() {
    let stub = HTTPStub.get("https://example.com/x", status: 201, headers: ["X-Test": "1"]) {
      .string("hello")
    }
    #expect(stub.method == .get)
    #expect(stub.url == "https://example.com/x")
    #expect(stub.status == 201)
    #expect(stub.headers == ["X-Test": "1"])
    guard case .string(let value) = stub.body() else {
      Issue.record("expected .string body")
      return
    }
    #expect(value == "hello")
  }

  @Test
  func defaultsToStatus200AndEmptyBody() {
    let stub = HTTPStub.post("https://example.com/y")
    #expect(stub.status == 200)
    #expect(stub.headers.isEmpty)
    guard case .empty = stub.body() else {
      Issue.record("expected .empty body")
      return
    }
  }

  @Test
  func everyVerbFactoryProducesItsMethod() {
    #expect(HTTPStub.get("https://example.com").method == .get)
    #expect(HTTPStub.post("https://example.com").method == .post)
    #expect(HTTPStub.put("https://example.com").method == .put)
    #expect(HTTPStub.patch("https://example.com").method == .patch)
    #expect(HTTPStub.delete("https://example.com").method == .delete)
    #expect(HTTPStub.head("https://example.com").method == .head)
  }
}
