import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Logging
import TestHelpers
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

    #expect(client.headers[.apiKey] == nil)
  }

  @Test
  func defaults() {
    let options = RealtimeClientOptions()

    #expect(options.heartbeatInterval == .seconds(25))
    #expect(options.requestTimeout == .seconds(10))
    #expect(RealtimeClientOptions.defaultRequestTimeout == .seconds(10))
    #expect(options.connectOnSubscribe)
    #expect(options.disconnectOnEmptyChannelsAfter == .seconds(50))
    #expect(options.handleAppLifecycle == RealtimeClientOptions.defaultHandleAppLifecycle)
    #expect(options.serverLogLevel == nil)
  }

  @Test
  func reconnectBackoffIsFullJitterWithA1sBaseAnd30sCap() {
    let client = RealtimeClient(
      url: URL(string: "https://project-ref.supabase.co/realtime/v1")!,
      options: RealtimeClientOptions(handleAppLifecycle: false)
    )

    #expect(client.reconnectBackoff.delay(forAttempt: 1, random: { $0.upperBound }) == .seconds(1))
    #expect(client.reconnectBackoff.delay(forAttempt: 2, random: { $0.upperBound }) == .seconds(2))
    #expect(client.reconnectBackoff.delay(forAttempt: 6, random: { $0.upperBound }) == .seconds(30))
    #expect(client.reconnectBackoff.delay(forAttempt: 6, random: { $0.lowerBound }) == .zero)
  }

  @Test
  func everyTimingOptionIsWritable() {
    var options = RealtimeClientOptions()
    options.heartbeatInterval = .seconds(5)
    options.requestTimeout = .seconds(4)
    options.connectOnSubscribe = false
    options.disconnectOnEmptyChannelsAfter = .zero

    #expect(options.heartbeatInterval == .seconds(5))
    #expect(options.requestTimeout == .seconds(4))
    #expect(!options.connectOnSubscribe)
    #expect(options.disconnectOnEmptyChannelsAfter == .zero)
  }

  @Test
  func headersAreReadableAsADictionary() {
    var options = RealtimeClientOptions(headers: ["X-Custom": "1"])
    options.headers["X-Other"] = "2"

    #expect(options.headers == ["X-Custom": "1", "X-Other": "2"])
  }

  @Test
  func headersReachTheUpgradeRequest() async throws {
    let headers = try await upgradeHeaders(for: ["X-Custom": "1", "apikey": "k"])

    #expect(headers[HTTPField.Name("X-Custom")!] == "1")
    #expect(headers[.apiKey] == "k")
    #expect(headers[.xClientInfo]?.hasPrefix("realtime-swift/") == true)
  }

  @Test
  func customClientInfoIsKept() async throws {
    let headers = try await upgradeHeaders(for: ["x-client-info": "my-app/1.0"])

    #expect(headers[values: .xClientInfo] == ["my-app/1.0"])
  }

  @Test
  func webSocketTransportIsUsed() async throws {
    let transport = CountingTransport()
    var options = RealtimeClientOptions(handleAppLifecycle: false)
    options.webSocketTransport = transport
    let client = RealtimeClient(
      url: URL(string: "http://localhost:54321/realtime/v1")!,
      options: options
    )

    try await client.connect()

    #expect(transport.connects.value == 1)
    await client.disconnect()
  }

  @Test
  func webSocketTransportDefaultsToNil() {
    #expect(RealtimeClientOptions().webSocketTransport == nil)
  }

  @Test
  func connectionOptionsAreWritable() {
    var options = RealtimeClientOptions()
    options.accessToken = { "token" }
    options.logger = Logging.Logger(label: "custom")
    options.http = HTTPClientConfiguration(timeout: .seconds(3))

    #expect(options.accessToken != nil)
    #expect(options.logger?.label == "custom")
    #expect(options.http.timeout == .seconds(3))
  }

  /// The headers the client sends with its WebSocket upgrade request.
  private func upgradeHeaders(for headers: [String: String]) async throws -> HTTPFields {
    let captured = LockIsolated<HTTPFields?>(nil)
    let client = RealtimeClient(
      url: URL(string: "http://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(headers: headers, handleAppLifecycle: false),
      wsTransport: { _, fields in
        captured.setValue(fields)
        return FakeWebSocket.fakes().0
      },
      http: HTTPClient(transport: RecordingTransport()),
      clock: TestClock()
    )
    try await client.connect()
    await client.disconnect()
    return try #require(captured.value)
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
  func clientTagsTheGivenLoggerWithSystemMetadata() {
    let client = RealtimeClient(
      url: URL(string: "https://example.supabase.co/realtime/v1")!,
      options: RealtimeClientOptions(
        logger: Logging.Logger(label: "test"),
        handleAppLifecycle: false
      )
    )
    #expect(client.logger.label == "test")
    #expect(client.logger[metadataKey: "system"] == "realtime")
  }

  @Test
  func clientUsesTheDefaultLoggerWhenNoneIsGiven() {
    #expect(RealtimeClientOptions().logger == nil)

    let client = RealtimeClient(
      url: URL(string: "https://example.supabase.co/realtime/v1")!,
      options: RealtimeClientOptions(handleAppLifecycle: false)
    )
    #expect(client.logger.label == "io.supabase.realtime")
    #expect(client.logger[metadataKey: "system"] == "realtime")
  }
}

private final class CountingTransport: WebSocketTransport {
  let connects = LockIsolated(0)

  func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
    connects.withValue { $0 += 1 }
    return FakeWebSocket.fakes().0
  }
}
