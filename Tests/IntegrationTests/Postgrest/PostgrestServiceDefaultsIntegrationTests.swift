//
//  PostgrestServiceDefaultsIntegrationTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 16/11/26.
//

import Foundation
import HTTPTypes
@_spi(Experimental) import PostgrestMacros
import Testing

/// Typed writes leave `Prefer: return=` and a primary-key `on_conflict` out of the request, so
/// PostgREST applies its own defaults. These tests check that the defaults give the documented
/// result against a real server.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil))
struct PostgrestServiceDefaultsIntegrationTests {
  let client = try! PostgrestClient(
    configuration: .init(
      url: URL(string: "\(DotEnv.supabaseURL)/rest/v1")!,
      headers: [.apikey: DotEnv.supabasePublishableKey]
    )
  )

  private func rows(withID id: UUID) async throws -> [Todos] {
    try await client.from(Todos.self).select().where { $0.id.eq(id) }.execute().value
  }

  private func appliedPreferences(_ headers: HTTPFields) -> String {
    headers[HTTPField.Name("Preference-Applied")!] ?? ""
  }

  @Test
  func insertWithNoOptionsReturnsNoBody() async throws {
    let id = UUID()
    let response = try await client.from(Todos.self)
      .insert(Todos.Draft(id: id, description: "insert default")).execute()

    #expect(response.status.code == 201)
    #expect(response.body.isEmpty)
    #expect(appliedPreferences(response.headers).contains("return=") == false)
    #expect(try await rows(withID: id).map(\.description) == ["insert default"])

    try await client.from(Todos.self).delete().where { $0.id.eq(id) }.execute()
  }

  @Test
  func updateWithNoOptionsReturnsNoBody() async throws {
    let id = UUID()
    try await client.from(Todos.self).insert(Todos.Draft(id: id, description: "before")).execute()

    let response = try await client.from(Todos.self)
      .update { $0.description = "after" }.where { $0.id.eq(id) }.execute()

    #expect(response.status.code == 204)
    #expect(response.body.isEmpty)
    #expect(try await rows(withID: id).map(\.description) == ["after"])

    try await client.from(Todos.self).delete().where { $0.id.eq(id) }.execute()
  }

  @Test
  func deleteWithNoOptionsReturnsNoBody() async throws {
    let id = UUID()
    try await client.from(Todos.self).insert(Todos.Draft(id: id, description: "doomed")).execute()

    let response = try await client.from(Todos.self).delete().where { $0.id.eq(id) }.execute()

    #expect(response.status.code == 204)
    #expect(response.body.isEmpty)
    #expect(try await rows(withID: id).isEmpty)
  }

  @Test
  func deleteCountWithNoReturnPreferenceStillCounts() async throws {
    let id = UUID()
    try await client.from(Todos.self).insert(Todos.Draft(id: id, description: "counted")).execute()

    let response = try await client.from(Todos.self).delete().where { $0.id.eq(id) }
      .execute(count: .exact)

    #expect(response.status.code == 204)
    #expect(response.body.isEmpty)
    #expect(response.count == 1)
  }

  @Test
  func primaryKeyUpsertWithNoConflictTargetInsertsThenMerges() async throws {
    let id = UUID()

    let inserted = try await client.from(Todos.self)
      .upsert(Todos.Draft(id: id, description: "first")).execute()
    #expect(inserted.status.code == 201)
    #expect(inserted.body.isEmpty)
    #expect(appliedPreferences(inserted.headers).contains("resolution=merge-duplicates"))

    let merged = try await client.from(Todos.self)
      .upsert(Todos.Draft(id: id, description: "second")).execute()
    #expect(merged.status.code == 200)
    #expect(merged.body.isEmpty)

    #expect(try await rows(withID: id).map(\.description) == ["second"])

    try await client.from(Todos.self).delete().where { $0.id.eq(id) }.execute()
  }

