import SwiftUI

/// Chooses between the loading, signed-out and signed-in states.
struct RootView: View {
  @Environment(SessionStore.self) private var session

  var body: some View {
    Group {
      if session.isLoading {
        ProgressView()
      } else if session.user != nil {
        HomeView()
      } else {
        AuthView()
      }
    }
    .task { await session.observe() }
  }
}
