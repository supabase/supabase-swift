import SwiftUI

/// The reminders of one list, or of a smart list.
struct ListDetailView: View {
  @Environment(DataStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  let source: ReminderSource

  @State private var newTitle = ""
  @State private var showsCompleted = false
  @State private var editedReminder: Reminder?
  @State private var isEditingList = false
  @State private var isConfirmingDelete = false
  @State private var error: (any Error)?
  @FocusState private var isNewReminderFocused: Bool

  /// The list on screen, or `nil` for a smart list.
  private var list: ReminderList? {
    if case .list(let id) = source { store.list(id: id) } else { nil }
  }

  private var title: String {
    switch source {
    case .list: list?.name ?? ""
    case .smart(let smartList): smartList.title
    }
  }

  private var tint: Color {
    switch source {
    case .list: ListStyle.color(named: list?.color ?? ListStyle.defaultColor)
    case .smart(let smartList): ListStyle.color(named: smartList.color)
    }
  }

  private var reminders: [Reminder] {
    switch source {
    case .list(let id):
      store.reminders(in: id, includeCompleted: showsCompleted)
    case .smart(.completed):
      SmartList.completed.filter(store.reminders)
    case .smart(let smartList):
      // A reminder that the user completes here stays visible only with Show Completed.
      smartList.filter(store.reminders)
        + (showsCompleted ? completedMatches(of: smartList) : [])
    }
  }

  /// The list that gets a reminder typed on this screen. A smart list uses the first list.
  private var targetListID: UUID? {
    switch source {
    case .list(let id): id
    case .smart(.completed): nil
    case .smart: store.lists.first?.id
    }
  }

  /// True when the list of this screen is gone. A smart list is never gone.
  private var isGone: Bool {
    if case .list = source { list == nil } else { false }
  }

  var body: some View {
    List {
      ForEach(reminders) { reminder in
        ReminderRow(
          reminder: reminder,
          tint: tint,
          listName: list == nil ? store.list(id: reminder.listID)?.name : nil,
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

      if targetListID != nil {
        newReminderRow
      }
    }
    .listStyle(.plain)
    .navigationTitle(title)
    .toolbar {
      if source != .smart(.completed), !isGone {
        ToolbarItem(placement: .topBarTrailing) {
          menu
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
        if let list { store.run { try await store.deleteList(id: list.id) } }
      }
      .accessibilityIdentifier("listDetail.confirmDelete")
    }
    .errorAlert($error)
    // The list can go away while this screen is open: the user deletes it, the owner
    // deletes it, or the owner removes this user from it.
    .onChange(of: isGone) { _, isGone in
      if isGone { dismiss() }
    }
  }

  private func completedMatches(of smartList: SmartList) -> [Reminder] {
    let completed = store.reminders.filter(\.isCompleted)
    switch smartList {
    case .today, .scheduled: return completed.filter { $0.dueAt != nil }
    case .flagged: return completed.filter(\.isFlagged)
    case .all: return completed
    case .completed: return []
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

  private var menu: some View {
    Menu {
      Button(
        showsCompleted ? "Hide Completed" : "Show Completed",
        systemImage: showsCompleted ? "eye.slash" : "eye"
      ) {
        showsCompleted.toggle()
      }
      if let list {
        Button("Edit List", systemImage: "pencil") { isEditingList = true }
        if store.isOwner(of: list) {
          Button("Delete List", systemImage: "trash", role: .destructive) {
            isConfirmingDelete = true
          }
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
    guard !title.isEmpty, let targetListID else {
      newTitle = ""
      return
    }
    // A reminder typed in a smart list gets what that list shows.
    var dueAt: Date?
    var isFlagged = false
    switch source {
    case .smart(.today), .smart(.scheduled): dueAt = Calendar.current.startOfDay(for: .now)
    case .smart(.flagged): isFlagged = true
    default: break
    }
    Task {
      do {
        try await store.createReminder(
          title: title, listID: targetListID, dueAt: dueAt, isFlagged: isFlagged)
        newTitle = ""
        isNewReminderFocused = true
      } catch {
        self.error = error
      }
    }
  }
}
