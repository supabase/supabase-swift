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
    // `swift test` always compiles this target in debug configuration, so this
    // exercises the `#if DEBUG` branch of `supabaseDefaultLogger`. The `#else`
    // branch (release: SwiftLogNoOpLogHandler, logLevel .critical) can't be
    // exercised from a debug test run — verify it by reading the source, or by
    // building `swift build -c release` and confirming no output appears.
    let logger = supabaseDefaultLogger(label: "io.supabase.test")
    #expect(logger.logLevel == .warning)
  }
}
