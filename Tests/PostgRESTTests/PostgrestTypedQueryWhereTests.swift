//
//  PostgrestTypedQueryWhereTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 26/08/26.
//

import Foundation
import Testing

@testable import PostgREST

@Suite
struct PostgrestTypedQueryWhereTests {
  struct Todo: PostgrestWritableRelation {
    static let relationName = "todos"
    static let schema = "public"
    static let selectString = "*"

    var id: Int
    var isDone: Bool
    var priority: Int
    var dueDate: Date?
    var metadata: String

    struct Columns: Sendable {
      let id = PostgrestColumn<Todo, Int>("id")
      let isDone = PostgrestColumn<Todo, Bool>("is_done")
      let priority = PostgrestColumn<Todo, Int>("priority")
      let dueDate = PostgrestNullableColumn<Todo, Date>("due_at")
      let metadata = PostgrestColumn<Todo, String>("metadata")
    }

    static let columns = Columns()

    static func columnName(for keyPath: PartialKeyPath<Self>) -> String {
      switch keyPath {
      case \Self.id: "id"
      case \Self.isDone: "is_done"
      case \Self.priority: "priority"
      case \Self.dueDate: "due_at"
      case \Self.metadata: "metadata"
      default: fatalError("unmapped key path")
      }
    }

    struct Draft: Encodable, Sendable {
      var id: Int
      var isDone: Bool
      var priority: Int
    }
  }

  @Test
  func whereAppliesAFlatFilter() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select()
      .where { $0.isDone.eq(false) && $0.priority.gt(3) }
      .execute()
    #expect(capture.query?.contains("is_done=eq.false") == true)
    #expect(capture.query?.contains("priority=gt.3") == true)
  }

  /// The target call site, verbatim.
  @Test
  func whereAppliesANestedGroup() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select()
      .where { ($0.isDone.eq(false) && $0.priority.gt(3)) || $0.id.eq(7) }
      .execute()
    #expect(capture.query?.contains("or=(and(is_done.eq.false,priority.gt.3),id.eq.7)") == true)
  }

  /// SQL has one WHERE clause, so the singular name invites the wrong reading. Two calls AND
  /// together.
  @Test
  func repeatedWhereAccumulates() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select()
      .where { $0.isDone.eq(false) }
      .where { $0.priority.gt(3) }
      .execute()
    #expect(capture.query?.contains("is_done=eq.false") == true)
    #expect(capture.query?.contains("priority=gt.3") == true)
  }

  @Test
  func whereWorksOnAMutation() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).delete().where { $0.id.eq(7) }.execute()
    #expect(capture.query?.contains("id=eq.7") == true)
    #expect(capture.httpMethod == "DELETE")
  }

  /// A filter built conditionally inside the closure, so no second entry point is needed.
  @Test
  func aFilterCanBeAssembledInsideTheClosure() async throws {
    let capture = QueryCapture()
    let minimumPriority: Int? = 3
    _ = try await capture.client.from(Todo.self)
      .select()
      .where { c in
        var filter = c.isDone.eq(false)
        if let minimumPriority { filter = filter && c.priority.gte(minimumPriority) }
        return filter
      }
      .execute()
    #expect(capture.query?.contains("is_done=eq.false") == true)
    #expect(capture.query?.contains("priority=gte.3") == true)
  }

  /// The direction is spelled on the column, so two sort keys can differ.
  @Test
  func orderUsesTheNamespaceColumnName() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select().order { $0.dueDate.asc() }.limit(5).execute()
    #expect(capture.query?.contains("order=due_at.asc") == true)
    #expect(capture.query?.contains("limit=5") == true)
  }

  /// A bare column sends no direction, rather than the SDK substituting `.asc`, so PostgREST's
  /// own default applies.
  @Test
  func orderWithoutADirectionSendsTheBareColumn() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().order { $0.dueDate }.execute()
    #expect(capture.query?.contains("order=due_at") == true)
    #expect(capture.query?.contains("order=due_at.asc") == false)
    #expect(capture.query?.contains("order=due_at.desc") == false)
  }

  /// The two spellings coexist as overloads, and a directionless key merges into the same single
  /// `order` parameter as a directed one.
  @Test
  func directedAndDirectionlessKeysMergeInOrder() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select().order { $0.priority.desc() }.order { $0.id }.execute()
    #expect(capture.query?.contains("order=priority.desc,id") == true)
  }

  /// An unspecified placement is not sent, so the database default applies. The string builder
  /// always appends `.nullslast` — see
  /// [SDK-1633](https://linear.app/supabase/issue/SDK-1633).
  @Test
  func nullPlacementIsOmittedUnlessAskedFor() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self).select().order { $0.dueDate.desc() }.execute()
    #expect(capture.query?.contains("order=due_at.desc") == true)
    #expect(capture.query?.contains("nulls") == false)
  }

  @Test
  func nullPlacementIsChainedWhenWanted() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select().order { $0.dueDate.desc().nulls(.first) }.execute()
    #expect(capture.query?.contains("order=due_at.desc.nullsfirst") == true)
  }

  /// Direction and placement are independent on the wire, so asking for a placement must not
  /// force a direction into the query — `order=due_at.nullslast` is a 200.
  @Test
  func aPlacementDoesNotRequireADirection() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select().order { $0.dueDate.nulls(.last) }.execute()
    #expect(capture.query?.contains("order=due_at.nullslast") == true)
    #expect(capture.query?.contains("asc") == false)
    #expect(capture.query?.contains("desc") == false)
  }

  /// Repeated calls merge into one `order` parameter, so the second key breaks ties in the first.
  @Test
  func repeatedOrderAppendsASecondKey() async throws {
    let capture = QueryCapture()
    _ = try await capture.client.from(Todo.self)
      .select().order { $0.priority.desc() }.order { $0.id.asc() }.execute()
    #expect(capture.query?.contains("order=priority.desc,id.asc") == true)
  }

  /// Value semantics: branching two chains off one query must not leak the first chain's filter
  /// into the second.
  @Test
  func branchingTwoChainsDoesNotAlias() async throws {
    let capture = QueryCapture()
    let base = capture.client.from(Todo.self).select()

    _ = try await base.where { $0.isDone.eq(true) }.execute()
    #expect(capture.query?.contains("is_done=eq.true") == true)

    _ = try await base.where { $0.id.gt(5) }.execute()
    #expect(capture.query?.contains("id=gt.5") == true)
    #expect(capture.query?.contains("is_done") == false)
  }
}
