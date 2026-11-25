import ConcurrencyExtras
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
  func defaultLoggerIsSilentInEveryBuildConfiguration() {
    let logger = supabaseDefaultLogger(label: "io.supabase.test")
    #expect(logger.handler is SwiftLogNoOpLogHandler)
    #expect(logger.logLevel == .critical)
  }

  @Test
  func defaultLoggerNeverBuildsAMessageBelowCritical() {
    let built = LockIsolated(0)
    func message() -> Logging.Logger.Message {
      built.withValue { $0 += 1 }
      return "built"
    }

    for logger in [
      supabaseDefaultLogger(label: "io.supabase.test"),
      supabaseDefaultLogger(label: "io.supabase.test").redactingSecrets(),
    ] {
      logger.trace(message())
      logger.debug(message())
      logger.info(message())
      logger.notice(message())
      logger.warning(message())
      logger.error(message())
    }

    #expect(built.value == 0)
  }
}
