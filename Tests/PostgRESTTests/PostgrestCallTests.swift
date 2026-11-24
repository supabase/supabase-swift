//
//  PostgrestCallTests.swift
//  PostgREST
//
//  Created by Guilherme Souza on 24/11/26.
//

import Foundation
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestCallTests {
  struct Score: _PostgrestWritableRelation, _PostgrestKeyedRelation {
    static let relationName = "scores"
    static let selectString = "*"
    static let primaryKeyColumns = ["id"]

    var id: Int

    struct Columns: Sendable {
      let id = _PostgrestColumn<Score, Int>("id")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var id: Int
    }
  }

  private let client: PostgrestClient

  init() throws {
    client = try PostgrestClient(
      configuration: .init(url: URL(string: "https://example.supabase.co/rest/v1")!))
  }

  @Test
  func readsAreSelects() throws {
    #expect(client.from("users").select().request.call == .init(operation: .select, table: "users"))
    #expect(
      client.from("users").select(head: true, count: .exact).request.call
        == .init(operation: .select, table: "users"))
    #expect(
      client.from(Score.self).select().request.call == .init(operation: .select, table: "scores"))
  }

  @Test
  func writesMapToTheirOperation() throws {
    let users = client.from("users")
    #expect(try users.insert(["id": 1]).request.call == .init(operation: .insert, table: "users"))
    #expect(try users.upsert(["id": 1]).request.call == .init(operation: .upsert, table: "users"))
    #expect(
      try users.upsert(["id": 1], ignoreDuplicates: true).request.call
        == .init(operation: .upsert, table: "users"))
    #expect(try users.update(["id": 1]).request.call == .init(operation: .update, table: "users"))
    #expect(users.delete().request.call == .init(operation: .delete, table: "users"))
  }

  @Test
  func typedWritesMapToTheirOperation() throws {
    let scores = client.from(Score.self)
    #expect(
      try scores.insert(Score.Draft(id: 1)).request.call
        == .init(operation: .insert, table: "scores"))
    #expect(
      try scores.upsert([Score.Draft(id: 1)]).request.call
        == .init(operation: .upsert, table: "scores"))
    #expect(scores.delete().request.call == .init(operation: .delete, table: "scores"))
  }

  @Test
  func anInsertWithOtherPreferencesStaysAnInsert() throws {
    var request = try client.from("users").insert(["id": 1], returning: .representation).request
    request.setPreference("missing=default")
    #expect(request.call == .init(operation: .insert, table: "users"))
  }

  @Test
  func rpcCallsAreRPCWhateverTheMethod() throws {
    for builder in [
      try client.rpc("get_scores"),
      try client.rpc("get_scores", get: true),
      try client.rpc("get_scores", head: true),
    ] {
      #expect(builder.request.call == .init(operation: .rpc, function: "get_scores"))
    }
  }
}
