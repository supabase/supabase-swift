import Supabase
import SwiftUI

/// Chooses between the loading, signed-out and signed-in states.
struct RootView: View {
  @Environment(SessionStore.self) private var session

  let client: SupabaseClient

  var body: some View {
    Group {
      if session.isLoading {
        ProgressView()
      } else if let user = session.user {
        SignedInView(client: client, userID: user.id)
          // A different user gets a new store. No data moves between accounts.
          .id(user.id)
      } else {
        AuthView()
      }
    }
    .task { await session.observe() }
  }
}

/// Owns the data of one signed-in user.
private struct SignedInView: View {
  @State private var store: DataStore

  init(client: SupabaseClient, userID: UUID) {
    _store = State(initialValue: DataStore(client: client, userID: userID))
  }

  var body: some View {
    @Bindable var store = store
    HomeView()
      .environment(store)
      .task {
        do { try await store.load() } catch { store.error = error }
      }
      .errorAlert($store.error)
  }
}
