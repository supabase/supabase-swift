import Foundation
@_spi(Experimental) import Supabase

/// All calls for the `lists` table.
struct ListsRepository: Sendable {
  let client: SupabaseClient

  /// Row level security returns only the lists that the user owns or is a member of.
  func fetchAll() async throws -> [ReminderList] {
    try await client.from(ReminderList.self)
      .select()
      .order { $0.createdAt.asc() }
      .execute()
      .value
  }

  /// The server sets the id, the owner and the dates.
  func create(name: String, color: String, icon: String) async throws -> ReminderList {
    try await client.from(ReminderList.self)
      .insert(ReminderList.Draft(name: name, color: color, icon: icon))
      .returning()
      .single()
      .execute()
      .value
  }

  /// Sends only the columns that a user can write. The database refuses any other column.
  func update(_ list: ReminderList) async throws -> ReminderList {
    if Config.failUpdates { throw SimulatedFailure() }
    return try await client.from(ReminderList.self)
      .update {
        $0.name = list.name
        $0.color = list.color
        $0.icon = list.icon
      }
      .where { $0.id.eq(list.id) }
      .returning()
      .single()
      .execute()
      .value
  }

  func delete(id: UUID) async throws {
    try await client.from(ReminderList.self)
      .delete()
      .where { $0.id.eq(id) }
      .execute()
  }
}
