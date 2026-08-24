//
//  PostgrestTypedQueryFilterTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestTypedQueryFilterTests {
  struct Todo: PostgrestRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var task: String
    var isDone: Bool
    var dueDate: Date?

    static func columnName<V>(for keyPath: KeyPath<Self, V>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.task: "task"
      case \Self.isDone: "is_done"
      case \Self.dueDate: "due_date"
      default: fatalError("unmapped key path")
      }
    }
  }

  @Test
  func eqUsesTheMappedColumnName() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().eq(\.isDone, false).execute()
    #expect(capture.query?.contains("is_done=eq.false") == true)
  }

  @Test
  func comparisonOperatorsRenderTheirPrefix() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().gt(\.id, 10).lte(\.id, 20).execute()
    #expect(capture.query?.contains("id=gt.10") == true)
    #expect(capture.query?.contains("id=lte.20") == true)
  }

  @Test
  func inRendersAParenthesisedList() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().in(\.task, ["a", "b"]).execute()
    #expect(capture.query?.contains("task=in.(a,b)") == true)
  }

  @Test
  func isNullAndIsNotNullRenderCorrectly() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().isNull(\.dueDate).execute()
    #expect(capture.query?.contains("due_date=is.null") == true)

    let other = QueryCapture()
    _ = try await other.client.from(Todo.self).select().isNotNull(\.dueDate).execute()
    #expect(other.query?.contains("due_date=not.is.null") == true)
  }

  /// The typed wrappers hold value-typed builders, so two chains branched off one query are
  /// independent. Under the old class-based builders the second request also carried the first
  /// chain's filter.
  @Test
  func branchingTwoChainsOffOneQueryDoesNotAlias() async throws {
    let capture = QueryCapture()
    let base = capture.client.from(Todo.self).select()

    _ = try await base.eq(\.isDone, true).execute()
    #expect(capture.query?.contains("is_done=eq.true") == true)

    _ = try await base.gt(\.id, 5).execute()
    #expect(capture.query?.contains("id=gt.5") == true)
    #expect(capture.query?.contains("is_done") == false)
  }

  @Test
  func orderAndLimitUseTheMappedColumnName() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select().order(\.dueDate, ascending: false).limit(5).execute()
    #expect(capture.query?.contains("order=due_date.desc") == true)
    #expect(capture.query?.contains("limit=5") == true)
  }
}
