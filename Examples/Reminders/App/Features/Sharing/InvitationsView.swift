import SwiftUI

/// The invitations that wait for the user's answer.
struct InvitationsView: View {
  @Environment(DataStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var isWorking = false
  @State private var error: (any Error)?

  var body: some View {
    NavigationStack {
      List(store.incomingInvitations) { invitation in
        VStack(alignment: .leading, spacing: 10) {
          Text(invitation.listName)
            .font(.headline)
          Text("\(invitation.inviterName) invited you to this list.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          HStack {
            Button("Accept") {
              perform { try await store.accept(invitationID: invitation.id) }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("invitation.\(invitation.listName).accept")
            Button("Decline", role: .destructive) {
              perform { try await store.decline(invitationID: invitation.id) }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("invitation.\(invitation.listName).decline")
          }
        }
        .padding(.vertical, 4)
      }
      .disabled(isWorking)
      .navigationTitle("Invitations")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .accessibilityIdentifier("invitations.done")
        }
      }
      .errorAlert($error)
      .onChange(of: store.incomingInvitations.isEmpty) { _, isEmpty in
        if isEmpty { dismiss() }
      }
    }
  }

  private func perform(_ operation: @escaping () async throws -> Void) {
    isWorking = true
    Task {
      do {
        try await operation()
      } catch {
        self.error = error
      }
      isWorking = false
    }
  }
}
