import Foundation

// Rows of the `public` schema. Each type decodes one table (or one function result).
// The coding keys are the column names.

struct Profile: Codable, Identifiable, Hashable, Sendable {
  let id: UUID
  var email: String
  var displayName: String

  enum CodingKeys: String, CodingKey {
    case id, email
    case displayName = "display_name"
  }
}

struct ReminderList: Codable, Identifiable, Hashable, Sendable {
  let id: UUID
  let ownerID: UUID
  var name: String
  var color: String
  var icon: String
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id, name, color, icon
    case ownerID = "owner_id"
    case createdAt = "created_at"
  }
}

struct Reminder: Codable, Identifiable, Hashable, Sendable {
  let id: UUID
  var listID: UUID
  var title: String
  var notes: String
  var dueAt: Date?
  /// False for a date with no time. `dueAt` is then the start of that day on the device.
  var dueHasTime: Bool
  /// 0 is none, 1 is low, 2 is medium, 3 is high.
  var priority: Int
  var isFlagged: Bool
  var completedAt: Date?
  let createdBy: UUID?
  let createdAt: Date
  var updatedAt: Date

  var isCompleted: Bool { completedAt != nil }

  enum CodingKeys: String, CodingKey {
    case id, title, notes, priority
    case listID = "list_id"
    case dueAt = "due_at"
    case dueHasTime = "due_has_time"
    case isFlagged = "is_flagged"
    case completedAt = "completed_at"
    case createdBy = "created_by"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

struct ListMember: Codable, Hashable, Sendable {
  let listID: UUID
  let userID: UUID
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case listID = "list_id"
    case userID = "user_id"
    case createdAt = "created_at"
  }
}

struct Invitation: Codable, Identifiable, Hashable, Sendable {
  let id: UUID
  let listID: UUID
  let invitedEmail: String
  let invitedBy: UUID
  /// `pending`, `accepted` or `declined`.
  let status: String
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id, status
    case listID = "list_id"
    case invitedEmail = "invited_email"
    case invitedBy = "invited_by"
    case createdAt = "created_at"
  }
}

/// A row of the `my_invitations()` function: an invitation that waits for the current user.
struct IncomingInvitation: Codable, Identifiable, Hashable, Sendable {
  let id: UUID
  let listName: String
  let inviterName: String

  enum CodingKeys: String, CodingKey {
    case id
    case listName = "list_name"
    case inviterName = "inviter_name"
  }
}

struct Attachment: Codable, Identifiable, Hashable, Sendable {
  let id: UUID
  let reminderID: UUID
  let storagePath: String
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case reminderID = "reminder_id"
    case storagePath = "storage_path"
    case createdAt = "created_at"
  }
}

/// The error that update calls throw when `Config.failUpdates` is on.
struct SimulatedFailure: LocalizedError {
  var errorDescription: String? { "Simulated update failure." }
}
