//
//  PostgresChangesE2ETests.swift
//  RealtimeV3IntegrationTests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import PostgREST
import RealtimeV3
import Testing

// MARK: - Helpers

private func makePostgrest() -> PostgrestClient {
  PostgrestClient(
    url: IntegrationEnv.restURL,
    headers: [
      "apikey": IntegrationEnv.anonKey,
      "Authorization": "Bearer \(IntegrationEnv.anonKey)",
    ]
  )
}

/// IE-5: Postgres changes e2e tests against a live local Supabase instance.
///
/// Requires:
///   - `public.messages` table (id uuid pk, room_id uuid, content text, user_id uuid, created_at)
///   - `REPLICA IDENTITY FULL` on `public.messages`
///   - Table added to the `supabase_realtime` publication
///   - RLS permissive for anon role
///
/// Tests are automatically skipped when the instance is not reachable.
@Suite("IE-5 Postgres Changes", .requiresLocalSupabase)
struct PostgresChangesE2ETests {

  // MARK: - IE-5a: INSERT delivers a postgres change

  @Test("inserting a row delivers an INSERT postgres change via realtime")
  func insertDeliversPostgresChange() async throws {
    let roomID = UUID()
    let expectedContent = "hello-\(roomID.uuidString.prefix(8))"

    let rt = IntegrationEnv.makeRealtime()
    let channel = await rt.channel("room:e2e-postgres-insert")

    // Register BEFORE subscribe.
    let token = try await channel.inserts(
      schema: "public",
      table: "messages",
      filter: .eq("room_id", roomID)
    )

    // Open the stream before subscribe so we don't miss the first event.
    let changesStream = await channel.postgresChanges(for: token)

    try await channel.subscribe()
    let state = await channel.state
    try await waitFor(state, timeout: .seconds(10), description: "postgres channel joined") {
      $0 == .joined
    }

    // INSERT via PostgREST.
    let db = makePostgrest()
    try await db.from("messages")
      .insert([
        "room_id": roomID.uuidString,
        "content": expectedContent,
        "user_id": UUID().uuidString,
      ])
      .execute()

    // Wait for the INSERT event to arrive.
    var receivedRow: JSONValue?
    try await withThrowingTaskGroup(of: JSONValue?.self) { group in
      group.addTask {
        for try await row in changesStream {
          return row
        }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: .seconds(15))
        throw TimeoutError(
          description: "did not receive postgres INSERT within timeout",
          timeout: .seconds(15)
        )
      }
      receivedRow = try await group.next()!
      group.cancelAll()
    }

    // The record should contain the expected content field.
    let contentValue = receivedRow?.objectValue?["content"]?.stringValue
    #expect(contentValue == expectedContent)

    try await channel.leave()
    await rt.disconnect()
  }

  // MARK: - IE-5b: UPDATE and DELETE deliver old_record (REPLICA IDENTITY FULL)

  @Test("updating a row delivers UPDATE with old_record; deleting delivers DELETE with old_record")
  func updateAndDeleteDeliverOldRecord() async throws {
    let roomID = UUID()
    let db = makePostgrest()

    // Pre-insert a row we will later UPDATE and DELETE.
    let insertedContent = "original-\(roomID.uuidString.prefix(8))"
    let updatedContent = "updated-\(roomID.uuidString.prefix(8))"
    let rowID = UUID()

    try await db.from("messages")
      .insert([
        "id": rowID.uuidString,
        "room_id": roomID.uuidString,
        "content": insertedContent,
        "user_id": UUID().uuidString,
      ])
      .execute()

    let rt = IntegrationEnv.makeRealtime()
    let channel = await rt.channel("room:e2e-postgres-update-delete")

    let updateToken = try await channel.updates(
      schema: "public",
      table: "messages",
      filter: .eq("room_id", roomID)
    )
    let deleteToken = try await channel.deletes(
      schema: "public",
      table: "messages",
      filter: .eq("room_id", roomID)
    )

    let updatesStream = await channel.postgresChanges(for: updateToken)
    let deletesStream = await channel.postgresChanges(for: deleteToken)

    try await channel.subscribe()
    let state = await channel.state
    try await waitFor(state, timeout: .seconds(10), description: "update/delete channel joined") {
      $0 == .joined
    }

    // UPDATE the row.
    try await db.from("messages")
      .update(["content": updatedContent])
      .eq("id", value: rowID.uuidString)
      .execute()

    // Wait for UPDATE event.
    var receivedUpdate: PostgresUpdate<JSONValue>?
    try await withThrowingTaskGroup(of: PostgresUpdate<JSONValue>?.self) { group in
      group.addTask {
        for try await update in updatesStream {
          return update
        }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: .seconds(15))
        throw TimeoutError(
          description: "did not receive postgres UPDATE within timeout",
          timeout: .seconds(15)
        )
      }
      receivedUpdate = try await group.next()!
      group.cancelAll()
    }

    // New record should have updated content; old_record should have original content.
    #expect(receivedUpdate?.record.objectValue?["content"]?.stringValue == updatedContent)
    #expect(receivedUpdate?.oldRecord?.objectValue?["content"]?.stringValue == insertedContent)

    // DELETE the row.
    try await db.from("messages")
      .delete()
      .eq("id", value: rowID.uuidString)
      .execute()

    // Wait for DELETE event.
    var receivedDelete: PostgresDelete<JSONValue>?
    try await withThrowingTaskGroup(of: PostgresDelete<JSONValue>?.self) { group in
      group.addTask {
        for try await del in deletesStream {
          return del
        }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: .seconds(15))
        throw TimeoutError(
          description: "did not receive postgres DELETE within timeout",
          timeout: .seconds(15)
        )
      }
      receivedDelete = try await group.next()!
      group.cancelAll()
    }

    // Realtime server v2.x returns only the primary key in old_record for DELETE events,
    // even with REPLICA IDENTITY FULL. This is an intentional security constraint in the
    // server: the deleted row no longer exists, so RLS cannot be evaluated for full-row
    // access. The SDK correctly surfaces whatever the server sends (which is the PK only).
    // Verify at minimum the row ID is present in old_record.
    let deletedRowId = receivedDelete?.oldRecord.objectValue?["id"]?.stringValue
    #expect(deletedRowId?.uppercased() == rowID.uuidString.uppercased())

    try await channel.leave()
    await rt.disconnect()
  }
}
