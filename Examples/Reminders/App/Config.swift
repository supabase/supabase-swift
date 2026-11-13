import Foundation

/// Connection values for the local Supabase stack in `Examples/Reminders/supabase`.
///
/// `supabase status` prints both values. The publishable key is safe to ship in an app:
/// row level security decides what each user can read and write.
enum Config {
  static let supabaseURL = URL(string: "http://127.0.0.1:54421")!
  static let supabaseKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"

  /// Makes every update call fail before it reaches the server.
  ///
  /// The UI tests use it to check that an optimistic update goes back to the old value.
  /// Set it with the launch argument `-failUpdates YES`. It is always `false` in release
  /// builds.
  static var failUpdates: Bool {
    #if DEBUG
      UserDefaults.standard.bool(forKey: "failUpdates")
    #else
      false
    #endif
  }
}
