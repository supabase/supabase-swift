import SwiftUI

/// The reminders of one list.
struct ListDetailView: View {
  @Environment(DataStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  let listID: UUID

  @State private var newTitle = ""
  @State private var showsCompleted = false
  @State private var editedReminder: Reminder?
  @State private var isEditingList = false
  @State private var isConfirmingDelete = false
  @State private var error: (any Error)?
  @FocusState private var isNewReminderFocused: Bool

  var body: some View {
    let list = store.list(id: listID)
    let tint = ListStyle.color(named: list?.color ?? ListStyle.defaultColor)

    List {
      ForEach(store.reminders(in: listID, includeCompleted: showsCompleted)) { reminder in
        ReminderRow(
          reminder: reminder,
          tint: tint,
          onToggle: { store.run { try await store.toggleCompleted(id: reminder.id) } },
          onInfo: { editedReminder = reminder }
        )
        .swipeActions(edge: .trailing) {
          Button("Delete", systemImage: "trash", role: .destructive) {
            store.run { try await store.deleteReminder(id: reminder.id) }
          }
          Button("Flag", systemImage: "flag") {
            var flagged = reminder
            flagged.isFlagged.toggle()
            store.run { try await store.updateReminder(flagged) }
          }
          .tint(.orange)
        }
      }

      newReminderRow
    }
    .listStyle(.plain)
    .navigationTitle(list?.name ?? "")
    .toolbar {
      if let list {
        ToolbarItem(placement: .topBarTrailing) {
          menu(for: list)
        }
      }
    }
    .sheet(item: $editedReminder) { reminder in
      ReminderDetailView(reminder: reminder)
    }
    .sheet(isPresented: $isEditingList) {
      if let list { ListEditorView(list: list) }
    }
    .confirmationDialog(
      "Delete this list and all its reminders?",
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button("Delete List", role: .destructive) {
        store.run { try await store.deleteList(id: listID) }
      }
      .accessibilityIdentifier("listDetail.confirmDelete")
    }
    .errorAlert($error)
    // The list can go away while this screen is open: the user deletes it, the owner
    // deletes it, or the owner removes this user from it.
    .onChange(of: list == nil) { _, isGone in
      if isGone { dismiss() }
    }
  }

  private var newReminderRow: some View {
    HStack(spacing: 12) {
      Image(systemName: "plus.circle.fill")
        .font(.title2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField("New Reminder", text: $newTitle)
        .focused($isNewReminderFocused)
        .submitLabel(.done)
        .onSubmit(addReminder)
        .accessibilityIdentifier("listDetail.newReminder")
    }
  }

  private func menu(for list: ReminderList) -> some View {
    Menu {
      Button(
        showsCompleted ? "Hide Completed" : "Show Completed",
        systemImage: showsCompleted ? "eye.slash" : "eye"
      ) {
        showsCompleted.toggle()
      }
      Button("Edit List", systemImage: "pencil") { isEditingList = true }
      if store.isOwner(of: list) {
        Button("Delete List", systemImage: "trash", role: .destructive) {
          isConfirmingDelete = true
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .accessibilityIdentifier("listDetail.menu")
  }

  /// An insert waits for the server. The text stays in the field until the row exists.
  private func addReminder() {
    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      newTitle = ""
      return
    }
    Task {
      do {
        try await store.createReminder(title: title, listID: listID)
        newTitle = ""
        isNewReminderFocused = true
      } catch {
        self.error = error
      }
    }
  }
}
