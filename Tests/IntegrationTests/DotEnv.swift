import XCTest

enum DotEnv {
  static let SUPABASE_URL = "http://127.0.0.1:54321"
  static let SUPABASE_ANON_KEY =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
  static let SUPABASE_SERVICE_ROLE_KEY =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"

  static var shouldRunIntegrationTests: Bool {
    ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil
  }

  static func requireEnabled(
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    try XCTSkipUnless(
      shouldRunIntegrationTests,
      "INTEGRATION_TESTS not defined. Set this environment variable to run integration tests.",
      file: file,
      line: line
    )
  }
}
