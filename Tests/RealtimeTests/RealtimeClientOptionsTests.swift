import Foundation
import Logging
import Testing

@testable import Realtime

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct RealtimeClientOptionsTests {
  @Test
  func sessionDefaultsToNil() {
    let options = RealtimeClientOptions(headers: ["apikey": "test-key"])
    #expect(options.session == nil)
  }

  @Test
  func sessionCanBeOverridden() {
    let customSession = URLSession(configuration: .ephemeral)
    let options = RealtimeClientOptions(
      headers: ["apikey": "test-key"],
      session: customSession
    )
    #expect(options.session === customSession)
  }

  @Test
  func loggerIsTaggedWithSystemMetadata() {
    // The `@_disfavoredOverload` initializer preserving the pre-`vsn` signature delegates to this
    // primary initializer via `self.init(...)`, so tagging here covers both entry points.
    let options = RealtimeClientOptions(
      headers: ["apikey": "test-key"],
      logger: Logging.Logger(label: "test")
    )
    #expect(options.logger[metadataKey: "system"] == "realtime")
  }
}
