import SwiftUI

/// The people of a list. The owner invites and removes people. A member can leave.
struct ShareListView: View {
  @Environment(DataStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  let listID: UUID

  @State private var email = ""
  @State private var isWorking = false
  @State private var errorText: String?

  private var trimmedEmail: String {
    email.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      Form {
        if let list = store.list(id: listID) {
          let isOwner = store.isOwner(of: list)

          Section("People") {
            personRow(userID: list.ownerID, detail: "Owner")
            ForEach(store.members(of: listID), id: \.userID) { member in
              HStack {
                personRow(userID: member.userID, detail: nil)
                if isOwner, let email = store.profile(id: member.userID)?.email {
                  Spacer()
                  Button("Remove", role: .destructive) {
                    perform { try await store.removeMember(userID: member.userID, listID: listID) }
                  }
                  .buttonStyle(.borderless)
                  .accessibilityIdentifier("share.remove.\(email)")
                }
              }
            }
          }

          if isOwner {
            ownerSections
          } else {
            Section {
              Button("Leave List", role: .destructive) {
                perform {
                  try await store.leaveList(id: listID)
                  dismiss()
                }
              }
              .accessibilityIdentifier("share.leave")
            }
          }
        }
      }
      .disabled(isWorking)
      .navigationTitle("Share List")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .accessibilityIdentifier("share.done")
        }
      }
    }
  }

  @ViewBuilder
  private var ownerSections: some View {
    let pending = store.pendingInvitations(for: listID)
    if !pending.isEmpty {
      Section("Invited") {
        ForEach(pending) { invitation in
          HStack {
            Text(invitation.invitedEmail)
              .accessibilityIdentifier("share.pending.\(invitation.invitedEmail)")
            Spacer()
            Button("Revoke", role: .destructive) {
              perform { try await store.revokeInvitation(id: invitation.id) }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("share.revoke.\(invitation.invitedEmail)")
          }
        }
      }
    }

    Section {
      TextField("Email", text: $email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .accessibilityIdentifier("share.email")
      Button("Invite") {
        perform {
          try await store.invite(email: trimmedEmail, listID: listID)
          email = ""
        }
      }
      .disabled(trimmedEmail.isEmpty)
      .accessibilityIdentifier("share.invite")
    } header: {
      Text("Invite by Email")
    } footer: {
      if let errorText {
        Text(errorText)
          .foregroundStyle(.red)
          .accessibilityIdentifier("share.error")
      } else {
        Text("The person sees the invitation in the app after they sign in with this email.")
      }
    }
  }

  private func personRow(userID: UUID, detail: String?) -> some View {
    let profile = store.profile(id: userID)
    return VStack(alignment: .leading) {
      Text(profile?.displayName ?? "Unknown")
      Text([profile?.email, detail].compactMap { $0 }.joined(separator: " · "))
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("share.member.\(profile?.email ?? "")")
  }

  private func perform(_ operation: @escaping () async throws -> Void) {
    isWorking = true
    errorText = nil
    Task {
      do {
        try await operation()
      } catch {
        errorText = errorMessage(for: error)
      }
      isWorking = false
    }
  }
}
