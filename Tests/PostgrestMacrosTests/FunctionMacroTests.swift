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

      nonisolated extension SearchTodos {
        static let functionName = "search_todos"

        typealias Schema = PostgREST._PublicSchema

        nonisolated enum CodingKeys: String, CodingKey {
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

      nonisolated extension Ping {
        public static let functionName = "ping"

        public typealias Schema = PrivateSchema
      }
      """
    }
  }

  /// The name is a database identifier, so it can hold anything. It must come out as the same
  /// string, never as an interpolation or the end of the literal.
  @Test
  func aNameWithAQuoteABackslashOrAnInterpolationRoundTrips() {
    assertMacro {
      #"""
      @Function(#"x\(exit(0))"y\z"#)
      struct Hostile {}
      """#
    } expansion: {
      #"""
      struct Hostile {}

      nonisolated extension Hostile {
        static let functionName = "x\\(exit(0))\"y\\z"

        typealias Schema = PostgREST._PublicSchema
      }
      """#
    }
  }

  @Test
  func aNameWithANewlineStaysOnOneLine() {
    assertMacro {
      #"""
      @Function("line\nbreak")
      struct Multiline {}
      """#
    } expansion: {
      #"""
      struct Multiline {}

      nonisolated extension Multiline {
        static let functionName = "line\nbreak"

        typealias Schema = PostgREST._PublicSchema
      }
      """#
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
