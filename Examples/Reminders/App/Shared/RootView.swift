import Supabase
import SwiftUI

/// Chooses between the loading, signed-out and signed-in states.
struct RootView: View {
  @Environment(SessionStore.self) private var session
  @State private var network = NetworkMonitor()

  let client: SupabaseClient

  var body: some View {
    ZStack {
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
      .environment(network)

      // The app keeps nothing on the device, so it cannot work with no connection.
      if !network.isConnected {
        OfflineView()
      }
    }
    .task { await session.observe() }
    .task { await network.observe() }
  }
}

/// Owns the data of one signed-in user.
private struct SignedInView: View {
  @Environment(NetworkMonitor.self) private var network
  @Environment(\.scenePhase) private var scenePhase
  @State private var store: DataStore

  init(client: SupabaseClient, userID: UUID) {
    _store = State(initialValue: DataStore(client: client, userID: userID))
  }

  /// A new value starts the sync again: when the connection returns, and when the app
  /// comes back to the front. Events that arrived in between are lost, so a full load
  /// comes first.
  private var syncTrigger: Bool {
    network.isConnected && scenePhase == .active
  }

  var body: some View {
    @Bindable var store = store
    HomeView()
      .environment(store)
      .task(id: syncTrigger) {
        guard syncTrigger else { return }
        do {
          try await store.load()
          await store.startRealtime()
        } catch {
          store.error = error
        }
      }
      .onDisappear {
        Task { await store.stopRealtime() }
      }
      .errorAlert($store.error)
  }
}

private struct OfflineView: View {
  var body: some View {
    ContentUnavailableView(
      "No Connection",
      systemImage: "wifi.slash",
      description: Text("Reminders needs a connection. Your data returns when you are online.")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    .accessibilityIdentifier("offline.message")
  }
}
