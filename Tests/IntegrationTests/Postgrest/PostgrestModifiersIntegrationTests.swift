//
//  PostgrestModifiersIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 16/11/26.
//

import Foundation
import PostgREST
@_spi(Experimental) import PostgrestMacros
import Testing

@SelectionOf(Posts.self)
struct PostsPerAuthor: Hashable {
  var author: String
  @Aggregate(.sum, of: \Posts.id) var idTotal: Double?
  @Aggregate(.avg, of: \Posts.discussionID) var meanDiscussion: Double?
  @Aggregate(.count) var rows: Int
}

extension Posts.Columns {
  var modifiersIDSum: _PostgrestAggregate<Posts, Double> { id.sum() }
  var modifiersIDAvg: _PostgrestAggregate<Posts, Double> { id.avg() }
  var modifiersIDText: _PostgrestDerivedExpression<Posts, String, _PostgrestSelectOnly> {
    id.cast(to: .text)
  }
}

@SelectionOf(Posts.self)
struct PostsIDStatistics: Hashable {
  var modifiersIDSum: Int?
  var modifiersIDAvg: Double?
}

@SelectionOf(Posts.self)
struct PostIDAsText: Hashable {
  var id: Int
  var modifiersIDText: String
}

/// Request modifiers and filters that only the server can prove: each test checks what PostgREST
/// does with the header or parameter the SDK sends, not the request itself.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestModifiersIntegrationTests {
  /// The rows `seed.sql` adds to `users`. Other suites insert and delete users of their own, so
  /// the tests scope every read to these.
  static let seededUsernames = ["supabot", "kiwicopple", "awailas", "dragarcia"]

  let client = try! PostgrestClient(
    configuration: .init(
      url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
      headers: [.apikey: DotEnv.supabasePublishableKey]
    )
  )

  struct Todo: Decodable, Equatable {
    var description: String
    var isComplete: Bool

    enum CodingKeys: String, CodingKey {
      case description
      case isComplete = "is_complete"
    }
  }

  private func insertTodos(_ count: Int, tag: String) async throws {
    let rows = Array(repeating: ["description": tag], count: count)
    try await client.from("todos").insert(rows).execute()
  }

  private func todos(tagged tag: String) async throws -> [Todo] {
    try await client.from("todos").select("description,is_complete")
      .eq("description", value: tag).execute().value
  }

  private func deleteTodos(tagged tag: String) async throws {
    try await client.from("todos").delete().eq("description", value: tag).execute()
  }

  // MARK: - maxAffected

  @Test
  func maxAffectedRejectsAnUpdateThatTouchesTooManyRowsAndRollsItBack() async throws {
    let tag = "max-affected-\(UUID().uuidString)"
    try await insertTodos(3, tag: tag)

    let error = await #expect(throws: PostgrestError.self) {
      try await client.from("todos").update(["is_complete": true])
        .eq("description", value: tag)
        .maxAffected(2)
        .execute()
    }
    #expect(error?.kind == .server)
    #expect(error?.code == "PGRST124")
    #expect(try await todos(tagged: tag).allSatisfy { !$0.isComplete })

    try await client.from("todos").update(["is_complete": true])
      .eq("description", value: tag)
      .maxAffected(3)
      .execute()
    #expect(try await todos(tagged: tag).allSatisfy(\.isComplete))

    try await client.from("todos").delete().eq("description", value: tag).maxAffected(3).execute()
    #expect(try await todos(tagged: tag).isEmpty)
  }

  @Test
  func typedMaxAffectedRejectsADeleteThatTouchesTooManyRows() async throws {
    let tag = "typed-max-affected-\(UUID().uuidString)"
    try await insertTodos(2, tag: tag)

    let error = await #expect(throws: PostgrestError.self) {
      try await client.from(Todos.self).delete()
        .where { $0.description.eq(tag) }
        .maxAffected(1)
        .execute()
    }
    #expect(error?.code == "PGRST124")
    #expect(try await todos(tagged: tag).count == 2)

    try await client.from(Todos.self).delete()
      .where { $0.description.eq(tag) }
      .maxAffected(2)
      .execute()
    #expect(try await todos(tagged: tag).isEmpty)
  }

  // MARK: - explain

  @Test
  func explainReturnsThePlanInsteadOfTheRows() async throws {
    let text = try await client.from("users").select()
      .in("username", values: Self.seededUsernames)
      .explain()
      .execute()
      .string()
    #expect(text?.contains("Scan") == true)
    #expect(text?.hasPrefix("[") == false)

    let analyzed = try await client.from("users").select()
      .explain(analyze: true, format: .json)
      .execute()
      .body
    let plans = try JSONSerialization.jsonObject(with: analyzed) as? [[String: Any]]
    let plan = try #require(plans?.first?["Plan"] as? [String: Any])
    #expect(plan["Actual Rows"] != nil)
  }

  @Test
  func typedExplainReturnsThePlan() async throws {
    let plan = try await client.from(Users.self).select()
      .where { $0.username.eq("supabot") }
      .explain(analyze: true)
      .execute()
      .value
    #expect(plan.contains("actual time"))
  }

  // MARK: - geojson

  @Test
  func geojsonReturnsAFeatureCollection() async throws {
    let body = try await client.schema("personal").from("places").select("id,name,location")
      .order("id")
      .geojson()
      .execute()
      .body
    let collection = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(collection["type"] as? String == "FeatureCollection")
    let features = try #require(collection["features"] as? [[String: Any]])
    let geometries = features.compactMap { $0["geometry"] as? [String: Any] }
    #expect(geometries.map { $0["type"] as? String } == ["Point", "Point"])
    #expect(geometries.first?["coordinates"] as? [Double] == [0, 0])
    let names = features.compactMap { ($0["properties"] as? [String: Any])?["name"] as? String }
    #expect(names == ["origin", "lisbon"])
  }

  // MARK: - stripNulls

  @Test
  func stripNullsLeavesNullFieldsOutOfTheBody() async throws {
    let kept = try await client.from("users").select("username,email")
      .eq("username", value: "supabot")
      .execute()
      .body
    #expect(
      try JSONSerialization.jsonObject(with: kept) as? [[String: String?]] == [
        ["username": "supabot", "email": nil]
      ])

    let stripped = try await client.from("users").select("username,email")
      .eq("username", value: "supabot")
      .stripNulls()
      .execute()
      .body
    #expect(
      try JSONSerialization.jsonObject(with: stripped) as? [[String: String]] == [
        ["username": "supabot"]
      ])
  }

  @Test
  func typedStripNullsStillDecodesTheOptionalFields() async throws {
    let response = try await client.from(Users.self).select()
      .where { $0.username.eq("supabot") }
      .stripNulls()
      .execute()
    #expect(response.value.map(\.username) == ["supabot"])
    #expect(response.value.first?.email == nil)
    let rows = try JSONSerialization.jsonObject(with: response.body) as? [[String: Any]]
    #expect(rows?.first?.keys.contains("email") == false)
  }

  // MARK: - isDistinct and imatch

  struct Username: Decodable, Equatable {
    var username: String
  }

  @Test
  func isDistinctMatchesRowsWhoseValueDiffers() async throws {
    let rows: [Username] = try await client.from("users").select("username")
      .in("username", values: Self.seededUsernames)
      .isDistinct("status", value: "ONLINE")
      .execute()
      .value
    #expect(rows == [Username(username: "kiwicopple")])

    let typed = try await client.from(Users.self).select()
      .where { $0.username.in(Self.seededUsernames) && $0.status.isDistinct(.online) }
      .execute()
      .value
    #expect(typed.map(\.username) == ["kiwicopple"])
  }

  @Test
  func imatchIsACaseInsensitiveRegularExpression() async throws {
    let rows: [Username] = try await client.from("users").select("username")
      .imatch("username", pattern: "^KIWI")
      .execute()
      .value
    #expect(rows == [Username(username: "kiwicopple")])
  }

  // MARK: - schema(_:)

  struct Note: Codable, Equatable {
    var body: String
  }

  @Test
  func schemaSendsTheProfileHeadersForReadsAndWrites() async throws {
    let body = "personal-\(UUID().uuidString)"
    let personal = client.schema("personal")

    let inserted: Note = try await personal.from("notes").insert(Note(body: body))
      .select("body").single().execute().value
    #expect(inserted == Note(body: body))

    let read: [Note] = try await personal.from("notes").select("body")
      .eq("body", value: body).execute().value
    #expect(read == [Note(body: body)])

    let inPublic: [Note] = try await client.from("notes").select("body")
      .eq("body", value: body).execute().value
    #expect(inPublic.isEmpty)

    let typed = try await client.schema(Personal.self).from(PersonalNotes.self).select()
      .where { $0.body.eq(body) }
      .execute()
      .value
    #expect(typed.map(\.body) == [body])

    try await personal.from("notes").delete().eq("body", value: body).execute()
  }

  // MARK: - head and count

  @Test
  func headSelectReturnsTheCountWithoutABody() async throws {
    let response = try await client.from("users")
      .select("*", head: true, count: .exact)
      .in("username", values: Self.seededUsernames)
      .execute()
    #expect(response.count == 4)
    #expect(response.body.isEmpty)
  }

  @Test
  func typedCountReturnsTheNumberOfMatchingRows() async throws {
    let online = try await client.from(Users.self).select()
      .where { $0.username.in(Self.seededUsernames) && $0.status.eq(.online) }
      .count(.exact)
    #expect(online == 3)
  }

  // MARK: - timeout

  @Test
  func perRequestTimeoutFailsASlowRequest() async throws {
    let start = ContinuousClock.now
    let error = await #expect(throws: PostgrestError.self) {
      try await client.rpc("sleep_for", params: ["seconds": 5])
        .timeout(.milliseconds(500))
        .execute()
    }
    #expect(error?.kind == .transport)
    #expect(ContinuousClock.now - start < .seconds(4))

    try await client.rpc("sleep_for", params: ["seconds": 0.2])
      .timeout(.seconds(10))
      .execute()
  }

  // MARK: - defaultToNull

  @Test
  func defaultToNullFalseFillsMissingColumnsWithTheirDefaults() async throws {
    let tag = "missing-default-\(UUID().uuidString)"
    let rows: [[String: JSONValue]] = [
      ["description": .string(tag), "is_complete": .bool(true)],
      ["description": .string(tag)],
    ]

    let error = await #expect(throws: PostgrestError.self) {
      try await client.from("todos").insert(rows).execute()
    }
    #expect(error?.code == .notNullViolation)

    let inserted: [Todo] = try await client.from("todos")
      .insert(rows, defaultToNull: false)
      .select("description,is_complete")
      .execute()
      .value
    #expect(
      inserted == [
        Todo(description: tag, isComplete: true), Todo(description: tag, isComplete: false),
      ])

    try await deleteTodos(tagged: tag)
  }

  // MARK: - Aggregates and casts

  @Test
  func aggregateSelectionGroupsByThePlainColumns() async throws {
    let rows = try await client.from(Posts.self)
      .select(PostsPerAuthor.self)
      .execute()
      .value
    #expect(
      Set(rows) == [
        PostsPerAuthor(author: "ada", idTotal: 4, meanDiscussion: 1, rows: 2),
        PostsPerAuthor(author: "bob", idTotal: 7, meanDiscussion: 2.5, rows: 2),
        PostsPerAuthor(author: "cy", idTotal: 4, meanDiscussion: 2, rows: 1),
      ])
  }

  @Test
  func sumAndAvgOverTheWholeRelation() async throws {
    let rows = try await client.from(Posts.self)
      .select(PostsIDStatistics.self)
      .execute()
      .value
    #expect(rows == [PostsIDStatistics(modifiersIDSum: 15, modifiersIDAvg: 3)])
  }

  /// `modifiersIDText` decodes as a `String` only when the server sends the id as JSON text.
  @Test
  func castReturnsTheColumnAsTheTargetType() async throws {
    let rows = try await client.from(Posts.self)
      .select(PostIDAsText.self)
      .where { $0.id.lte(2) }
      .order { $0.id }
      .execute()
      .value
    #expect(
      rows == [
        PostIDAsText(id: 1, modifiersIDText: "1"), PostIDAsText(id: 2, modifiersIDText: "2"),
      ])
  }

  // MARK: - Typed all()

  /// `all()` adds no filter, so the write reaches Postgres with no `WHERE` clause. The stack
  /// loads `pg-safeupdate`, which refuses exactly that (code 21000), so the refusal proves the
  /// server saw an unfiltered delete. The same delete with a filter goes through.
  @Test
  func typedAllSendsAWriteWithNoFilter() async throws {
    let tag = "typed-all-\(UUID().uuidString)"
    try await insertTodos(2, tag: tag)
    let total = try await client.from(Todos.self).select().count(.exact)

    let error = await #expect(throws: PostgrestError.self) {
      try await client.from(Todos.self).delete().all().execute()
    }
    #expect(error?.code == "21000")
    #expect(try await client.from(Todos.self).select().count(.exact) == total)

    try await client.from(Todos.self).delete().where { $0.description.eq(tag) }.execute()
    #expect(try await todos(tagged: tag).isEmpty)
  }
}
