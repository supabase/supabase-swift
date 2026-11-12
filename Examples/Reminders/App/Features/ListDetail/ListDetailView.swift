import SwiftUI

/// The reminders of one list.
struct ListDetailView: View {
  @Environment(DataStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  let listID: UUID

  @State private var isEditingList = false
  @State private var isConfirmingDelete = false
  @State private var error: (any Error)?

  var body: some View {
    let list = store.list(id: listID)

    List {}
      .navigationTitle(list?.name ?? "")
      .toolbar {
        if let list {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
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
        }
      }
      .sheet(isPresented: $isEditingList) {
        if let list { ListEditorView(list: list) }
      }
      .confirmationDialog(
        "Delete this list and all its reminders?",
        isPresented: $isConfirmingDelete,
        titleVisibility: .visible
      ) {
        Button("Delete List", role: .destructive, action: deleteList)
          .accessibilityIdentifier("listDetail.confirmDelete")
      }
      .errorAlert($error)
      // The list can go away while this screen is open: the user deletes it, the owner
      // deletes it, or the owner removes this user from it.
      .onChange(of: list == nil) { _, isGone in
        if isGone { dismiss() }
      }
  }

  private func deleteList() {
    Task {
      do {
        try await store.deleteList(id: listID)
      } catch {
        self.error = error
      }
    }
  }
}
