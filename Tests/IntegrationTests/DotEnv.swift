import Foundation

enum DotEnv {
  /// `SUPABASE_URL` overrides the default so the suite can run against a stack on other ports.
  static let supabaseURL =
    ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "http://127.0.0.1:54321"
  static let supabasePublishableKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
  static let supabaseSecretKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
  /// The CLI's fixed local demo key in the new `sb_publishable_` format.
  static let supabaseNewFormatPublishableKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
}
