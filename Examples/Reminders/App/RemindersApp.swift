import Supabase
import SwiftUI

/// The one client of the app. Every view and store uses it, so they all share one session.
///
/// The URL in `Config` is fixed, so the initializer cannot throw here.
// swift-format-ignore: NeverUseForceTry
let supabaseClient = try! SupabaseClient(
  supabaseURL: Config.supabaseURL,
  supabaseKey: Config.supabaseKey
)

@main
struct RemindersApp: App {
  /// Follows the auth state of `supabaseClient`. The stored session comes first, and the
  /// client refreshes it before it reports it when it is expired.
  @State private var auth = AuthModel(client: supabaseClient.auth)

  init() {
    #if DEBUG
      SmartList.selfTest()
    #endif
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(\.supabase, supabaseClient)
        .environment(auth)
    }
  }
}
