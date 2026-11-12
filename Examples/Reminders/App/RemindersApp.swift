import Supabase
import SwiftUI

@main
struct RemindersApp: App {
  private let client: SupabaseClient
  @State private var session: SessionStore

  init() {
    #if DEBUG
      SmartList.selfTest()
    #endif

    let client = SupabaseClient(
      supabaseURL: Config.supabaseURL,
      supabaseKey: Config.supabaseKey,
      options: SupabaseClientOptions(
        // Sends the stored session at once on launch, before any network call.
        // This is the default in the next major version.
        auth: .init(emitLocalSessionAsInitialSession: true)
      )
    )
    self.client = client
    _session = State(initialValue: SessionStore(client: client))
  }

  var body: some Scene {
    WindowGroup {
      RootView(client: client)
        .environment(session)
    }
  }
}
