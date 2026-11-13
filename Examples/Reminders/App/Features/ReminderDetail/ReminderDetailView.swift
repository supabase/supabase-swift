import SwiftUI

/// Edits one reminder. The changes go to the store when the user taps Done.
struct ReminderDetailView: View {
  @Environment(DataStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  /// The reminder as it was when the sheet opened.
  private let original: Reminder
  @State private var draft: Reminder
  @State private var hasDate: Bool
  @State private var date: Date

  init(reminder: Reminder) {
    original = reminder
    _draft = State(initialValue: reminder)
    _hasDate = State(initialValue: reminder.dueAt != nil)
    _date = State(initialValue: reminder.localDueDate() ?? .now)
  }

  private var trimmedTitle: String {
    draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Title", text: $draft.title)
            .accessibilityIdentifier("reminderDetail.title")
          TextField("Notes", text: $draft.notes, axis: .vertical)
            .lineLimit(1...6)
            .accessibilityIdentifier("reminderDetail.notes")
        }

        Section {
          Toggle("Date", systemImage: "calendar", isOn: $hasDate)
            .accessibilityIdentifier("reminderDetail.dateToggle")
          if hasDate {
            DatePicker("Day", selection: $date, displayedComponents: .date)
              .accessibilityIdentifier("reminderDetail.date")
            Toggle("Time", systemImage: "clock", isOn: $draft.dueHasTime)
              .accessibilityIdentifier("reminderDetail.timeToggle")
            if draft.dueHasTime {
              DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("reminderDetail.time")
            }
          }
        }

        Section {
          Toggle("Flag", systemImage: "flag", isOn: $draft.isFlagged)
            .accessibilityIdentifier("reminderDetail.flag")
          Picker("Priority", selection: $draft.priority) {
            Text("None").tag(0)
            Text("Low").tag(1)
            Text("Medium").tag(2)
            Text("High").tag(3)
          }
          .accessibilityIdentifier("reminderDetail.priority")
          Picker("List", selection: $draft.listID) {
            ForEach(store.lists) { list in
              Text(list.name).tag(list.id)
            }
          }
          .accessibilityIdentifier("reminderDetail.list")
        }

        AttachmentsSection(reminderID: draft.id)
      }
      .navigationTitle("Details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .accessibilityIdentifier("reminderDetail.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: save)
            .disabled(trimmedTitle.isEmpty)
            .accessibilityIdentifier("reminderDetail.done")
        }
      }
    }
  }

  private func save() {
    var edited = draft
    edited.title = trimmedTitle
    if hasDate {
      edited.dueAt = edited.dueHasTime ? date : Reminder.storedDay(for: date)
    } else {
      edited.dueAt = nil
      edited.dueHasTime = false
    }

    // Another person can change the reminder while the sheet is open. The store has
    // their change. Only the fields that this user changed go on top of it, so that
    // an old value from the sheet does not replace a newer one.
    guard var reminder = store.reminders.first(where: { $0.id == original.id }) else {
      dismiss()
      return
    }
    func apply<Value: Equatable>(_ field: WritableKeyPath<Reminder, Value>) {
      if edited[keyPath: field] != original[keyPath: field] {
        reminder[keyPath: field] = edited[keyPath: field]
      }
    }
    apply(\.title)
    apply(\.notes)
    // `dueAt` means a different thing when `dueHasTime` changes (see `Reminder`), so a
    // change to either one copies both.
    if edited.dueAt != original.dueAt || edited.dueHasTime != original.dueHasTime {
      reminder.dueAt = edited.dueAt
      reminder.dueHasTime = edited.dueHasTime
    }
    apply(\.priority)
    apply(\.isFlagged)
    apply(\.listID)
    // The update shows at once, so the sheet closes before the server answers.
    store.run { [store] in try await store.updateReminder(reminder) }
    dismiss()
  }
}
