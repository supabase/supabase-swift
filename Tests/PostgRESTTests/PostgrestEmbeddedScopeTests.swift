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

/// The scope construct from spec §4.4, over hand-written conformances that spell out what
/// `@SelectionOf` generates. The macro-generated form is covered end to end in
/// `RelationshipIntegrationTests`.
///
/// One property is checked by the compiler rather than here: `embedded`/`requiring` are declared
/// only where `Output == [S]` and `S: _PostgrestEmbeddingSelection`. A relation never conforms, so
/// `client.from(Todo.self).select().requiring(\.comments) { $0 }` is *no such member* — a
/// whole-row select declares no embeds to scope.
///
/// Another is checked outside `swift test`: a parent filter cannot be ORed with an embedded one.
/// See `Tests/CompileFailures/PostgrestParentOrEmbeddedFilter.swift`, which
/// `scripts/check-compile-failures.sh` requires to fail to compile.
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
    }

    static let columns = Columns()
  }

  /// Selects `id` and `body` only. `approved`, `authorID` and `createdAt` are deliberately not
  /// selected: a scope filters the embedded *relation*, so they stay filterable.
  struct CommentBody: _PostgrestSelection {
    typealias Source = Comment
    static let selectString = "id:id,body:body"

    var id: Int
    var body: String
  }

  /// A comment with its replies, so a scope can nest.
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

  /// The §4.4 target query, verbatim, and its exact rendering. `!inner` goes after the
  /// foreign-key hint; §9.2 verified either order works, so this pins one.
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

  /// The trap the two names exist for: the same scope without `!inner` keeps every parent row.
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

  /// A nested `requiring` marks the inner entry, not the outer one — the outer embed is still an
  /// `embedded`, so parents without comments are kept.
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

  /// PostgREST honours only the first `order` it sees, so two sort keys in a scope merge into one
  /// parameter, as they do at top level.
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

  /// §9.2: omitting a needed foreign-key hint is HTTP 300 `PGRST201`. A typed embed always
  /// carries the hint, so only the string form can reach it, and it must surface as the server's
  /// own error rather than a failure to decode the rows that never came.
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
