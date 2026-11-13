import Foundation

// `Database.swift` declares the rows of the `public` schema as `@Table` structs. The
// generator names each struct after its table. These names are the ones the app uses.
// Regenerate the file after each change to the schema (see the README).

typealias Profile = Profiles
typealias ReminderList = Lists
typealias Reminder = Reminders
typealias ListMember = ListMembers
typealias Invitation = ListInvitations
typealias Attachment = ReminderAttachments

extension Profiles: Identifiable {}
extension Lists: Identifiable {}
extension ListInvitations: Identifiable {}
extension ReminderAttachments: Identifiable {}

/// - `dueAt` is the due date as the server holds it. Views use `localDueDate(calendar:)`.
/// - `dueHasTime` is false for a date with no time. `dueAt` is then 00:00 UTC of that day.
/// - `priority` 0 is none, 1 is low, 2 is medium, 3 is high.
extension Reminders: Identifiable {
  var isCompleted: Bool { completedAt != nil }
}

/// An invitation that waits for the current user, from the `my_invitations()` function.
///
/// The columns of a function result can be null in Postgres, so each field of the
/// generated `MyInvitationsRow` is optional. `SharingRepository` checks them.
struct IncomingInvitation: Identifiable, Hashable, Sendable {
  let id: UUID
  let listName: String
  let inviterName: String
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
