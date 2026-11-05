//
//  PostgRESTIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 05/11/26.
//

import Foundation
@_spi(Experimental) import Supabase

/// Written out as `@Table("todos")` would expand it. The macro's extension gets main-actor
/// isolated conformances under `.defaultIsolation(MainActor.self)`, which the requirements of
/// `_PostgrestRelation` reject, so the conformances sit on a `nonisolated` declaration. An app
/// that uses the macro in such a module needs the same until the expansion handles it.
nonisolated struct IsolationTodo: _PostgrestWritableRelation, _PostgrestKeyedRelation {
  static let relationName = "todos"
  static let selectString = "id,title,is_done"
  static let primaryKeyColumns = ["id"]

  var id: Int
  var title: String
  var isDone: Bool

  enum CodingKeys: String, CodingKey {
    case id, title
    case isDone = "is_done"
  }

  struct Columns: Sendable {
    let id = _PostgrestColumn<IsolationTodo, Int>("id")
    let title = _PostgrestColumn<IsolationTodo, String>("title")
    let isDone = _PostgrestColumn<IsolationTodo, Bool>("is_done")
  }

  static let columns = Columns()

  struct Draft: Encodable, Sendable {
    var id: Int
    var title: String
    var isDone: Bool

    enum CodingKeys: String, CodingKey {
      case id, title
      case isDone = "is_done"
    }
  }
}

/// A column subset of `IsolationTodo`, written out as `@SelectionOf` would expand it.
nonisolated struct IsolationTodoTitle: _PostgrestSelection {
  typealias Source = IsolationTodo
  static let selectString = "title"

  var title: String
}

/// A function with a result, written out as `@Function("search_todos")` would expand it.
nonisolated struct IsolationSearchTodos: _PostgrestFunction {
  static let functionName = "search_todos"
  typealias Result = [IsolationTodo]

  var keyword: String
}

/// A function without a result, written out as `@Function("reset_todos")` would expand it.
nonisolated struct IsolationResetTodos: _PostgrestFunction {
  static let functionName = "reset_todos"
}

/// Calls every public async PostgREST API from the main actor, since this target compiles with
/// `.defaultIsolation(MainActor.self)`. Nothing here runs: if a call stops compiling, the build
/// fails. `scripts/check-isolation-coverage.sh` checks only the names, so each `execute()`
/// overload and each builder that ends in one is listed by hand.
enum PostgRESTIsolationTests {
  /// A row with a main-actor-isolated `Decodable` conformance.
  struct Row: Decodable {
    var id: Int
  }

  /// A payload with a main-actor-isolated `Encodable` conformance.
  struct Payload: Encodable {
    var title: String
  }

  static func untyped(_ client: PostgrestClient) async throws {
    let payload = Payload(title: "buy milk")

    try await client.from("todos").select().execute()
    let rows: [Row] = try await client.from("todos").select().execute().value
    _ = rows
    let response: PostgrestResponse<[Row]> = try await client.from("todos").select()
      .execute(options: FetchOptions(), decoder: JSONDecoder())
    _ = response
    try await client.from("todos").select(head: true, count: .exact).execute()
    try await client.from("todos").select().eq("id", value: 1).single().execute()
    try await client.from("todos").insert(payload).execute()
    try await client.from("todos").insert([payload], returning: .representation).select().execute()
    try await client.from("todos").upsert(payload, onConflict: "id").execute()
    try await client.from("todos").update(payload).eq("id", value: 1).execute()
    try await client.from("todos").delete().eq("id", value: 1).execute()
    try await client.rpc("reset_todos").execute()
    try await client.rpc("search_todos", params: payload, get: true).execute()
    try await client.rpc("search_todos", params: payload, head: true, count: .exact).execute()
    let result: [Row] = try await client.rpc("search_todos", params: payload).execute().value
    _ = result
  }

  static func typed(_ client: PostgrestClient) async throws {
    let draft = IsolationTodo.Draft(id: 1, title: "buy milk", isDone: false)

    let todos = try await client.from(IsolationTodo.self).select().execute().value
    _ = todos
    try await client.from(IsolationTodo.self).select()
      .where { $0.isDone.eq(false) }
      .order { $0.title.asc() }
      .execute(count: .exact)
    _ = try await client.from(IsolationTodo.self).select().count(.exact)
    _ = try await client.from(IsolationTodo.self).select(IsolationTodoTitle.self).execute().value
    _ = try await client.from(IsolationTodo.self).select().csv().execute()
    _ = try await client.from(IsolationTodo.self).select().geojson().execute()
    _ = try await client.from(IsolationTodo.self).select().explain().execute()

    try await client.from(IsolationTodo.self).insert(draft).execute()
    try await client.from(IsolationTodo.self).insert(draft).execute(count: .exact)
    try await client.from(IsolationTodo.self).insert([draft]).execute()
    _ = try await client.from(IsolationTodo.self).insert(draft).returning().execute().value
    try await client.from(IsolationTodo.self).upsert(draft).execute()
    try await client.from(IsolationTodo.self).upsert([draft]).execute()
    try await client.from(IsolationTodo.self).upsert(draft, onConflict: \.id).execute()
    try await client.from(IsolationTodo.self).update { $0.isDone = true }
      .where { $0.id.eq(1) }
      .execute()
    try await client.from(IsolationTodo.self).update { $0.isDone = true }
      .all()
      .execute(count: .exact)
    try await client.from(IsolationTodo.self).delete().where { $0.id.eq(1) }.execute()
    try await client.from(IsolationTodo.self).delete().all().execute()

    _ = try await client.rpc.call(IsolationSearchTodos(keyword: "milk")).execute().value
    _ = try await client.rpc.call(IsolationSearchTodos(keyword: "milk")).rows().execute().value
    try await client.rpc.call(IsolationResetTodos()).execute()
    _ = try await client.rpc(IsolationSearchTodos(keyword: "milk")).execute().value
  }
}
