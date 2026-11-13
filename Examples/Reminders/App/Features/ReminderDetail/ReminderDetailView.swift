import SwiftUI

/// Edits one reminder. The changes go to the store when the user taps Done.
struct ReminderDetailView: View {
  @Environment(DataStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var draft: Reminder
  @State private var hasDate: Bool
  @State private var date: Date

  init(reminder: Reminder) {
    _draft = State(initialValue: reminder)
    _hasDate = State(initialValue: reminder.dueAt != nil)
    _date = State(initialValue: reminder.dueAt ?? .now)
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
    var reminder = draft
    reminder.title = trimmedTitle
    if hasDate {
      // A date with no time is the start of that day in the time zone of the device.
      reminder.dueAt = reminder.dueHasTime ? date : Calendar.current.startOfDay(for: date)
    } else {
      reminder.dueAt = nil
      reminder.dueHasTime = false
    }
    // The update shows at once, so the sheet closes before the server answers.
    store.run { [store] in try await store.updateReminder(reminder) }
    dismiss()
  }
}
