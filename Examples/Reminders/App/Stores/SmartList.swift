import Foundation

/// The built-in lists that collect reminders from every list.
enum SmartList: String, CaseIterable, Identifiable, Sendable {
  case today, scheduled, all, flagged, completed

  var id: String { rawValue }

  var title: String {
    switch self {
    case .today: "Today"
    case .scheduled: "Scheduled"
    case .all: "All"
    case .flagged: "Flagged"
    case .completed: "Completed"
    }
  }

  /// An SF Symbol name.
  var symbol: String {
    switch self {
    case .today: "calendar"
    case .scheduled: "calendar.badge.clock"
    case .all: "tray.fill"
    case .flagged: "flag.fill"
    case .completed: "checkmark"
    }
  }

  /// A color name from `ListStyle.colors`.
  var color: String {
    switch self {
    case .today: "blue"
    case .scheduled: "red"
    case .all: "indigo"
    case .flagged: "orange"
    case .completed: "brown"
    }
  }

  /// The reminders that belong to this list, in the order of `reminders`.
  ///
  /// - Parameters:
  ///   - reminders: The reminders of every list.
  ///   - now: The current time. Tests pass a fixed value.
  ///   - calendar: The calendar that decides where a day ends.
  func filter(
    _ reminders: [Reminder],
    now: Date = .now,
    calendar: Calendar = .current
  ) -> [Reminder] {
    switch self {
    case .today:
      // Today also shows what is overdue.
      let startOfToday = calendar.startOfDay(for: now)
      guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
        return []
      }
      return reminders.filter { reminder in
        guard !reminder.isCompleted, let dueAt = reminder.dueAt else { return false }
        return dueAt < startOfTomorrow
      }
    case .scheduled:
      return reminders.filter { !$0.isCompleted && $0.dueAt != nil }
    case .all:
      return reminders.filter { !$0.isCompleted }
    case .flagged:
      return reminders.filter { !$0.isCompleted && $0.isFlagged }
    case .completed:
      return reminders.filter(\.isCompleted)
    }
  }
}

/// What a reminder list screen shows: one list, or a smart list over every list.
enum ReminderSource: Hashable, Sendable {
  case list(UUID)
  case smart(SmartList)
}

#if DEBUG
  extension SmartList {
    /// Checks the filter rules with fixed dates. A debug build runs it at launch.
    ///
    /// The case that matters most is a date with no time: it belongs to a day in the
    /// time zone of the device, not in UTC.
    static func selfTest() {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
      func local(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(
          from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
      }
      // 23:30 in São Paulo is 02:30 of the next day in UTC.
      let now = local(12, 23, 30)

      func reminder(
        _ title: String,
        due: Date? = nil,
        hasTime: Bool = false,
        flagged: Bool = false,
        completed: Bool = false
      ) -> Reminder {
        Reminder(
          id: UUID(), listID: UUID(), title: title, notes: "", dueAt: due, dueHasTime: hasTime,
          priority: 0, isFlagged: flagged, completedAt: completed ? now : nil, createdBy: nil,
          createdAt: now, updatedAt: now)
      }

      let all = [
        reminder("yesterday", due: local(11)),
        reminder("today", due: local(12)),
        reminder("tonight", due: local(12, 23, 59), hasTime: true),
        reminder("tomorrow", due: local(13)),
        reminder("no date"),
        reminder("flagged", flagged: true),
        reminder("done", due: local(12), flagged: true, completed: true),
      ]

      func titles(_ list: SmartList) -> [String] {
        list.filter(all, now: now, calendar: calendar).map(\.title)
      }

      precondition(titles(.today) == ["yesterday", "today", "tonight"], "today: \(titles(.today))")
      precondition(
        titles(.scheduled) == ["yesterday", "today", "tonight", "tomorrow"],
        "scheduled: \(titles(.scheduled))")
      precondition(
        titles(.all) == ["yesterday", "today", "tonight", "tomorrow", "no date", "flagged"],
        "all: \(titles(.all))")
      precondition(titles(.flagged) == ["flagged"], "flagged: \(titles(.flagged))")
      precondition(titles(.completed) == ["done"], "completed: \(titles(.completed))")

      let found = searchReminders("  MILK ", in: [reminder("Buy milk"), reminder("Bread")])
      precondition(found.map(\.title) == ["Buy milk"], "search: \(found.map(\.title))")
      let accent = searchReminders("cafe", in: [reminder("Café"), reminder("Tea")])
      precondition(accent.map(\.title) == ["Café"], "search accents: \(accent.map(\.title))")
      precondition(searchReminders("   ", in: all).isEmpty, "an empty query finds nothing")
    }
  }
#endif

/// The reminders whose title or notes contain `query`. Case and accents do not matter.
func searchReminders(_ query: String, in reminders: [Reminder]) -> [Reminder] {
  let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !query.isEmpty else { return [] }
  let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
  return reminders.filter {
    $0.title.range(of: query, options: options) != nil
      || $0.notes.range(of: query, options: options) != nil
  }
}
