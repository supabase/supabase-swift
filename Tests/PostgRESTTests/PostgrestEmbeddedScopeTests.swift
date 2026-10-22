//
//  PostgrestEmbeddedScopeTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import HTTPTypes
import Testing

@_spi(Experimental) @testable import PostgREST

@Suite
struct PostgrestEmbeddedScopeTests {
  struct Todo: _PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let isDone = _PostgrestColumn<Todo, Bool>("is_done")
    }

    static let columns = Columns()
  }

  struct Comment: _PostgrestRelation {
    static let relationName = "comments"
    static let selectString = "*"

    var id: Int

    struct Columns: Sendable {
      let id = _PostgrestColumn<Comment, Int>("id")
      let todoID = _PostgrestColumn<Comment, Int>("todo_id")
      let parentID = _PostgrestNullableColumn<Comment, Int>("parent_id")
      let approved = _PostgrestColumn<Comment, Bool>("approved")
      let authorID = _PostgrestColumn<Comment, Int>("author_id")
      let createdAt = _PostgrestColumn<Comment, Date>("created_at")
      let meta = _PostgrestColumn<Comment, JSONValue>("meta")
    }

    static let columns = Columns()
  }

  struct CommentBody: _PostgrestSelection {
    typealias Source = Comment
    static let selectString = "id:id,body:body"

    var id: Int
    var body: String
  }

  struct CommentWithReplies: _PostgrestEmbeddingSelection {
    typealias Source = Comment
    static let selectString = "id:id,replies:\(embeds.replies.postgrestExpression)"

    var id: Int
    var replies: [CommentBody]

    struct Embeds: Sendable {
      let replies = _PostgrestEmbed<CommentBody>(alias: "replies", foreignKey: "parent_id")
    }

    static let embeds = Embeds()
  }

  struct TodoWithComments: _PostgrestEmbeddingSelection {
    typealias Source = Todo
    static let selectString = "id:id,comments:\(embeds.comments.postgrestExpression)"

    var id: Int
    var comments: [CommentBody]

    struct Embeds: Sendable {
      let comments = _PostgrestEmbed<CommentBody>(alias: "comments", foreignKey: "todo_id")
    }

    static let embeds = Embeds()
  }

  struct TodoWithThreads: _PostgrestEmbeddingSelection {
    typealias Source = Todo
    static let selectString = "id:id,comments:\(embeds.comments.postgrestExpression)"

    var id: Int
    var comments: [CommentWithReplies]

    struct Embeds: Sendable {
      let comments = _PostgrestEmbed<CommentWithReplies>(alias: "comments", foreignKey: "todo_id")
    }

    static let embeds = Embeds()
  }

  @Test
  func requiringRendersTheTargetQuery() async throws {
    let capture = QueryCapture()
    let me = 42
    _ = try await capture.client.from(Todo.self)
      .select(TodoWithComments.self)
      .where { $0.isDone.eq(false) }
      .requiring(\.comments) {
        $0.where { $0.approved.eq(true) || $0.authorID.eq(me) }
          .order { $0.createdAt.desc().nulls(.last) }
          .limit(5)
      }
      .execute()

    #expect(
      capture.query
        == "select=id:id,comments:comments!todo_id!inner(id:id,body:body)"
        + "&is_done=eq.false"
        + "&comments.or=(approved.eq.true,author_id.eq.42)"
        + "&comments.order=created_at.desc.nullslast"
        + "&comments.limit=5"
    )
  }

  @Test
  func anOperandWithNoJSONFormInAScopeFailsTheQuery() async throws {
    let capture = QueryCapture()
    await #expect(throws: PostgrestError.self) {
      try await capture.client.from(Todo.self)
        .select(TodoWithComments.self)
        .embedded(\.comments) { $0.where { $0.meta.containsJSON(["n": .double(.nan)]) } }
        .execute()
    }
    #expect(capture.query == nil)
  }

  @Test
  func embeddedLeavesTheSelectEntryAlone() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select(TodoWithComments.self)
      .embedded(\.comments) { $0.where { $0.approved.eq(true) } }
      .execute()

    #expect(
      capture.query
        == "select=id:id,comments:comments!todo_id(id:id,body:body)&comments.approved=eq.true"
    )
  }

  @Test
  func nestedScopesRenderDottedPaths() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select(TodoWithThreads.self)
      .embedded(\.comments) {
        $0.limit(10).embedded(\.replies) { $0.limit(3) }
      }
      .execute()

    #expect(
      capture.query
        == "select=id:id,comments:comments!todo_id(id:id,replies:comments!parent_id(id:id,body:body))"
        + "&comments.limit=10&comments.replies.limit=3"
    )
  }

  @Test
  func nestedRequiringMarksTheInnerEntryOnly() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select(TodoWithThreads.self)
      .embedded(\.comments) {
        $0.requiring(\.replies) { $0.where { $0.approved.eq(true) } }
      }
      .execute()

    #expect(
      capture.query
        == "select=id:id,comments:comments!todo_id(id:id,replies:comments!parent_id!inner(id:id,body:body))"
        + "&comments.replies.approved=eq.true"
    )
  }

  @Test
  func repeatedRequiringMarksTheEntryOnce() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select(TodoWithComments.self)
      .requiring(\.comments) { $0.limit(1) }
      .requiring(\.comments) { $0.limit(2) }
      .execute()

    #expect(
      capture.query
        == "select=id:id,comments:comments!todo_id!inner(id:id,body:body)"
        + "&comments.limit=1&comments.limit=2"
    )
  }

  @Test
  func orderKeysMergeWithinAScope() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select(TodoWithComments.self)
      .embedded(\.comments) { $0.order { $0.createdAt.desc() }.order { $0.id } }
      .execute()

    #expect(capture.query?.hasSuffix("&comments.order=created_at.desc,id") == true)
  }

  @Test
  func rangeRendersOffsetAndLimit() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select(TodoWithComments.self)
      .embedded(\.comments) { $0.range(10...19) }
      .execute()

    #expect(capture.query?.hasSuffix("&comments.offset=10&comments.limit=10") == true)
  }

  @Test
  func anAmbiguousUntypedEmbedSurfacesTheServerError() async throws {
    let body = """
      {"code":"PGRST201","message":"Could not embed because more than one relationship was found for 'todos' and 'comments'","details":[{"cardinality":"one-to-many","embedding":"todos with comments","relationship":"comments_todo_id_fkey using todos(id) and comments(todo_id)"}],"hint":"Try changing 'comments' to one of the following: 'comments!comments_todo_id_fkey', 'comments!comments_parent_todo_id_fkey'. Find the desired relationship in the 'details' key."}
      """
    let capture = QueryCapture(body: body, status: .multipleChoices)

    await #expect { () async throws in
      _ = try await capture.client.from("todos").select("id,comments(*)").execute()
    } throws: { error in
      guard let error = error as? PostgrestError else { return false }
      return error.kind == .server
        && error.serverError?.code == "PGRST201"
        && error.serverError?.hint?.contains("comments!comments_todo_id_fkey") == true
        && error.response?.statusCode == 300
    }
  }
}
