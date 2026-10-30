//
//  RealtimeChannelTypedPostgresChangesTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 30/10/26.
//

import Foundation
import Testing

@testable import Realtime
@_spi(Experimental) @testable import Supabase

/// Written out as `@Table("todos")` would expand it. Using the macro here would link the macro
/// plugin into this target, and its sources would count as uncovered lines in the coverage report.
struct RealtimeTodo: _PostgrestRelation, Equatable {
  static let relationName = "todos"
  static let selectString = "id,title,is_done,priority,due_date,tags"

  var id: Int
  var title: String
  var isDone: Bool
  var priority: Int
  var dueDate: Date?
  var tags: [String]?

  enum CodingKeys: String, CodingKey {
    case id, title, priority, tags
    case isDone = "is_done"
    case dueDate = "due_date"
  }

  struct Columns: Sendable {
    let id = _PostgrestColumn<RealtimeTodo, Int>("id")
    let title = _PostgrestColumn<RealtimeTodo, String>("title")
    let isDone = _PostgrestColumn<RealtimeTodo, Bool>("is_done")
    let priority = _PostgrestColumn<RealtimeTodo, Int>("priority")
    let dueDate = _PostgrestNullableColumn<RealtimeTodo, Date>("due_date")
    let tags = _PostgrestNullableColumn<RealtimeTodo, [String]>("tags")
  }

  static let columns = Columns()
}

@Suite
struct RealtimeChannelTypedPostgresChangesTests {
  typealias Filter = _PostgrestFilter<RealtimeTodo>

  static let renderings: [(Filter, String)] = {
    let c = RealtimeTodo.columns
    return [
      (c.id.eq(1), "id=eq.1"),
      (c.id.neq(1), "id=neq.1"),
      (c.priority.gt(3), "priority=gt.3"),
      (c.priority.gte(3), "priority=gte.3"),
      (c.priority.lt(3), "priority=lt.3"),
      (c.priority.lte(3), "priority=lte.3"),
      (c.priority.in([1, 2, 3]), "priority=in.(1,2,3)"),
      (c.title.like("%milk%"), "title=like.%milk%"),
      (c.title.ilike("%milk%"), "title=ilike.%milk%"),
      (c.title.regexMatch("^a"), "title=match.^a"),
      (c.title.regexIMatch("^a"), "title=imatch.^a"),
      (c.dueDate.isNull(), "due_date=is.null"),
      (c.isDone.isTrue(), "is_done=is.true"),
      (c.isDone.isFalse(), "is_done=is.false"),
      (c.priority.isDistinct(3), "priority=isdistinct.3"),
      (!c.id.eq(1), "id=not.eq.1"),
      (!(!c.id.eq(1)), "id=eq.1"),
      (!c.dueDate.isNull(), "due_date=not.is.null"),
      (c.title.eq("a,b"), #"title=eq."a,b""#),
      (c.title.in(["a,b", "c"]), #"title=in.("a,b",c)"#),
      (c.title.raw("eq.milk"), "title=eq.milk"),
      (!c.title.raw("eq.milk"), "title=not.eq.milk"),
      (
        c.id.eq(1) && c.isDone.isFalse() && !c.priority.gt(3),
        "id=eq.1,is_done=is.false,priority=not.gt.3"
      ),
      (c.id.eq(1) && (c.priority.gt(3) && c.title.eq("x")), "id=eq.1,priority=gt.3,title=eq.x"),
    ]
  }()

  @Test(arguments: renderings)
  func rendersTheRealtimeFilterGrammar(filter: Filter, expected: String) {
    #expect(filter.realtimeFilter == expected)
  }

  #if os(macOS) || os(Linux)
    @Test
    func trapsOnAnOrFilter() async {
      await #expect(processExitsWith: .failure) {
        let c = RealtimeTodo.columns
        _ = (c.id.eq(1) || c.id.eq(2)).realtimeFilter
      }
    }

    @Test
    func trapsOnANegatedGroup() async {
      await #expect(processExitsWith: .failure) {
        let c = RealtimeTodo.columns
        _ = (!(c.id.eq(1) && c.id.eq(2))).realtimeFilter
      }
    }

    @Test
    func trapsOnAnOperatorRealtimeDoesNotSupport() async {
      await #expect(processExitsWith: .failure) {
        _ = RealtimeTodo.columns.tags.contains(["home"]).realtimeFilter
      }
    }
  #endif

  @Test
  func streamsTypedChangesForTheRelationTableAndFilter() async throws {
    let client = RealtimeClient(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions()
    )
    let channel = await client.channel("todos")

    let changes = await channel.postgresChanges(
      for: RealtimeTodo.self, event: .insert, where: { $0.priority.gt(3) && $0.title.eq("milk") }
    )

    let expectedConfig = PostgresJoinConfig(
      event: .insert, schema: "public", table: "todos", filter: "priority=gt.3,title=eq.milk"
    )
    #expect(await channel.clientChanges == [expectedConfig])

    await channel.setServerChanges([
      PostgresJoinConfig(
        event: .insert, schema: "public", table: "todos", filter: "priority=gt.3,title=eq.milk",
        id: 1)
    ])
    await channel.onMessage(
      RealtimeMessage(
        joinRef: nil,
        ref: nil,
        topic: "realtime:todos",
        event: ChannelEvent.postgresChanges,
        payload: [
          "ids": [1],
          "data": [
            "type": "INSERT",
            "schema": "public",
            "table": "todos",
            "commit_timestamp": "2026-10-30T12:00:00.000Z",
            "record": [
              "id": 1, "title": "milk", "is_done": false, "priority": 5,
              "due_date": "2026-10-31T09:30:00.000Z", "tags": ["home"],
            ],
          ],
        ]
      )
    )
    await channel.finishStreams()

    var received: [TypedPostgresChange<RealtimeTodo>] = []
    for await change in changes {
      received.append(change)
    }

    #expect(received.map(\.kind) == [.insert])
    #expect(
      try received.first?.row()
        == RealtimeTodo(
          id: 1, title: "milk", isDone: false, priority: 5,
          dueDate: Date(timeIntervalSince1970: 1_793_439_000), tags: ["home"]
        )
    )
  }

  @Test
  func usesTheRelationSchemaAndNoFilterByDefault() async {
    enum PrivateSchema: _PostgrestSchema {
      static let name = "private"
    }

    struct Secret: _PostgrestRelation {
      typealias Schema = PrivateSchema
      static let relationName = "secrets"
      static let selectString = "*"

      var id: Int

      struct Columns: Sendable {}

      static let columns = Columns()
    }

    let client = RealtimeClient(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions()
    )
    let channel = await client.channel("secrets")

    let changes = await channel.postgresChanges(for: Secret.self)
    withExtendedLifetime(changes) {}

    let configs = await channel.clientChanges
    #expect(configs == [PostgresJoinConfig(event: .all, schema: "private", table: "secrets")])
    #expect(configs.map(\.event) == [.all])
  }
}

extension RealtimeChannel {
  fileprivate func setServerChanges(_ changes: [PostgresJoinConfig]) {
    serverChanges = changes
  }
}
