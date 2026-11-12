import SwiftUI

/// One reminder in a list.
struct ReminderRow: View {
  let reminder: Reminder
  let tint: Color
  let onToggle: () -> Void
  let onInfo: () -> Void

  private var id: String { "reminder.\(reminder.title)" }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Button(action: onToggle) {
        Image(systemName: reminder.isCompleted ? "largecircle.fill.circle" : "circle")
          .font(.title2)
          .foregroundStyle(reminder.isCompleted ? tint : .secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(reminder.isCompleted ? "Mark as not completed" : "Mark as completed")
      .accessibilityIdentifier("\(id).toggle")

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          if reminder.priority > 0 {
            Text(String(repeating: "!", count: reminder.priority))
              .foregroundStyle(tint)
              .accessibilityLabel("Priority \(reminder.priority)")
              .accessibilityIdentifier("\(id).priority")
          }
          Text(reminder.title)
            .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
            .accessibilityIdentifier(id)
        }
        if !reminder.notes.isEmpty {
          Text(reminder.notes)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        if let dueAt = reminder.dueAt {
          Text(dueText(dueAt))
            .font(.subheadline)
            .foregroundStyle(isOverdue(dueAt) ? .red : .secondary)
            .accessibilityIdentifier("\(id).due")
        }
      }

      Spacer(minLength: 0)

      if reminder.isFlagged {
        Image(systemName: "flag.fill")
          .foregroundStyle(.orange)
          .accessibilityLabel("Flagged")
          .accessibilityIdentifier("\(id).flag")
      }

      Button(action: onInfo) {
        Image(systemName: "info.circle")
          .font(.title3)
      }
      .buttonStyle(.plain)
      .foregroundStyle(tint)
      .accessibilityLabel("Details")
      .accessibilityIdentifier("\(id).info")
    }
  }

  private func dueText(_ date: Date) -> String {
    reminder.dueHasTime
      ? date.formatted(date: .abbreviated, time: .shortened)
      : date.formatted(date: .abbreviated, time: .omitted)
  }

  private func isOverdue(_ date: Date) -> Bool {
    guard !reminder.isCompleted else { return false }
    return reminder.dueHasTime ? date < .now : date < Calendar.current.startOfDay(for: .now)
  }
}
