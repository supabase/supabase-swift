import Supabase
import SwiftUI

@main
struct RemindersApp: App {
  private let client = SupabaseClient(
    supabaseURL: Config.supabaseURL,
    supabaseKey: Config.supabaseKey
  )

  var body: some Scene {
    WindowGroup {
      RootView()
    }
  }
}
