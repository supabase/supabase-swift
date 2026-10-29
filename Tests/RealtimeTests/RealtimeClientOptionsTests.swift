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
  func defaults() {
    let options = RealtimeClientOptions()

    #expect(options.heartbeatInterval == .seconds(25))
    #expect(options.requestTimeout == .seconds(10))
    #expect(RealtimeClientOptions.defaultRequestTimeout == .seconds(10))
    #expect(
      options.reconnectBackoff.delay(forAttempt: 6, random: { $0.upperBound }) == .seconds(30))
    #expect(options.reconnectBackoff.delay(forAttempt: 2, random: { $0.upperBound }) == .seconds(2))
    #expect(options.connectOnSubscribe)
    #expect(options.disconnectOnEmptyChannelsAfter == .seconds(50))
    #expect(options.handleAppLifecycle == RealtimeClientOptions.defaultHandleAppLifecycle)
    #expect(options.serverLogLevel == nil)
  }

  @Test
  func everyTimingOptionIsWritable() {
    var options = RealtimeClientOptions()
    options.heartbeatInterval = .seconds(5)
    options.requestTimeout = .seconds(4)
    options.reconnectBackoff = .steps([.seconds(9)])
    options.connectOnSubscribe = false
    options.disconnectOnEmptyChannelsAfter = .zero

    #expect(options.heartbeatInterval == .seconds(5))
    #expect(options.requestTimeout == .seconds(4))
    #expect(options.reconnectBackoff.delay(forAttempt: 3) == .seconds(9))
    #expect(!options.connectOnSubscribe)
    #expect(options.disconnectOnEmptyChannelsAfter == .zero)
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
