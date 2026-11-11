import Foundation

enum DotEnv {
  /// The stack's API URL. The experimental stack picks its ports, so `scripts/test-integration.sh`
  /// and CI export it from `supabase status --env`. The default is the Docker stack's port.
  static let supabaseURL =
    ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "http://127.0.0.1:54321"
  /// The stack's Mailpit URL, exported the same way as ``supabaseURL``.
  static let mailpitURL =
    ProcessInfo.processInfo.environment["MAILPIT_URL"] ?? "http://127.0.0.1:54324"
  /// The local stack's JWT secret, which signs the keys below and any token a test mints.
  static let jwtSecret =
    ProcessInfo.processInfo.environment["SUPABASE_JWT_SECRET"]
    ?? "super-secret-jwt-token-with-at-least-32-characters-long"
  static let supabasePublishableKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
  static let supabaseSecretKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
  static let supabaseNewFormatPublishableKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
}
