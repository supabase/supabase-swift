import SwiftUI

struct HomeView: View {
  @Environment(SessionStore.self) private var session
  @Environment(DataStore.self) private var store

  @State private var isAddingList = false
  @State private var error: (any Error)?

  var body: some View {
    NavigationStack {
      List {
        Section("My Lists") {
          ForEach(store.lists) { list in
            NavigationLink(value: list.id) {
              Label {
                Text(list.name)
              } icon: {
                ListIcon(list: list)
              }
            }
            .accessibilityIdentifier("home.list.\(list.name)")
          }
        }
      }
      .overlay {
        if !store.isLoaded {
          ProgressView()
        } else if store.lists.isEmpty {
          ContentUnavailableView(
            "No Lists",
            systemImage: "list.bullet",
            description: Text("Tap Add List to create your first list.")
          )
        }
      }
      .navigationTitle("Reminders")
      .navigationDestination(for: UUID.self) { listID in
        ListDetailView(listID: listID)
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          accountMenu
        }
        ToolbarItem(placement: .bottomBar) {
          Button("Add List") { isAddingList = true }
            .accessibilityIdentifier("home.addList")
        }
      }
      .sheet(isPresented: $isAddingList) {
        ListEditorView()
      }
      .refreshable {
        do { try await store.load() } catch { self.error = error }
      }
      .errorAlert($error)
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
