//
//  PostgrestRpcTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 07/10/26.
//

import Foundation
import IssueReporting
import Testing

@_spi(Experimental) @testable import PostgREST

/// The typed `rpc(_:)` over hand-written `_PostgrestFunction` conformances, so this target needs
/// no macro import. `from(SearchTodos.self)` does not compile — `SearchTodos` is not a
/// `_PostgrestRelation` — which Swift cannot assert at runtime; everything below is the half it can.
@Suite
struct PostgrestRpcTests {
  struct Todo: _PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"
    var id: Int
    var isDone: Bool

    enum CodingKeys: String, CodingKey {
      case id
      case isDone = "is_done"
    }

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let isDone = _PostgrestColumn<Todo, Bool>("is_done")
    }
    static let columns = Columns()
  }

  struct SearchTodos: _PostgrestFunction {
    typealias Result = [Todo]
    static let functionName = "search_todos"
    var keyword: String
    var limit: Int
    var tags: [String]
  }

  struct CountTodos: _PostgrestFunction {
    typealias Result = Int
    static let functionName = "count_todos"
    var done: Bool
  }

  /// No `Result`, so it defaults to `Void`; no arguments, so it encodes as `{}`.
  struct Ping: _PostgrestFunction {
    static let functionName = "ping"
  }

  enum PrivateSchema: _PostgrestSchema {
    static let name = "private"
  }

  struct Audit: _PostgrestFunction {
    typealias Schema = PrivateSchema
    typealias Result = Int
    static let functionName = "audit"
  }

  /// A conformance that does not encode as an object, which `@Function` can never produce.
  struct Pair: _PostgrestFunction {
    typealias Result = Int
    static let functionName = "pair"
    func encode(to encoder: any Encoder) throws {
      var container = encoder.unkeyedContainer()
      try container.encode(1)
      try container.encode(2)
    }
  }

  private let search = SearchTodos(keyword: "milk", limit: 3, tags: ["a", "b c"])

  @Test
  func postsTheArgumentsAsTheBody() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.rpc(search).execute()
    #expect(capture.httpMethod == "POST")
    #expect(capture.path == "/rpc/search_todos")
    #expect(capture.query == nil)
    #expect(capture.bodyString == #"{"keyword":"milk","limit":3,"tags":["a","b c"]}"#)
    #expect(capture.header("Content-Type") == "application/json")
  }

  /// The arguments render exactly as the untyped `rpc(_:params:get:)` renders them, so the two
  /// spellings produce the same request.
  @Test
  func readOnlySendsAGetWithTheArgumentsInTheQuery() async throws {
    let typed = QueryCapture()
    _ = try await typed.client.rpc(search).readOnly().execute()
    #expect(typed.httpMethod == "GET")
    #expect(typed.bodyString == nil)
    #expect(typed.query == "keyword=milk&limit=3&tags={a,b c}")

    let untyped = QueryCapture()
    _ = try await untyped.client.rpc("search_todos", params: search, get: true).execute()
    #expect(
      Set(typed.query?.split(separator: "&") ?? [])
        == Set(untyped.query?.split(separator: "&") ?? [])
    )
  }

  @Test
  func filtersOrderingAndPagingApplyToTheRows() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.rpc(search)
      .where { $0.isDone.eq(false) }
      .order { $0.id.desc() }
      .limit(5)
      .execute()
    #expect(capture.httpMethod == "POST")
    #expect(capture.query == "is_done=eq.false&order=id.desc&limit=5")
    #expect(capture.bodyString?.contains(#""keyword":"milk""#) == true)
  }

  @Test
  func readOnlyKeepsTheArgumentsAheadOfTheFilters() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.rpc(search).readOnly()
      .rows().where { $0.isDone.eq(false) }.execute()
    #expect(capture.httpMethod == "GET")
    #expect(capture.query == "keyword=milk&limit=3&tags={a,b c}&is_done=eq.false")
  }

  @Test
  func aScalarResultDecodes() async throws {
    let capture = QueryCapture(body: "3")
    let count = try await capture.client.rpc(CountTodos(done: true)).execute().value
    #expect(count == 3)
    #expect(capture.bodyString == #"{"done":true}"#)
  }

  @Test
  func aVoidFunctionIgnoresTheEmptyBody() async throws {
    let capture = QueryCapture(body: "")
    _ = try await capture.client.rpc(Ping()).execute()
    #expect(capture.path == "/rpc/ping")
    #expect(capture.bodyString == "{}")
  }

  @Test
  func theFunctionsSchemaSetsTheProfileHeader() async throws {
    let posted = QueryCapture(body: "1")
    _ = try await posted.client.rpc(Audit()).execute()
    #expect(posted.header("Content-Profile") == "private")

    let read = QueryCapture(body: "1")
    _ = try await read.client.rpc(Audit()).readOnly().execute()
    #expect(read.header("Accept-Profile") == "private")
  }

  @Test
  func aNonObjectArgumentReportsAndStaysAPost() async throws {
    let capture = QueryCapture(body: "1")
    let call = try capture.client.rpc(Pair())
    var readOnly = call
    withExpectedIssue { readOnly = call.readOnly() }
    _ = try await readOnly.execute()
    #expect(capture.httpMethod == "POST")
    #expect(capture.bodyString == "[1,2]")
  }
}
