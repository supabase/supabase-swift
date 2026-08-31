//
//  RelationshipIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 31/08/26.
//

import Foundation
import PostgrestMacros
import Testing

// File scope, for the same reason as `SelectionIntegrationTests`: both macros attach extensions.

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

/// The many-to-one direction: the foreign key sits on *this* selection's own relation, and the
/// embed is a single row rather than an array.
@SelectionOf(RelationshipComment.self)
struct RelationshipCommentWithAuthor {
  var body: String
  @Relationship(\RelationshipComment.authorID) var author: RelationshipUserName?
}

@Suite
struct RelationshipIntegrationTests {
  @Test
  func selectStringCarriesTheEmbedAndItsForeignKeyHint() {
    // `comments:` is the alias the response comes back under, `comments` the embedded relation,
    // `!todo_id` the disambiguating hint, and the parentheses the embed's own select list.
    #expect(
      RelationshipTodoWithComments.selectString
        == "id:id,task:task,comments:comments!todo_id(id:id,body:body)"
    )
  }

  @Test
  func aManyToOneEmbedReadsTheForeignKeyOffItsOwnRelation() {
    // Two things at once. The key path is rooted on the selection's own relation rather than on
    // the target, so the target comes from the property's type — `users`, which appears nowhere in
    // the attribute. And the hint is read off that relation's namespace, so the `@Column`
    // override applies: `written_by`, not the `author_id` a local snake-casing would produce.
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
