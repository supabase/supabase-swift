import Foundation
import Supabase

/// All calls for the `reminders` table.
struct RemindersRepository: Sendable {
  let client: SupabaseClient

  /// Row level security returns only the reminders of lists that the user can open.
  func fetchAll() async throws -> [Reminder] {
    try await client.from("reminders")
      .select()
      .order("created_at")
      .execute()
      .value
  }

  func create(title: String, listID: UUID, dueAt: Date?, isFlagged: Bool) async throws -> Reminder {
    try await client.from("reminders")
      .insert(NewReminderValues(listID: listID, title: title, dueAt: dueAt, isFlagged: isFlagged))
      .select()
      .single()
      .execute()
      .value
  }

  func update(_ reminder: Reminder) async throws -> Reminder {
    if Config.failUpdates { throw SimulatedFailure() }
    return try await client.from("reminders")
      .update(ReminderValues(reminder: reminder))
      .eq("id", value: reminder.id)
      .select()
      .single()
      .execute()
      .value
  }

  func delete(id: UUID) async throws {
    try await client.from("reminders")
      .delete()
      .eq("id", value: id)
      .execute()
  }
}

/// The columns that a user can write. The database refuses any other column.
private struct ReminderValues: Encodable {
  let reminder: Reminder

  enum CodingKeys: String, CodingKey {
    case title, notes, priority
    case listID = "list_id"
    case dueAt = "due_at"
    case dueHasTime = "due_has_time"
    case isFlagged = "is_flagged"
    case completedAt = "completed_at"
  }

  // The default `Encodable` code leaves out a `nil` value. The update would then keep
  // the old date. `encode` writes `null`, which clears the column.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(reminder.listID, forKey: .listID)
    try container.encode(reminder.title, forKey: .title)
    try container.encode(reminder.notes, forKey: .notes)
    try container.encode(reminder.dueAt, forKey: .dueAt)
    try container.encode(reminder.dueHasTime, forKey: .dueHasTime)
    try container.encode(reminder.priority, forKey: .priority)
    try container.encode(reminder.isFlagged, forKey: .isFlagged)
    try container.encode(reminder.completedAt, forKey: .completedAt)
  }
}

private struct NewReminderValues: Encodable {
  let listID: UUID
  let title: String
  let dueAt: Date?
  let isFlagged: Bool

  enum CodingKeys: String, CodingKey {
    case title
    case listID = "list_id"
    case dueAt = "due_at"
    case isFlagged = "is_flagged"
  }
}
