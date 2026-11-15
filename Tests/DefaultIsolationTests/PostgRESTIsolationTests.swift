//
//  PostgRESTIsolationTests.swift
//  DefaultIsolationTests
//
//  Created by Guilherme Souza on 05/11/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
@_spi(Experimental) import Supabase

/// The real macros, on types this target makes main-actor isolated. They compile only if each
/// expansion opts its conformances and nested types out of that isolation.
@Table("todos")
struct IsolationTodo {
  @PrimaryKey var id: Int
  var title: String
  @Default var isDone: Bool
  var priority: IsolationPriority?
  @Generated var createdAt: Date
}

/// A column type with its own main-actor-isolated `Codable` conformance.
enum IsolationPriority: String, Codable {
  case low, high
}

@SelectionOf(IsolationTodo.self)
struct IsolationTodoTitle {
  var title: String
}

@Table("comments", readOnly: true)
struct IsolationComment {
  @PrimaryKey var id: Int
  var todoID: Int
  var body: String
}

@SelectionOf(IsolationComment.self)
struct IsolationCommentBody {
  var body: String
}

/// A computed relationship. The expansion reads it from a nonisolated context, so the extension
/// has to be `nonisolated`.
nonisolated extension IsolationTodo.Columns {
  var recentComments: _PostgrestToManyRelation<IsolationTodo, IsolationComment> {
    .init("recent_comments")
  }
}

/// A selection with embeds, so the expansion also emits its `Embeds` namespace.
@SelectionOf(IsolationTodo.self)
struct IsolationTodoWithComments {
  var title: String
  @Relationship(\IsolationComment.todoID) var comments: [IsolationCommentBody]
  @Relationship(computed: \IsolationTodo.Columns.recentComments) var recent: [IsolationCommentBody]
}

@Function("search_todos")
struct IsolationSearchTodos {
  typealias Result = [IsolationTodo]

  var keyword: String
}

@Function("reset_todos")
struct IsolationResetTodos {}

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
    _ = try await client.from(IsolationTodo.self).select(IsolationTodoWithComments.self)
      .execute().value
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
