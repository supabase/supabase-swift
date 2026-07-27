//
//  TypedBuildersTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/06/25.
//

import Foundation
import InlineSnapshotTesting
import Mocker
import PostgrestMacros
import TestHelpers
import Testing

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Test fixtures

/// A minimal hand-written TableRepresentable conformance for testing — does not use
/// the @Table macro so these tests have no macro dependency.
struct TestTodo: TableRepresentable, Decodable {
  var id: UUID
  var title: String
  var isComplete: Bool

  struct Insert: Encodable {
    var title: String
    var isComplete: Bool
  }
  struct Update: Encodable {
    var title: String?
    var isComplete: Bool?
  }

  static let tableName = "todos"
  static let schema = "public"
  static let selectString = "id,title,is_complete"

  static func columnName<V>(for keyPath: KeyPath<TestTodo, V>) -> String {
    let erased = keyPath as AnyKeyPath
    if erased == \TestTodo.id { return "id" }
    if erased == \TestTodo.title { return "title" }
    if erased == \TestTodo.isComplete { return "is_complete" }
    preconditionFailure("unknown keyPath")
  }
}

/// A projection type for selecting a subset of columns.
struct TodoSummary: SelectionRepresentable, Decodable {
  var id: UUID
  var title: String

  static let selectString = "id,title"
}

// MARK: - Helpers

private func makeClient() -> PostgrestClient {
  let sessionConfiguration = URLSessionConfiguration.default
  sessionConfiguration.protocolClasses = [MockingURLProtocol.self]
  let session = URLSession(configuration: sessionConfiguration)

  return PostgrestClient(
    url: URL(string: "http://localhost:54321/rest/v1")!,
    headers: [
      "apikey":
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    ],
    logger: nil,
    fetch: { try await session.data(for: $0) }
  )
}

private let baseURL = URL(string: "http://localhost:54321/rest/v1")!
private let todosURL = baseURL.appendingPathComponent("todos")

// MARK: - Compile-verification tests (no network needed)

@Suite("TypedPostgrestQueryBuilder — type inference")
struct TypedPostgrestQueryBuilderTypeTests {

  @Test("select() returns TypedPostgrestFilterBuilder<TestTodo, TestTodo>")
  func selectDefaultType() {
    let client = makeClient()
    let builder: TypedPostgrestFilterBuilder<TestTodo, TestTodo> =
      client.from(TestTodo.self).select()
    // If the above compiles, the type inference is correct.
    _ = builder
  }

  @Test("select(TodoSummary.self) returns TypedPostgrestFilterBuilder<TestTodo, TodoSummary>")
  func selectProjectionType() {
    let client = makeClient()
    let builder: TypedPostgrestFilterBuilder<TestTodo, TodoSummary> =
      client.from(TestTodo.self).select(TodoSummary.self)
    _ = builder
  }

  @Test("filter chain compiles — eq then order then limit")
  func filterChainCompiles() {
    let client = makeClient()
    let builder =
      client.from(TestTodo.self)
      .select()
      .eq(\.isComplete, value: false)
      .limit(10)
    _ = builder
  }

  @Test("single() returns TypedSingleResultBuilder")
  func singleReturnType() {
    let client = makeClient()
    let builder: TypedSingleResultBuilder<TestTodo, TestTodo> =
      client.from(TestTodo.self).select().single()
    _ = builder
  }

  @Test("order() returns TypedPostgrestTransformBuilder")
  func orderReturnType() {
    let client = makeClient()
    let builder: TypedPostgrestTransformBuilder<TestTodo, TestTodo> =
      client.from(TestTodo.self).select().order(\.title)
    _ = builder
  }
}

// MARK: - URL snapshot tests (verify column name translation in the HTTP request)

@Suite("TypedPostgrestFilterBuilder — KeyPath to column name translation")
struct TypedPostgrestFilterBuilderSnapshotTests {

  @Test("eq on Bool KeyPath translates to snake_case column in URL")
  func eqBoolKeyPathTranslation() async throws {
    Mock(
      url: todosURL,
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/todos?is_complete=eq.false&select=id%2Ctitle%2Cis_complete"
      """#
    }
    .register()

    let client = makeClient()
    _ = try await client.from(TestTodo.self)
      .select()
      .eq(\.isComplete, value: false)
      .execute()
  }

  @Test("select with projection uses SelectionRepresentable.selectString")
  func selectProjectionUsesSelectString() async throws {
    Mock(
      url: todosURL,
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/todos?select=id%2Ctitle"
      """#
    }
    .register()

    let client = makeClient()
    _ = try await client.from(TestTodo.self)
      .select(TodoSummary.self)
      .execute()
  }

  @Test("or filter translates column expression to URL query")
  func orFilter() async throws {
    Mock(
      url: todosURL,
      ignoreQuery: true,
      statusCode: 200,
      data: [.get: Data("[]".utf8)]
    )
    .snapshotRequest {
      #"""
      curl \
      	--header "Accept: application/json" \
      	--header "Content-Type: application/json" \
      	--header "X-Client-Info: postgrest-swift/0.0.0" \
      	--header "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" \
      	"http://localhost:54321/rest/v1/todos?or=(is_complete.eq.true,title.eq.Buy+milk)&select=id%2Ctitle%2Cis_complete"
      """#
    }
    .register()

    let client = makeClient()
    _ = try await client.from(TestTodo.self)
      .select()
      .or("is_complete.eq.true,title.eq.Buy milk")
      .execute()
  }
}
