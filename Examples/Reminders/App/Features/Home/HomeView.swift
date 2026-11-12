import SwiftUI

struct HomeView: View {
  @Environment(SessionStore.self) private var session

  @State private var error: (any Error)?

  var body: some View {
    NavigationStack {
      List {}
        .navigationTitle("Reminders")
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Menu {
              if let email = session.user?.email {
                Text(email)
              }
              Button("Sign Out", role: .destructive) {
                Task {
                  do { try await session.signOut() } catch { self.error = error }
                }
              }
              .accessibilityIdentifier("home.signOut")
            } label: {
              Image(systemName: "person.crop.circle")
            }
            .accessibilityIdentifier("home.accountMenu")
          }
        }
        .errorAlert($error)
    }
  }
}
