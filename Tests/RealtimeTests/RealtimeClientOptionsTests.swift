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
  func initializesWithoutAnAPIKeyInsteadOfTrapping() {
    let client = RealtimeClient(
      url: URL(string: "https://project-ref.supabase.co/realtime/v1")!,
      options: RealtimeClientOptions(headers: [:])
    )

    #expect(client.connection.options.apikey == nil)
  }

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
    let options = RealtimeClientOptions(
      headers: ["apikey": "test-key"],
      logger: Logging.Logger(label: "test")
    )
    #expect(options.logger[metadataKey: "system"] == "realtime")
  }
}
