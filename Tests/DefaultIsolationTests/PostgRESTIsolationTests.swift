//
//  PostgRESTIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 05/11/26.
//

import Foundation
import PostgrestMacros
@_spi(Experimental) import Supabase

/// A `@Table` type declared under `.defaultIsolation(MainActor.self)`. The macro-generated
/// requirements are nonisolated, so a consumer opts the type out with `nonisolated`, as an app
/// would. The queries below then run from the main actor.
@Table("todos")
nonisolated struct IsolationTodo {
  @PrimaryKey var id: Int
  var title: String
  var isDone: Bool
}

@Function("search_todos")
nonisolated struct IsolationSearchTodos {
  typealias Result = [IsolationTodo]
  var keyword: String
}

@Function("reset_todos")
nonisolated struct IsolationResetTodos {}

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

  /// A narrower read of `IsolationTodo`.
  @SelectionOf(IsolationTodo.self)
  nonisolated struct IsolationTodoTitle {
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
