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

    #expect(client.options.apikey == nil)
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

  @Test(arguments: [
    (RealtimeServerLogLevel.info, "info"),
    (.warning, "warn"),
    (.error, "error"),
  ])
  func serverLogLevelAddsTheQueryItem(level: RealtimeServerLogLevel, expected: String) {
    let client = RealtimeClient(
      url: URL(string: "https://project-ref.supabase.co/realtime/v1")!,
      options: RealtimeClientOptions(serverLogLevel: level, handleAppLifecycle: false)
    )

    let items = URLComponents(url: client.webSocketURL, resolvingAgainstBaseURL: false)?.queryItems
    #expect(items?.first { $0.name == "log_level" }?.value == expected)
  }

  @Test
  func noServerLogLevelAddsNoQueryItem() {
    let client = RealtimeClient(
      url: URL(string: "https://project-ref.supabase.co/realtime/v1")!,
      options: RealtimeClientOptions(handleAppLifecycle: false)
    )

    let items = URLComponents(url: client.webSocketURL, resolvingAgainstBaseURL: false)?.queryItems
    #expect(items?.contains { $0.name == "log_level" } == false)
  }

  @Test
  func serverLogLevelAcceptsAStringLiteral() {
    let level: RealtimeServerLogLevel = "debug"
    #expect(level.rawValue == "debug")
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
