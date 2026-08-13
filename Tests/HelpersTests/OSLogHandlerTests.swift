import Logging
import Testing

@testable import Helpers

#if canImport(OSLog)
  @Suite
  struct OSLogHandlerTests {
    @Test
    func metadataRoundTrips() {
      var handler = OSLogHandler(label: "io.supabase.test")
      handler[metadataKey: "requestID"] = "abc-123"
      #expect(handler[metadataKey: "requestID"] == "abc-123")
    }

    @Test
    func logLevelIsMutable() {
      var handler = OSLogHandler(label: "io.supabase.test")
      handler.logLevel = .error
      #expect(handler.logLevel == .error)
    }

    @Test
    func loggerConstructedWithHandlerDoesNotCrash() {
      let logger = Logging.Logger(label: "io.supabase.test") { label in
        OSLogHandler(label: label)
      }
      logger.warning("test message")
    }
  }
#endif
