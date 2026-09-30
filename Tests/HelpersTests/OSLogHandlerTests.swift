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
    func logLevelDefaultsToTrace() {
      let handler = OSLogHandler(label: "io.supabase.test")
      #expect(handler.logLevel == .trace)
    }

    @Test
    func loggerConstructedWithHandlerDoesNotCrash() {
      let logger = Logging.Logger(label: "io.supabase.test") { label in
        OSLogHandler(label: label)
      }
      logger.warning("test message")
    }

    @Test
    func renderedMessageIncludesHandlerMetadataAndSourceLocation() {
      var handler = OSLogHandler(label: "io.supabase.test")
      handler[metadataKey: "requestID"] = "abc-123"

      let rendered = handler.renderedMessage(
        message: "hello",
        metadata: nil,
        file: "/some/path/File.swift",
        function: "doStuff()",
        line: 42
      )

      #expect(rendered == "hello [File.swift.doStuff():42] context: requestID: abc-123")
    }

    @Test
    func renderedMessageMergesPerCallMetadataOverHandlerMetadata() {
      var handler = OSLogHandler(label: "io.supabase.test")
      handler[metadataKey: "requestID"] = "abc-123"
      handler[metadataKey: "client_id"] = "1"

      let rendered = handler.renderedMessage(
        message: "hello",
        metadata: ["requestID": "override", "extra": "value"],
        file: "/some/path/File.swift",
        function: "doStuff()",
        line: 42
      )

      #expect(
        rendered
          == "hello [File.swift.doStuff():42] context: client_id: 1, extra: value, requestID: override"
      )
    }
  }
#endif
