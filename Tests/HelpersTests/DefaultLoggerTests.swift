import Logging
import Testing

@testable import Helpers

@Suite
struct DefaultLoggerTests {
  @Test
  func defaultLoggerUsesTheGivenLabel() {
    let logger = supabaseDefaultLogger(label: "io.supabase.test")
    #expect(logger.label == "io.supabase.test")
  }

  @Test
  func defaultLoggerLogsWarningAndAboveInDebugBuilds() {
    let logger = supabaseDefaultLogger(label: "io.supabase.test")
    #expect(logger.logLevel == .warning)
  }
}