  @Test
  func primaryKeyUpsertCanIgnoreDuplicatesWithNoConflictTarget() async throws {
    let id = UUID()
    try await client.from(Todos.self).insert(Todos.Draft(id: id, description: "kept")).execute()

    try await client.from(Todos.self)
      .upsert(Todos.Draft(id: id, description: "ignored"), resolution: .ignoreDuplicates)
      .execute()

    #expect(try await rows(withID: id).map(\.description) == ["kept"])

    try await client.from(Todos.self).delete().where { $0.id.eq(id) }.execute()
  }

  @Test
  func bulkPrimaryKeyUpsertMergesEveryRow() async throws {
    let first = UUID()
    let second = UUID()
    try await client.from(Todos.self)
      .insert([
        Todos.Draft(id: first, description: "a"), Todos.Draft(id: second, description: "b"),
      ])
      .execute()

    try await client.from(Todos.self)
      .upsert([
        Todos.Draft(id: first, description: "a2"), Todos.Draft(id: second, description: "b2"),
      ])
      .execute()

    #expect(try await rows(withID: first).map(\.description) == ["a2"])
    #expect(try await rows(withID: second).map(\.description) == ["b2"])

    try await client.from(Todos.self).delete().where { $0.id.in([first, second]) }.execute()
  }

  /// Two drafts where only the first names `is_complete`, which is `NOT NULL DEFAULT false`.
  private func raggedDrafts() -> (ids: [UUID], drafts: [Todos.Draft]) {
    let ids = [UUID(), UUID()]
    return (
      ids,
      [
        Todos.Draft(id: ids[0], description: "a", isComplete: true),
        Todos.Draft(id: ids[1], description: "b"),
      ]
    )
  }

  @Test
  func raggedBulkInsertStoresNullForAMissingColumnByDefault() async throws {
    let (ids, drafts) = raggedDrafts()

    await #expect(throws: PostgrestError.self) {
      try await client.from(Todos.self).insert(drafts).execute()
    }
    #expect(try await rows(withID: ids[1]).isEmpty)
  }

  @Test
  func raggedBulkInsertWithoutDefaultToNullAppliesTheColumnDefault() async throws {
    let (ids, drafts) = raggedDrafts()

    let response = try await client.from(Todos.self)
      .insert(drafts, defaultToNull: false).returning().execute()

    #expect(response.status.code == 201)
    #expect(appliedPreferences(response.headers).contains("missing=default"))
    #expect(response.value.map(\.isComplete) == [true, false])

    try await client.from(Todos.self).delete().where { $0.id.in(ids) }.execute()
  }

  @Test
  func raggedBulkUpsertWithoutDefaultToNullAppliesTheColumnDefault() async throws {
    let (ids, drafts) = raggedDrafts()

    await #expect(throws: PostgrestError.self) {
      try await client.from(Todos.self).upsert(drafts).execute()
    }

    let response = try await client.from(Todos.self)
      .upsert(drafts, defaultToNull: false).returning().execute()

    #expect(response.value.map(\.isComplete) == [true, false])

    try await client.from(Todos.self).delete().where { $0.id.in(ids) }.execute()
  }

  @Test
  func returningStillReturnsTheRows() async throws {
    let id = UUID()

    let inserted = try await client.from(Todos.self)
      .insert(Todos.Draft(id: id, description: "returned")).returning().execute()
    #expect(inserted.status.code == 201)
    #expect(inserted.value.map(\.id) == [id])

    let merged = try await client.from(Todos.self)
      .upsert(Todos.Draft(id: id, description: "returned again")).returning().execute()
    #expect(merged.status.code == 200)
    #expect(merged.value.map(\.description) == ["returned again"])

    let updated = try await client.from(Todos.self)
      .update { $0.description = "updated" }.where { $0.id.eq(id) }.returning().execute()
    #expect(updated.status.code == 200)
    #expect(updated.value.map(\.description) == ["updated"])

    let deleted = try await client.from(Todos.self)
      .delete().where { $0.id.eq(id) }.returning().execute()
    #expect(deleted.status.code == 200)
    #expect(deleted.value.map(\.id) == [id])
  }
}
