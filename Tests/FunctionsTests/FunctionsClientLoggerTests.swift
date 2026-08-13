import Foundation
import Logging
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// `FunctionsClient` has no stored `logger` property (unlike Auth/PostgREST/Storage) — the
/// `logger:` parameter is tagged and consumed directly when building the `LoggerInterceptor` at
/// construction time. Verify the tag by capturing the metadata the interceptor actually emits.
@Suite
struct FunctionsClientLoggerTests {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey = "test-api-key"

  private final class MetadataCapture: @unchecked Sendable {
    var captured: Logging.Logger.Metadata = [:]
  }

  private struct CapturingLogHandler: LogHandler {
    let capture: MetadataCapture
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .trace

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
      get { metadata[key] }
      set { metadata[key] = newValue }
    }

    func log(
      level: Logging.Logger.Level,
      message: Logging.Logger.Message,
      metadata: Logging.Logger.Metadata?,
      source: String,
      file: String,
      function: String,
      line: UInt
    ) {
      var merged = self.metadata
      if let metadata {
        merged.merge(metadata) { _, new in new }
      }
      capture.captured = merged
    }
  }

  @Test
  func loggerIsTaggedWithSystemMetadata() async throws {
    let capture = MetadataCapture()
    let logger = Logging.Logger(label: "test") { _ in CapturingLogHandler(capture: capture) }

    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      logger: logger,
      fetch: { request in
        (
          Data(),
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      }
    )

    try await sut.invoke("hello-world")

    #expect(capture.captured["system"] == "functions")
  }
}
