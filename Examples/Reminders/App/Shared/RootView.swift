import Supabase
import SwiftUI

/// Chooses between the loading, signed-out and signed-in states.
struct RootView: View {
  @Environment(AuthModel.self) private var auth
  @Environment(\.supabase) private var client
  @State private var network = NetworkMonitor()

  var body: some View {
    ZStack {
      Group {
        switch auth.status {
        case .loading:
          ProgressView()
        case .signedIn(let session):
          SignedInView(client: client, userID: session.user.id)
            // A different user gets a new store. No data moves between accounts.
            .id(session.user.id)
        case .signedOut:
          AuthView()
        }
      }
      .environment(network)

      // The app keeps nothing on the device, so it cannot work with no connection.
      if !network.isConnected {
        OfflineView()
      }
    }
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
  /// comes back from the background. Events that arrived in between are lost, so the
  /// app reads everything again.
  ///
  /// `.inactive` is not a reason to stop: the app is inactive for a moment each time
  /// Control Center or a system prompt covers it.
  private var syncTrigger: Bool {
    network.isConnected && scenePhase != .background
  }

  var body: some View {
    @Bindable var store = store
    HomeView()
      .environment(store)
      .task(id: syncTrigger) {
        guard syncTrigger else { return }
        // Subscribe first, then load. In the other order, a change between the end of
        // the load and the start of the subscription would never arrive.
        await store.startRealtime()
        do {
          try await store.load()
        } catch {
          // A new trigger value cancels this task. That is not an error to show.
          if !Task.isCancelled { store.error = error }
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
