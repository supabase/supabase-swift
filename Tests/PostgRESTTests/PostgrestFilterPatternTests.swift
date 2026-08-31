//
//  PostgrestFilterPatternTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestFilterPatternTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String
    var note: String?

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let task = PostgrestColumn<Todo, String>("task")
      let note = PostgrestNullableColumn<Todo, String>("note")
    }

    static let columns = Columns()

    static func columnName(for keyPath: PartialKeyPath<Self>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.task: "task"
      case \Self.note: "note"
      default: fatalError("unmapped key path")
      }
    }
  }

  private func rendered(_ filter: PostgrestFilter<Todo>) -> String {
    filter.queryItems().map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
  }

  @Test
  func patternOperatorsRenderTheirPrefix() {
    let task = Todo.columns.task
    #expect(rendered(task.like("Jo%")) == "task=like.Jo%")
    #expect(rendered(task.ilike("jo%")) == "task=ilike.jo%")
    #expect(rendered(task.regexMatch("^Jo")) == "task=match.^Jo")
    #expect(rendered(task.regexIMatch("^jo")) == "task=imatch.^jo")
  }

  /// The multi-pattern forms take a braced array literal, not a parenthesised list.
  @Test
  func multiPatternOperatorsRenderABracedArray() {
    let task = Todo.columns.task
    #expect(rendered(task.likeAllOf(["A%", "%z"])) == "task=like(all).{A%,%z}")
    #expect(rendered(task.likeAnyOf(["A%", "%z"])) == "task=like(any).{A%,%z}")
    #expect(rendered(task.ilikeAllOf(["a%"])) == "task=ilike(all).{a%}")
    #expect(rendered(task.ilikeAnyOf(["a%"])) == "task=ilike(any).{a%}")
  }

  /// An empty list reaches the server as an empty literal rather than being short-circuited: for
  /// `all` that is vacuously true and matches every row, for `any`/`in` it matches none.
  @Test
  func emptyListsRenderAnEmptyLiteral() {
    #expect(rendered(Todo.columns.task.likeAllOf([])) == "task=like(all).{}")
    #expect(rendered(Todo.columns.task.likeAnyOf([])) == "task=like(any).{}")
    #expect(rendered(Todo.columns.id.in([])) == "id=in.()")
  }

  /// There is no `notIn`; `!` covers it.
  @Test
  func listOperatorsRenderAParenthesisedList() {
    #expect(rendered(Todo.columns.id.in([1, 2, 3])) == "id=in.(1,2,3)")
    #expect(rendered(!Todo.columns.id.in([1, 2])) == "id=not.in.(1,2)")
  }

  /// List operands are escaped, unlike single values at top level: a comma splits the list, and a
  /// parenthesis silently matches nothing.
  @Test
  func listMembersAreEscaped() {
    #expect(rendered(Todo.columns.task.in(["a,b"])) == "task=in.(\"a,b\")")
    #expect(rendered(Todo.columns.task.in(["p(q)", "Ada"])) == "task=in.(\"p(q)\",Ada)")
  }

  /// A comma splits one pattern into two, and a brace corrupts the literal's delimiters. The
  /// brace case is what distinguishes the array escaper from the filter escaper here — swapping
  /// them would leave a stray `{` unquoted while the paren case still passed.
  @Test
  func multiPatternMembersAreEscaped() {
    #expect(rendered(Todo.columns.task.likeAnyOf(["a,%"])) == "task=like(any).{\"a,%\"}")
    #expect(rendered(Todo.columns.task.likeAnyOf(["a{b"])) == "task=like(any).{\"a{b\"}")
  }

  /// A nullable text column reaches the same declarations: its `Value` is the wrapped `String`.
  @Test
  func nullableColumnsTakePatternAndListOperators() {
    #expect(rendered(Todo.columns.note.like("Jo%")) == "note=like.Jo%")
    #expect(rendered(Todo.columns.note.in(["a", "b"])) == "note=in.(a,b)")
  }

  /// `in`'s own `(…)` must not be re-escaped inside a group: `or=(id.in."(2,3)",id.eq.4)` is
  /// a `PGRST100`. Reproduces with no special characters at all.
  @Test
  func inKeepsItsListParensBareInsideAGroup() {
    #expect(
      rendered(Todo.columns.id.in([2, 3]) || Todo.columns.id.eq(4))
        == "or=(id.in.(2,3),id.eq.4)")
  }

  /// Members are still escaped inside a group. Only the list's own outer parens stay bare.
  @Test
  func inEscapesItsListMembersInsideAGroup() {
    #expect(
      rendered(Todo.columns.task.in(["p(q)", "Ada"]) || Todo.columns.id.eq(4))
        == "or=(task.in.(\"p(q)\",Ada),id.eq.4)")
  }

  /// PostgREST tolerates the redundant quoting `group()` adds around a `{…}` operand, so the
  /// multi-pattern operators need no exemption. Pinned so the escaping path cannot change it.
  @Test
  func multiPatternOperatorsComposeWithOr() {
    let task = Todo.columns.task
    let id = Todo.columns.id
    #expect(
      rendered(task.likeAllOf(["A%", "%z"]) || id.eq(4))
        == "or=(task.like(all).\"{A%,%z}\",id.eq.4)")
    #expect(
      rendered(task.likeAnyOf(["A%", "%z"]) || id.eq(4))
        == "or=(task.like(any).\"{A%,%z}\",id.eq.4)")
    #expect(
      rendered(task.ilikeAllOf(["a%"]) || id.eq(4))
        == "or=(task.ilike(all).{a%},id.eq.4)")
    #expect(
      rendered(task.ilikeAnyOf(["a%"]) || id.eq(4))
        == "or=(task.ilike(any).{a%},id.eq.4)")
    #expect(
      rendered(task.likeAnyOf(["a,%"]) || id.eq(3))
        == "or=(task.like(any).\"{\\\"a,%\\\"}\",id.eq.3)")
  }
}
