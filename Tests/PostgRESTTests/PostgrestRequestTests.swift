//
//  PostgrestRequestTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import HTTPTypes
import Testing

@testable import PostgREST

@Suite
struct PostgrestRequestTests {
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var id: Int
    }
  }

  private let configuration = PostgrestClient.Configuration(
    url: URL(string: "https://example.supabase.co")!)

  private func accept(_ accept: String?) -> String? {
    var request = PostgrestRequest(relation: "todos")
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
  func makeRequestSeedsTheClientHeaders() {
    let client = PostgrestClient(
      url: URL(string: "https://example.supabase.co")!, headers: ["apikey": "key"])
    let request = client.makeRequest("todos")
    #expect(request.headerFields[HTTPField.Name("apikey")!] == "key")
  }

  @Test
  func aRequestHeaderReplacesTheClientHeader() {
    let client = PostgrestClient(
      url: URL(string: "https://example.supabase.co")!, headers: ["Prefer": "tx=rollback"])
    var request = client.makeRequest("todos")
    request.headerFields[.prefer] = "count=exact"
    #expect(request.httpRequest(for: client.configuration).headerFields[.prefer] == "count=exact")
  }

  @Test
  func aClientHeaderRemovedFromTheRequestStaysRemoved() {
    let client = PostgrestClient(
      url: URL(string: "https://example.supabase.co")!, headers: ["apikey": "key"])
    var request = client.makeRequest("todos")
    request.headerFields[HTTPField.Name("apikey")!] = nil
    let sent = request.httpRequest(for: client.configuration)
    #expect(sent.headerFields[HTTPField.Name("apikey")!] == nil)
  }

  @Test
  func rpcParamsAreNotReplacedByALaterTransform() async throws {
    let capture = QueryCapture()
    try await capture.client.rpc("f", params: ["limit": 5], get: true).limit(10).execute()
    #expect(capture.query == "limit=5&limit=10")
  }

  @Test
  func nullOnNoRowsReportsADecodingError() async throws {
    let capture = QueryCapture(
      body: #"""
        {"code":"PGRST116","message":"Cannot coerce the result to a single JSON object",\#
        "details":"The result contains 0 rows","hint":null}
        """#,
      status: .notAcceptable
    )
    var request = capture.client.makeRequest("todos")
    request.nullOnNoRows = true
    let error = await #expect(throws: PostgrestError.self) {
      _ = try await request.execute(on: capture.client) {
        try JSONDecoder().decode(Int.self, from: $0)
      }
    }
    #expect(error?.kind == .decoding)
  }

  @Test
  func typedPreferMergesWithTheClientPrefer() async throws {
    let capture = QueryCapture(headers: ["Prefer": "tx=rollback"])
    try await capture.client.from(Todo.self).delete().all().execute(count: .exact)
    let prefer = try #require(capture.header("Prefer"))
    #expect(prefer.contains("tx=rollback"))
    #expect(prefer.contains("count=exact"))
    #expect(prefer.contains("return=minimal"))
  }

  @Test
  func nullOnNoRowsDecodesNull() async throws {
    let capture = QueryCapture(
      body: #"""
        {"code":"PGRST116","message":"Cannot coerce the result to a single JSON object",\#
        "details":"The result contains 0 rows","hint":null}
        """#,
      status: .notAcceptable
    )
    var request = capture.client.makeRequest("todos")
    request.nullOnNoRows = true
    let response = try await request.execute(on: capture.client) {
      try JSONDecoder().decode(Int?.self, from: $0)
    }
    #expect(response.value == nil)
  }

  @Test
  func withoutNullOnNoRowsPGRST116Throws() async throws {
    let capture = QueryCapture(
      body: #"""
        {"code":"PGRST116","message":"Cannot coerce the result to a single JSON object",\#
        "details":"The result contains 0 rows","hint":null}
        """#,
      status: .notAcceptable
    )
    let request = capture.client.makeRequest("todos")
    await #expect(throws: PostgrestError.self) {
      _ = try await request.execute(on: capture.client) {
        try JSONDecoder().decode(Int?.self, from: $0)
      }
    }
  }
}
