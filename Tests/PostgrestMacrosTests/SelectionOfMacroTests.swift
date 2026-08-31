//
//  SelectionOfMacroTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import MacroTesting
import Testing

@testable import PostgrestMacrosPlugin

/// As in `TableMacroTests`, `MacroTesting` expands without the declaration, so `conformingTo:` is
/// always empty here and the recorded extensions carry no inheritance clause.
@Suite(.macros(["SelectionOf": SelectionOfMacro.self]))
struct SelectionOfMacroTests {
  @Test
  func expandsAColumnSubset() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      struct TodoSummary {
        var id: Int
        @Column("due_at") var dueDate: Date?
      }
      """
    } expansion: {
      #"""
      struct TodoSummary {
        var id: Int
        @Column("due_at") var dueDate: Date?
      }

      extension TodoSummary {
        typealias Source = Todo

        static let selectString = [
          "id:\(Todo.columns.id.postgrestExpression)",
          "due_at:\(Todo.columns.dueDate.postgrestExpression)",
        ].joined(separator: ",")

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case dueDate = "due_at"
        }

        /// Fails to compile if a property does not name a column on Todo, or an embed's
        /// foreign key does not name one on its own relation.
        private static let _columnCheck: [String] = [
          Todo.columns.id.postgrestExpression,
          Todo.columns.dueDate.postgrestExpression,
        ]
      }
      """#
    }
  }

  /// The select list reads the relation's namespace directly, not a key-path-to-column mapping.
  @Test
  func selectStringReadsTheColumnNamespace() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      struct TodoSummary {
        var id: Int
        var isDone: Bool
      }
      """
    } expansion: {
      #"""
      struct TodoSummary {
        var id: Int
        var isDone: Bool
      }

      extension TodoSummary {
        typealias Source = Todo

        static let selectString = [
          "id:\(Todo.columns.id.postgrestExpression)",
          "is_done:\(Todo.columns.isDone.postgrestExpression)",
        ].joined(separator: ",")

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case isDone = "is_done"
        }

        /// Fails to compile if a property does not name a column on Todo, or an embed's
        /// foreign key does not name one on its own relation.
        private static let _columnCheck: [String] = [
          Todo.columns.id.postgrestExpression,
          Todo.columns.isDone.postgrestExpression,
        ]
      }
      """#
    }
  }

  /// The embed the whole attribute exists for. Every part of the rendered form is an
  /// interpolation: the embedded relation and its select list come from the property's type, and
  /// the `!todo_id` hint from the foreign key's own relation.
  @Test
  func expandsAToManyEmbed() {
    assertMacro {
      #"""
      @SelectionOf(Todo.self)
      struct TodoWithComments {
        var id: Int
        var task: String
        @Relationship(\Comment.todoID) var comments: [CommentBody]
      }
      """#
    } expansion: {
      #"""
      struct TodoWithComments {
        var id: Int
        var task: String
        @Relationship(\Comment.todoID) var comments: [CommentBody]
      }

      extension TodoWithComments {
        typealias Source = Todo

        static let selectString = [
          "id:\(Todo.columns.id.postgrestExpression)",
          "task:\(Todo.columns.task.postgrestExpression)",
          "comments:\(CommentBody.Source.relationName)!\(Comment.columns.todoID.postgrestExpression)(\(CommentBody.selectString))",
        ].joined(separator: ",")

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case task = "task"
          case comments = "comments"
        }

        /// Fails to compile if a property does not name a column on Todo, or an embed's
        /// foreign key does not name one on its own relation.
        private static let _columnCheck: [String] = [
          Todo.columns.id.postgrestExpression,
          Todo.columns.task.postgrestExpression,
          Comment.columns.todoID.postgrestExpression,
        ]
      }
      """#
    }
  }

  /// The other direction. `\Comment.authorID` is rooted on the selection's *own* relation rather
  /// than on the target, and the expansion is the same shape — which is the point: the key path
  /// names the foreign key, and the property names the embed.
  @Test
  func expandsAToOneEmbed() {
    assertMacro {
      #"""
      @SelectionOf(Comment.self)
      struct CommentWithAuthor {
        var body: String
        @Relationship(\Comment.authorID) var author: UserName?
      }
      """#
    } expansion: {
      #"""
      struct CommentWithAuthor {
        var body: String
        @Relationship(\Comment.authorID) var author: UserName?
      }

      extension CommentWithAuthor {
        typealias Source = Comment

        static let selectString = [
          "body:\(Comment.columns.body.postgrestExpression)",
          "author:\(UserName.Source.relationName)!\(Comment.columns.authorID.postgrestExpression)(\(UserName.selectString))",
        ].joined(separator: ",")

        enum CodingKeys: String, CodingKey {
          case body = "body"
          case author = "author"
        }

        /// Fails to compile if a property does not name a column on Comment, or an embed's
        /// foreign key does not name one on its own relation.
        private static let _columnCheck: [String] = [
          Comment.columns.body.postgrestExpression,
          Comment.columns.authorID.postgrestExpression,
        ]
      }
      """#
    }
  }

  @Test
  func propagatesTheAccessLevel() {
    assertMacro {
      """
      @SelectionOf(Todo.self)
      public struct TodoSummary {
        var isDone: Bool
      }
      """
    } expansion: {
      #"""
      public struct TodoSummary {
        var isDone: Bool
      }

      extension TodoSummary {
        public typealias Source = Todo

        public static let selectString = [
          "is_done:\(Todo.columns.isDone.postgrestExpression)",
        ].joined(separator: ",")

        enum CodingKeys: String, CodingKey {
          case isDone = "is_done"
        }

        /// Fails to compile if a property does not name a column on Todo, or an embed's
        /// foreign key does not name one on its own relation.
        private static let _columnCheck: [String] = [
          Todo.columns.isDone.postgrestExpression,
        ]
      }
      """#
    }
  }
}
