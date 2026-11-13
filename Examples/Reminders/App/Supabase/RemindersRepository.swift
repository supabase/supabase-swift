import Foundation
@_spi(Experimental) import Supabase

/// All calls for the `reminders` table.
struct RemindersRepository: Sendable {
  let client: SupabaseClient

  /// Row level security returns only the reminders of lists that the user can open.
  func fetchAll() async throws -> [Reminder] {
    try await client.from(Reminder.self)
      .select()
      .order { $0.createdAt.asc() }
      .execute()
      .value
  }

  func create(title: String, listID: UUID, dueAt: Date?, isFlagged: Bool) async throws -> Reminder {
    try await client.from(Reminder.self)
      .insert(Reminder.Draft(listID: listID, title: title, dueAt: dueAt, isFlagged: isFlagged))
      .returning()
      .single()
      .execute()
      .value
  }

  /// Sends only the columns that a user can write. The database refuses any other column.
  ///
  /// An update names each column that it writes, so `nil` clears a column: `dueAt = nil`
  /// sends `null`.
  func update(_ reminder: Reminder) async throws -> Reminder {
    if Config.failUpdates { throw SimulatedFailure() }
    return try await client.from(Reminder.self)
      .update {
        $0.listID = reminder.listID
        $0.title = reminder.title
        $0.notes = reminder.notes
        $0.dueAt = reminder.dueAt
        $0.dueHasTime = reminder.dueHasTime
        $0.priority = reminder.priority
        $0.isFlagged = reminder.isFlagged
        $0.completedAt = reminder.completedAt
      }
      .where { $0.id.eq(reminder.id) }
      .returning()
      .single()
      .execute()
      .value
  }

  func delete(id: UUID) async throws {
    try await client.from(Reminder.self)
      .delete()
      .where { $0.id.eq(id) }
      .execute()
  }
}
