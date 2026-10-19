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
  struct Todo: _PostgrestRelation {
    static let relationName = "todos"
    static let selectString = "*"

    var id: Int
    var task: String
    var note: String?

    struct Columns: Sendable {
      let id = _PostgrestColumn<Todo, Int>("id")
      let task = _PostgrestColumn<Todo, String>("task")
      let note = _PostgrestNullableColumn<Todo, String>("note")
    }

    static let columns = Columns()
  }

  private func rendered(_ filter: _PostgrestFilter<Todo>) -> String {
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

  @Test
  func multiPatternOperatorsRenderABracedArray() {
    let task = Todo.columns.task
    #expect(rendered(task.likeAllOf(["A%", "%z"])) == "task=like(all).{A%,%z}")
    #expect(rendered(task.likeAnyOf(["A%", "%z"])) == "task=like(any).{A%,%z}")
    #expect(rendered(task.ilikeAllOf(["a%"])) == "task=ilike(all).{a%}")
    #expect(rendered(task.ilikeAnyOf(["a%"])) == "task=ilike(any).{a%}")
  }

  @Test
  func emptyListsRenderAnEmptyLiteral() {
    #expect(rendered(Todo.columns.task.likeAllOf([])) == "task=like(all).{}")
    #expect(rendered(Todo.columns.task.likeAnyOf([])) == "task=like(any).{}")
    #expect(rendered(Todo.columns.id.in([])) == "id=in.()")
  }

  @Test
  func listOperatorsRenderAParenthesisedList() {
    #expect(rendered(Todo.columns.id.in([1, 2, 3])) == "id=in.(1,2,3)")
    #expect(rendered(!Todo.columns.id.in([1, 2])) == "id=not.in.(1,2)")
  }

  @Test
  func listMembersAreEscaped() {
    #expect(rendered(Todo.columns.task.in(["a,b"])) == "task=in.(\"a,b\")")
    #expect(rendered(Todo.columns.task.in(["p(q)", "Ada"])) == "task=in.(\"p(q)\",Ada)")
  }

  @Test
  func multiPatternMembersAreEscaped() {
    #expect(rendered(Todo.columns.task.likeAnyOf(["a,%"])) == "task=like(any).{\"a,%\"}")
    #expect(rendered(Todo.columns.task.likeAnyOf(["a{b"])) == "task=like(any).{\"a{b\"}")
  }

  @Test
  func nullableColumnsTakePatternAndListOperators() {
    #expect(rendered(Todo.columns.note.like("Jo%")) == "note=like.Jo%")
    #expect(rendered(Todo.columns.note.in(["a", "b"])) == "note=in.(a,b)")
  }

  @Test
  func inKeepsItsListParensBareInsideAGroup() {
    #expect(
      rendered(Todo.columns.id.in([2, 3]) || Todo.columns.id.eq(4))
        == "or=(id.in.(2,3),id.eq.4)")
  }

  @Test
  func negatedInInsideAGroupKeepsItsListParensBare() {
    #expect(
      rendered(!Todo.columns.id.in([2, 3]) || Todo.columns.id.eq(4))
        == "or=(id.not.in.(2,3),id.eq.4)")
  }

  @Test
  func inEscapesItsListMembersInsideAGroup() {
    #expect(
      rendered(Todo.columns.task.in(["p(q)", "Ada"]) || Todo.columns.id.eq(4))
        == "or=(task.in.(\"p(q)\",Ada),id.eq.4)")
  }

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
