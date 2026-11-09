//
//  SupabaseTypegenPostgrestTypegenOutputTests.swift
//  SupabaseTypegenPostgrestTypegenOutputTests
//
//  Created by Guilherme Souza on 09/10/26.
//

import Foundation
import HTTPTypes
@_spi(Experimental) import PostgrestMacros
import TestHelpers
import Testing

/// This target builds with `.defaultIsolation(MainActor.self)`, so the generated file and this
/// selection compile the way they would in an app module with default MainActor isolation.
@SelectionOf(Users.self)
struct UserWithTodos {
  var name: String?
  @Relationship(\Todos.userID) var todos: [Todos]
  @Relationship(computed: \Users.Columns.getTodosFromUser) var computedTodos: [Todos]
  @Relationship(computed: \Users.Columns.functionUsingTableReturns) var firstTodo: Todos?
}

@Suite
struct SupabaseTypegenPostgrestTypegenOutputTests {
  @Test
  func prefixedRelationSendsItsSchemaInAcceptProfile() async throws {
    let transport = RecordingTransport { _, _ in
      (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]), Data("[]".utf8))
    }
    let client = try PostgrestClient(
      url: URL(string: "https://example.supabase.co")!,
      http: .init(transport: transport)
    )
    _ = try await client.from(InventoryItems.self).select()
      .where { $0.status.eq(.stocked) }
      .execute()

    let request = try #require(transport.requests.first?.head)
    #expect(request.headerFields[HTTPField.Name("Accept-Profile")!] == "inventory")
    #expect(request.path?.removingPercentEncoding == "/items?select=*&status=eq.STOCKED")
  }

  @Test
  func embedsAndFunctionCallsCompileUnderDefaultMainActorIsolation() async throws {
    let transport = RecordingTransport { _, _ in
      (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]), Data("[]".utf8))
    }
    let client = try PostgrestClient(
      url: URL(string: "https://example.supabase.co")!,
      http: .init(transport: transport)
    )
    _ = try await client.from(Users.self).select(UserWithTodos.self)
      .where { $0.status.eq(.active) }
      .execute()
    _ = try await client.rpc.getTodosFromUser(searchUserID: 1).execute()

    let paths = transport.requests.map { $0.head.path?.removingPercentEncoding }
    #expect(
      paths == [
        "/users?select=name:name,todos:todos!user-id(*),computed_todos:get_todos_from_user(*),"
          + "first_todo:function_using_table_returns(*)&status=eq.ACTIVE",
        "/rpc/get_todos_from_user",
      ]
    )
  }
}
