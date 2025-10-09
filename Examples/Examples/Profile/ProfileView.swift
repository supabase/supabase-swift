//
//  ProfileView.swift
//  Examples
//
//  Demonstrates user profile management and account operations
//

import Supabase
import SwiftUI

struct ProfileView: View {
  @State var user: User?
  @State var error: Error?
  @State var isLoading = false
  @State var showingMFA = false

  var identities: [UserIdentity] {
    user?.identities ?? []
  }

  var mfaFactors: [Factor] {
    user?.factors ?? []
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Manage your account, profile information, and security settings")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        if isLoading {
          Section {
            ProgressView("Loading profile...")
          }
        }

        if let error {
          Section {
            ErrorText(error)
          }
        }

        // User Information
        if let user {
          Section("Account Information") {
            VStack(alignment: .leading, spacing: 8) {
              if let email = user.email {
                HStack {
                  Image(systemName: "envelope.fill")
                    .foregroundColor(.accentColor)
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Email")
                      .font(.caption)
                      .foregroundColor(.secondary)
                    Text(email)
                      .font(.subheadline)
                  }
                }
              }

              if let phone = user.phone {
                HStack {
                  Image(systemName: "phone.fill")
                    .foregroundColor(.accentColor)
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Phone")
                      .font(.caption)
                      .foregroundColor(.secondary)
                    Text(phone)
                      .font(.subheadline)
                  }
                }
                .padding(.top, 4)
              }

              HStack {
                Image(systemName: "person.fill")
                  .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                  Text("User ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
                  Text(user.id.uuidString)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                }
              }
              .padding(.top, 4)

              HStack {
                Image(systemName: "calendar")
                  .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                  Text("Created")
                    .font(.caption)
                    .foregroundColor(.secondary)
                  Text(user.createdAt, style: .date)
                    .font(.caption)
                }
              }
              .padding(.top, 4)
            }
            .padding(.vertical, 4)
          }

          // Profile Management
          Section("Profile Management") {
            NavigationLink {
              UpdateProfileView(user: user)
            } label: {
              Label("Update Profile", systemImage: "pencil.circle.fill")
            }

            NavigationLink {
              ResetPasswordView()
            } label: {
              Label("Change Password", systemImage: "key.fill")
            }
          }

          // Security Section
          Section("Security") {
            HStack {
              Label("Multi-Factor Auth", systemImage: "lock.shield.fill")
              Spacer()
              if mfaFactors.isEmpty {
                Text("Not Enabled")
                  .font(.caption)
                  .foregroundColor(.secondary)
              } else {
                Text("\(mfaFactors.count) Factor(s)")
                  .font(.caption)
                  .foregroundColor(.green)
              }
            }
            .onTapGesture {
              showingMFA = true
            }

            Button {
              Task {
                await reauthenticate()
              }
            } label: {
              Label("Reauthenticate", systemImage: "arrow.clockwise.circle.fill")
            }
          }

          // Linked Identities
          Section("Linked Accounts") {
            NavigationLink {
              UserIdentityList()
            } label: {
              HStack {
                Label("Manage Identities", systemImage: "link.circle.fill")
                Spacer()
                Text("\(identities.count)")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }

            if identities.count > 1 {
              Menu {
                ForEach(identities) { identity in
                  Button(role: .destructive) {
                    Task {
                      await unlinkIdentity(identity)
                    }
                  } label: {
                    Label("Unlink \(identity.provider)", systemImage: "link.badge.minus")
                  }
                }
              } label: {
                Label("Unlink Identity", systemImage: "link.badge.minus")
                  .foregroundColor(.orange)
              }
            }
          }

          // Raw User Data
          Section("User Data (JSON)") {
            if let json = try? AnyJSON(user) {
              AnyJSONView(value: json)
            }
          }
        }

        // Sign Out
        Section {
          Button(role: .destructive) {
            Task {
              await signOut()
            }
          } label: {
            HStack {
              Spacer()
              Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
              Spacer()
            }
          }
        }

        Section("About") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Profile Management")
              .font(.headline)

            Text(
              "Your profile contains all account information and settings. You can update your email, phone, password, manage linked accounts, and configure security options like MFA."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Text("Available Actions:")
              .font(.subheadline)
              .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
              Label("Update email and phone", systemImage: "checkmark.circle")
              Label("Change password", systemImage: "checkmark.circle")
              Label("Link/unlink OAuth identities", systemImage: "checkmark.circle")
              Label("Enable multi-factor authentication", systemImage: "checkmark.circle")
              Label("Reauthenticate for sensitive operations", systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundColor(.secondary)
          }
        }
      }
      .navigationTitle("Profile")
      .refreshable {
        await loadUser()
      }
    }
    .gitHubSourceLink()
    .task {
      await loadUser()
    }
    .sheet(isPresented: $showingMFA) {
      if let user {
        let hasMFA = !(user.factors ?? []).isEmpty
        let status: MFAStatus = hasMFA ? .verified : .unenrolled
        MFAFlow(status: status)
      }
    }
  }

  @MainActor
  private func loadUser() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      user = try await supabase.auth.user()
    } catch {
      self.error = error
    }
  }

  @MainActor
  private func reauthenticate() async {
    do {
      error = nil
      isLoading = true
      defer { isLoading = false }

      try await supabase.auth.reauthenticate()

      // Refresh user data after reauthentication
      user = try await supabase.auth.user()
    } catch {
      self.error = error
    }
  }

  @MainActor
  private func unlinkIdentity(_ identity: UserIdentity) async {
    do {
      error = nil
      try await supabase.auth.unlinkIdentity(identity)

      // Refresh user data
      user = try await supabase.auth.user()
    } catch {
      self.error = error
    }
  }

  @MainActor
  private func signOut() async {
    do {
      try await supabase.auth.signOut()
    } catch {
      debug("Failed to sign out: \(error)")
    }
  }
}

#Preview {
  ProfileView()
}
