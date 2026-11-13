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
  /// The due date as the server holds it. Views use `localDueDate(calendar:)`.
  var dueAt: Date?
  /// False for a date with no time. `dueAt` is then 00:00 UTC of that day.
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

// A date with no time is a calendar day, not a moment. If the app saved it as midnight on
// the device, a person in a different time zone would see the day before. So the app
// saves 00:00 UTC of the day, and each device reads the day back in its own time zone.
extension Reminder {
  private static var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }

  /// The value to save in `dueAt` for a date with no time.
  ///
  /// - Parameters:
  ///   - date: A moment in the day that the user chose.
  ///   - calendar: The calendar of the user.
  /// - Returns: 00:00 UTC of the chosen day in `calendar`.
  static func storedDay(for date: Date, calendar: Calendar = .current) -> Date {
    let day = calendar.dateComponents([.year, .month, .day], from: date)
    return utcCalendar.date(from: day) ?? date
  }

  /// The due date in the time zone of `calendar`. For a date with no time, this is the
  /// start of the day.
  func localDueDate(calendar: Calendar = .current) -> Date? {
    guard let dueAt else { return nil }
    guard !dueHasTime else { return dueAt }
    let day = Self.utcCalendar.dateComponents([.year, .month, .day], from: dueAt)
    return calendar.date(from: day) ?? dueAt
  }
}
