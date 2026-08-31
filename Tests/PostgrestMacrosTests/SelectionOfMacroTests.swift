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

        /// Fails to compile if a property does not name a column on Todo.
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
      """
      struct TodoSummary {
        var id: Int
        var isDone: Bool
      }

      extension TodoSummary {
        typealias Source = Todo

        static let selectString = [
          "id:\\(Todo.columns.id.postgrestExpression)",
          "is_done:\\(Todo.columns.isDone.postgrestExpression)",
        ].joined(separator: ",")

        enum CodingKeys: String, CodingKey {
          case id = "id"
          case isDone = "is_done"
        }

        /// Fails to compile if a property does not name a column on Todo.
        private static let _columnCheck: [String] = [
          Todo.columns.id.postgrestExpression,
          Todo.columns.isDone.postgrestExpression,
        ]
      }
      """
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

        /// Fails to compile if a property does not name a column on Todo.
        private static let _columnCheck: [String] = [
          Todo.columns.isDone.postgrestExpression,
        ]
      }
      """#
    }
  }
}
