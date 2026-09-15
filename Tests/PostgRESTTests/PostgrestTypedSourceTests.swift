//
//  PostgrestTypedSourceTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestTypedSourceTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let task = PostgrestColumn<Todo, String>("task")
    }

    static let columns = Columns()
  }

  struct Secret: PostgrestWritableRelation {
    static let relationName = "secrets"
    static let schema = "private"
    static let selectString = "*"

    var id: Int
    var value: String

    struct Columns: Sendable {
      let id = PostgrestColumn<Secret, Int>("id")
      let value = PostgrestColumn<Secret, String>("value")
    }

    static let columns = Columns()

    struct Draft: Encodable, Sendable {
      var value: String
    }
  }

  @Test
  func fromUsesTheRelationName() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().execute()
    #expect(capture.path?.hasSuffix("/todos") == true)
    #expect(capture.query?.contains("select=*") == true)
  }

  @Test
  func selectDecodesIntoTheRelationType() async throws {
    let capture = QueryCapture(body: #"[{"id":1,"task":"buy milk"}]"#)
    let todos = try await capture.client.from(Todo.self).select().execute().value
    #expect(todos.count == 1)
    #expect(todos.first?.task == "buy milk")
  }

  @Test
  func fromSendsTheRelationSchemaOnReads() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Secret.self).select().execute()
    #expect(capture.path?.hasSuffix("/secrets") == true)
    #expect(capture.header("Accept-Profile") == "private")
    #expect(capture.header("Content-Profile") == nil)
  }

  @Test
  func fromSendsTheRelationSchemaOnWrites() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Secret.self).insert(Secret.Draft(value: "shh")).execute()
    #expect(capture.header("Content-Profile") == "private")
    #expect(capture.header("Accept-Profile") == nil)
  }

  @Test
  func clientSchemaWinsOverTheRelationSchema() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.schema("tenant_a").from(Secret.self).select().execute()
    #expect(capture.header("Accept-Profile") == "tenant_a")
  }

  @Test
  func publicRelationOnUnscopedClientSendsNoProfile() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().execute()
    #expect(capture.header("Accept-Profile") == nil)
    #expect(capture.header("Content-Profile") == nil)
  }
}
