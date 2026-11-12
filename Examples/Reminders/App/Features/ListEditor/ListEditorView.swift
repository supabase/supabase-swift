import SwiftUI

/// Creates a list, or edits the name, color and icon of an existing one.
struct ListEditorView: View {
  @Environment(DataStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  private let list: ReminderList?

  @State private var name: String
  @State private var color: String
  @State private var icon: String
  @State private var isSaving = false
  @State private var error: (any Error)?

  /// - Parameter list: The list to edit, or `nil` to create one.
  init(list: ReminderList? = nil) {
    self.list = list
    _name = State(initialValue: list?.name ?? "")
    _color = State(initialValue: list?.color ?? ListStyle.defaultColor)
    _icon = State(initialValue: list?.icon ?? ListStyle.defaultIcon)
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private let columns = Array(repeating: GridItem(.flexible()), count: 6)

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("List Name", text: $name)
            .font(.title3.bold())
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("listEditor.name")
        }

        Section {
          LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ListStyle.colors, id: \.name) { item in
              Button {
                color = item.name
              } label: {
                Circle()
                  .fill(item.color)
                  .frame(width: 36, height: 36)
                  .overlay {
                    if color == item.name {
                      Circle().stroke(.primary.opacity(0.4), lineWidth: 3).padding(-5)
                    }
                  }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(item.name)
              .accessibilityIdentifier("listEditor.color.\(item.name)")
            }
          }
          .padding(.vertical, 6)
        }

        Section {
          LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ListStyle.icons, id: \.self) { symbol in
              Button {
                icon = symbol
              } label: {
                Image(systemName: symbol)
                  .frame(width: 36, height: 36)
                  .background(.quaternary, in: Circle())
                  .overlay {
                    if icon == symbol {
                      Circle().stroke(.primary.opacity(0.4), lineWidth: 3).padding(-5)
                    }
                  }
              }
              .buttonStyle(.plain)
              .accessibilityLabel(symbol)
              .accessibilityIdentifier("listEditor.icon.\(symbol)")
            }
          }
          .padding(.vertical, 6)
        }
      }
      .navigationTitle(list == nil ? "New List" : "List Info")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .accessibilityIdentifier("listEditor.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: save)
            .disabled(trimmedName.isEmpty || isSaving)
            .accessibilityIdentifier("listEditor.save")
        }
      }
      .errorAlert($error)
    }
  }

  private func save() {
    isSaving = true
    Task {
      do {
        if var list {
          list.name = trimmedName
          list.color = color
          list.icon = icon
          // The update shows at once, so the sheet can close before the server answers.
          dismiss()
          try await store.updateList(list)
        } else {
          try await store.createList(name: trimmedName, color: color, icon: icon)
          dismiss()
        }
      } catch {
        self.error = error
      }
      isSaving = false
    }
  }
}
