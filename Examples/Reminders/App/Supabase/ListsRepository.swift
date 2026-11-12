import Foundation
import Supabase

/// All calls for the `lists` table.
struct ListsRepository: Sendable {
  let client: SupabaseClient

  /// The columns that a user can write. The database refuses any other column.
  private struct Values: Encodable {
    let name: String
    let color: String
    let icon: String
  }

  /// Row level security returns only the lists that the user owns or is a member of.
  func fetchAll() async throws -> [ReminderList] {
    try await client.from("lists")
      .select()
      .order("created_at")
      .execute()
      .value
  }

  func create(name: String, color: String, icon: String) async throws -> ReminderList {
    try await client.from("lists")
      .insert(Values(name: name, color: color, icon: icon))
      .select()
      .single()
      .execute()
      .value
  }

  func update(_ list: ReminderList) async throws -> ReminderList {
    if Config.failUpdates { throw SimulatedFailure() }
    return try await client.from("lists")
      .update(Values(name: list.name, color: list.color, icon: list.icon))
      .eq("id", value: list.id)
      .select()
      .single()
      .execute()
      .value
  }

  func delete(id: UUID) async throws {
    try await client.from("lists")
      .delete()
      .eq("id", value: id)
      .execute()
  }
}
