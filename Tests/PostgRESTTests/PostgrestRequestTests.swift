//
//  PostgrestRequestTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import HTTPTypes
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestRequestTests {
  struct Todo: _PostgrestWritableRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var id: Int
    }
  }

  private let configuration = PostgrestClient.Configuration(
    url: URL(string: "https://example.supabase.co")!)

  private func accept(_ accept: String?) -> String? {
    var request = _PostgrestRequest(relation: "todos")
    request.stripsNulls = true
    if let accept {
      request.headerFields[.accept] = accept
    }
    return request.httpRequest(for: configuration).headerFields[.accept]
  }

  @Test
  func stripsNullsUsesTheArrayMediaTypeByDefault() {
    #expect(accept(nil) == "application/vnd.pgrst.array+json;nulls=stripped")
    #expect(accept("application/json") == "application/vnd.pgrst.array+json;nulls=stripped")
  }

  @Test
  func stripsNullsKeepsTheObjectMediaType() {
    #expect(
      accept("application/vnd.pgrst.object+json")
        == "application/vnd.pgrst.object+json;nulls=stripped")
  }

  @Test
  func stripsNullsLeavesOtherMediaTypesAlone() {
    #expect(accept("text/csv") == "text/csv")
    #expect(accept("application/geo+json") == "application/geo+json")
  }

  @Test
  func makeRequestSeedsTheClientHeaders() throws {
    let client = try PostgrestClient(
      configuration: .init(
        url: URL(string: "https://example.supabase.co")!,
        headers: [.apikey: "key"]
      )
    )
    let request = client.makeRequest("todos")
    #expect(request.headerFields[.apikey] == "key")
  }

  @Test
  func aRequestHeaderReplacesTheClientHeader() throws {
    let client = try PostgrestClient(
      configuration: .init(
        url: URL(string: "https://example.supabase.co")!,
        headers: [HTTPField.Name("Prefer")!: "tx=rollback"]
      )
    )
    var request = client.makeRequest("todos")
    request.headerFields[.prefer] = "count=exact"
    #expect(request.httpRequest(for: client.configuration).headerFields[.prefer] == "count=exact")
  }

  @Test
  func aClientHeaderRemovedFromTheRequestStaysRemoved() throws {
    let client = try PostgrestClient(
      configuration: .init(
        url: URL(string: "https://example.supabase.co")!,
        headers: [.apikey: "key"]
      )
    )
    var request = client.makeRequest("todos")
    request.headerFields[.apikey] = nil
    let sent = request.httpRequest(for: client.configuration)
    #expect(sent.headerFields[.apikey] == nil)
  }

  @Test
  func rpcParamsAreNotReplacedByALaterTransform() async throws {
    let capture = try QueryCapture()
    try await capture.client.rpc("f", params: ["limit": 5], get: true).limit(10).execute()
    #expect(capture.query == "limit=5&limit=10")
  }

  @Test
  func atMostOneRowReportsADecodingErrorForNoRowAndANonOptionalType() async throws {
    let capture = try QueryCapture(body: "[]")
    var request = capture.client.makeRequest("todos")
    request.expectsAtMostOneRow = true
    let error = await #expect(throws: PostgrestError.self) {
      _ = try await request.execute(on: capture.client) {
        try JSONDecoder().decode(Int.self, from: $0)
      }
    }
    #expect(error?.kind == .decoding)
  }

  @Test
  func typedPreferMergesWithTheClientPrefer() async throws {
    let capture = try QueryCapture(headers: [HTTPField.Name("Prefer")!: "tx=rollback"])
    try await capture.client.from(Todo.self).delete().all().execute(count: .exact)
    let prefer = try #require(capture.header("Prefer"))
    #expect(prefer.contains("tx=rollback"))
    #expect(prefer.contains("count=exact"))
    #expect(prefer.contains("return=minimal"))
  }

  @Test
  func atMostOneRowDecodesNullForNoRow() async throws {
    let capture = try QueryCapture(body: " [ ] ")
    var request = capture.client.makeRequest("todos")
    request.expectsAtMostOneRow = true
    let response = try await request.execute(on: capture.client) {
      try JSONDecoder().decode(Int?.self, from: $0)
    }
    #expect(response.value == nil)
    #expect(response.status == .ok)
    #expect(String(decoding: response.body, as: UTF8.self) == "null")
  }

  @Test
  func atMostOneRowKeepsTheBytesOfTheOnlyRow() async throws {
    let row = #"{"amount":12345678901234567890.123456789}"#
    let capture = try QueryCapture(body: "\n[\n  \(row)\n]\n")
    var request = capture.client.makeRequest("todos")
    request.expectsAtMostOneRow = true
    let response = try await request.execute(on: capture.client) { $0 }
    #expect(String(decoding: response.body, as: UTF8.self) == row)
  }

  @Test
  func atMostOneRowCountsRowsNotNestedArrays() async throws {
    let capture = try QueryCapture(body: #"[{"tags":["a","b",","],"note":"],["}]"#)
    var request = capture.client.makeRequest("todos")
    request.expectsAtMostOneRow = true
    let response = try await request.execute(on: capture.client) { $0 }
    #expect(
      String(decoding: response.body, as: UTF8.self) == #"{"tags":["a","b",","],"note":"],["}"#)
  }

  @Test
  func atMostOneRowLeavesABodyThatIsNotAnArray() async throws {
    let capture = try QueryCapture(body: "")
    var request = capture.client.makeRequest("todos")
    request.method = .head
    request.expectsAtMostOneRow = true
    let response = try await request.execute(on: capture.client) { $0 }
    #expect(response.body.isEmpty)
  }

  @Test
  func withoutAtMostOneRowAnArrayIsLeftAsItIs() async throws {
    let capture = try QueryCapture(body: "[1,2]")
    let request = capture.client.makeRequest("todos")
    let response = try await request.execute(on: capture.client) {
      try JSONDecoder().decode([Int].self, from: $0)
    }
    #expect(response.value == [1, 2])
  }
}
