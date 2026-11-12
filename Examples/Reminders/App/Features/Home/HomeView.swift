import SwiftUI

struct HomeView: View {
  @Environment(SessionStore.self) private var session
  @Environment(DataStore.self) private var store

  @State private var path: [ReminderSource] = []
  @State private var query = ""
  @State private var isAddingList = false
  @State private var editedReminder: Reminder?
  @State private var error: (any Error)?

  private var isSearching: Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack(path: $path) {
      List {
        if isSearching {
          searchResults
        } else {
          smartLists
          myLists
        }
      }
      .listStyle(.insetGrouped)
      .overlay {
        if !store.isLoaded {
          ProgressView()
        }
      }
      .navigationTitle("Reminders")
      .navigationDestination(for: ReminderSource.self) { source in
        ListDetailView(source: source)
      }
      .searchable(text: $query, prompt: "Search")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          accountMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add List", systemImage: "plus") { isAddingList = true }
            .accessibilityIdentifier("home.addList")
        }
      }
      .sheet(isPresented: $isAddingList) {
        ListEditorView()
      }
      .sheet(item: $editedReminder) { reminder in
        ReminderDetailView(reminder: reminder)
      }
      .refreshable {
        do { try await store.load() } catch { self.error = error }
      }
      .errorAlert($error)
    }
  }

  private var smartLists: some View {
    Section {
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(SmartList.allCases) { smartList in
          // A button, not a `NavigationLink`: a tap on a list row fires every link in
          // that row, and all the cards are in one row.
          Button {
            path.append(.smart(smartList))
          } label: {
            SmartListCard(
              smartList: smartList,
              count: smartList.filter(store.reminders).count
            )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("home.smart.\(smartList.rawValue)")
        }
      }
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    }
  }

  private var myLists: some View {
    Section("My Lists") {
      if store.isLoaded, store.lists.isEmpty {
        Text("Tap + to create your first list.")
          .foregroundStyle(.secondary)
      }
      ForEach(store.lists) { list in
        NavigationLink(value: ReminderSource.list(list.id)) {
          HStack {
            Label {
              Text(list.name)
            } icon: {
              ListIcon(list: list)
            }
            Spacer()
            Text(store.reminders(in: list.id, includeCompleted: false).count, format: .number)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("home.list.\(list.name).count")
          }
        }
        .accessibilityIdentifier("home.list.\(list.name)")
      }
    }
  }

  @ViewBuilder
  private var searchResults: some View {
    let results = searchReminders(query, in: store.reminders)
    if results.isEmpty {
      ContentUnavailableView.search(text: query)
    }
    ForEach(results) { reminder in
      ReminderRow(
        reminder: reminder,
        tint: ListStyle.color(named: store.list(id: reminder.listID)?.color ?? ""),
        listName: store.list(id: reminder.listID)?.name,
        onToggle: { store.run { try await store.toggleCompleted(id: reminder.id) } },
        onInfo: { editedReminder = reminder }
      )
    }
  }

  private var accountMenu: some View {
    Menu {
      if let email = session.user?.email {
        Text(email)
      }
      Button("Sign Out", role: .destructive) {
        Task {
          do { try await session.signOut() } catch { self.error = error }
        }
      }
    } label: {
      Image(systemName: "person.crop.circle")
    }
    .accessibilityIdentifier("home.accountMenu")
  }
}
