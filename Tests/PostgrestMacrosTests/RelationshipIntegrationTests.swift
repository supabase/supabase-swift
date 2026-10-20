//
//  RelationshipIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 31/08/26.
//

import Foundation
@_spi(Experimental) import PostgrestMacros
import Testing

@Table("todos")
struct RelationshipTodo {
  @PrimaryKey var id: Int
  var task: String
}

@Table("comments")
struct RelationshipComment {
  @PrimaryKey var id: Int
  var todoID: Int
  var body: String
  @Column("written_by") var authorID: Int
}

@Table("users")
struct RelationshipUser {
  @PrimaryKey var id: Int
  var name: String
}

@SelectionOf(RelationshipComment.self)
struct RelationshipCommentBody {
  var id: Int
  var body: String
}

@SelectionOf(RelationshipUser.self)
struct RelationshipUserName {
  var name: String
}

@SelectionOf(RelationshipTodo.self)
struct RelationshipTodoWithComments {
  var id: Int
  var task: String
  @Relationship(\RelationshipComment.todoID) var comments: [RelationshipCommentBody]
}

@SelectionOf(RelationshipComment.self)
struct RelationshipCommentWithAuthor {
  var body: String
  @Relationship(\RelationshipComment.authorID) var author: RelationshipUserName?
}

@Suite
struct RelationshipIntegrationTests {
  @Test
  func selectStringCarriesTheEmbedAndItsForeignKeyHint() {
    #expect(
      RelationshipTodoWithComments.selectString
        == "id:id,task:task,comments:comments!todo_id(id:id,body:body)"
    )
  }

  @Test
  func aManyToOneEmbedReadsTheForeignKeyOffItsOwnRelation() {
    #expect(
      RelationshipCommentWithAuthor.selectString == "body:body,author:users!written_by(name:name)"
    )
  }

  @Test
  func anEmbedDecodesUnderItsAlias() throws {
    let json = #"{"id":1,"task":"ship","comments":[{"id":7,"body":"nice"}]}"#
    let row = try JSONDecoder().decode(
      RelationshipTodoWithComments.self, from: Data(json.utf8)
    )
    #expect(row.comments.map(\.id) == [7])
  }
}

@Suite
struct RelationshipScopeIntegrationTests {
  @Test
  func requiringMarksTheGeneratedEmbedAndPrefixesTheScope() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(RelationshipTodo.self)
      .select(RelationshipTodoWithComments.self)
      .requiring(\.comments) { $0.where { $0.authorID.eq(7) }.limit(5) }
      .execute()

    #expect(
      capture.query
        == "select=id:id,task:task,comments:comments!todo_id!inner(id:id,body:body)"
        + "&comments.written_by=eq.7&comments.limit=5"
    )
  }

  @Test
  func aToOneScopeIsPrefixedByItsAlias() async throws {
    let capture = RequestCapture()
    _ = try await capture.client
      .from(RelationshipComment.self)
      .select(RelationshipCommentWithAuthor.self)
      .embedded(\.author) { $0.where { $0.name.eq("Ada") } }
      .execute()

    #expect(
      capture.query
        == "select=body:body,author:users!written_by(name:name)&author.name=eq.Ada"
    )
  }
}
