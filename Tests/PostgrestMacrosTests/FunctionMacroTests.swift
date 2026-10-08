//
//  FunctionMacroTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 07/10/26.
//

import MacroTesting
import Testing

@testable import PostgrestMacrosPlugin

@Suite(.macros(["Function": FunctionMacro.self]))
struct FunctionMacroTests {
  /// The arguments get `CodingKeys` from the same input `@Table` reads, so `nameParam` goes out
  /// as `name_param` and `@Column` wins. `Result` is the author's and is left alone.
  @Test
  func expandsAFunction() {
    assertMacro {
      """
      @Function("search_todos")
      struct SearchTodos {
        typealias Result = [Todo]
        var keyword: String
        var maxResults: Int
        @Column("only_done") var done: Bool?
      }
      """
    } expansion: {
      """
      struct SearchTodos {
        typealias Result = [Todo]
        var keyword: String
        var maxResults: Int
        @Column("only_done") var done: Bool?
      }

      extension SearchTodos {
        static let functionName = "search_todos"

        typealias Schema = PostgREST.PublicSchema

        enum CodingKeys: String, CodingKey {
          case keyword = "keyword"
          case maxResults = "max_results"
          case done = "only_done"
        }
      }
      """
    }
  }

  @Test
  func aFunctionWithNoArgumentsHasNoCodingKeys() {
    assertMacro {
      """
      @Function("ping", schema: PrivateSchema.self)
      public struct Ping {}
      """
    } expansion: {
      """
      public struct Ping {}

      extension Ping {
        public static let functionName = "ping"

        public typealias Schema = PrivateSchema
      }
      """
    }
  }

  @Test
  func rejectsAClass() {
    assertMacro {
      """
      @Function("ping")
      class Ping {}
      """
    } diagnostics: {
      """
      @Function("ping")
      ┬────────────────
      ╰─ 🛑 @Function can only be applied to a struct
      class Ping {}
      """
    }
  }

  @Test
  func requiresAnExplicitTypeAnnotation() {
    assertMacro {
      """
      @Function("search_todos")
      struct SearchTodos {
        var keyword = ""
      }
      """
    } diagnostics: {
      """
      @Function("search_todos")
      struct SearchTodos {
        var keyword = ""
            ┬──────
            ╰─ 🛑 @Function requires an explicit type annotation on 'keyword', as in 'var keyword: <Type> = ...' — without one the macro cannot infer the type, and the column is dropped
      }
      """
    }
  }
}
