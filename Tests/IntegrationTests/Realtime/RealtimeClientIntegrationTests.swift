//
//  RealtimeClientIntegrationTests.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 08/10/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Realtime
import TestHelpers
import Testing

@Suite(
  .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil),
  .disabled(if: WebSocketAvailability.isMissing, "libcurl has no WebSocket support")
)
struct RealtimeClientIntegrationTests {
  struct StreamEnded: Error {}

  /// Counts upgrades on the way to the default transport.
  struct CountingTransport: WebSocketTransport {
    let count = LockIsolated(0)
    let base = URLSessionWebSocketTransport()

    func connect(to url: URL, headerFields: HTTPFields) async throws -> any WebSocketConnection {
      count.withValue { $0 += 1 }
      return try await base.connect(to: url, headerFields: headerFields)
    }
  }

  private func uniqueTopic() -> String { "it-\(UUID())" }

  /// Runs `body` with a fresh client and closes it afterwards, also when `body` throws.
  private func withClient(
    configure: (inout RealtimeClientOptions) -> Void = { _ in },
    _ body: (RealtimeClient) async throws -> Void
  ) async throws {
    let client = LiveRealtime.client(configure: configure)
    do {
      try await body(client)
    } catch {
      await client.disconnect()
      throw error
    }
    await client.disconnect()
  }

  /// The first element that passes `predicate`, within 10 seconds.
  private func first<Element>(
    _ stream: RealtimeStream<Element>,
    where predicate: @escaping @Sendable (Element) -> Bool = { _ in true }
  ) async throws -> Element {
    try await withTimeout(.seconds(10)) {
      for await element in stream where predicate(element) { return element }
      throw StreamEnded()
    }
  }

  private func name(_ status: RealtimeConnectionStatus) -> String {
    switch status {
    case .disconnected: "disconnected"
    case .connecting: "connecting"
    case .connected: "connected"
    case .reconnecting: "reconnecting"
    }
  }

  // MARK: - Connection

  @Test
  func connectionAndDisconnection() async throws {
    let client = LiveRealtime.client()
    guard case .disconnected(nil) = client.status else {
      Issue.record("expected a new client to be disconnected, got \(client.status)")
      return
    }

    try await client.connect()
    #expect(client.status.isConnected)

    await client.disconnect()
    guard case .disconnected(nil) = client.status else {
      Issue.record("expected .disconnected(nil), got \(client.status)")
      return
    }
  }

  @Test
  func connectionStatusChanges() async throws {
    let client = LiveRealtime.client()
    let statuses = client.statusChanges
    let seen = LockIsolated<[String]>([])
    let collecting = Task {
      for await status in statuses { seen.withValue { $0.append(name(status)) } }
    }
    defer { collecting.cancel() }
    // The stream keeps only the newest status, so each step waits until the collector saw it.
    #expect(await waitUntil { seen.value == ["disconnected"] })

    try await client.connect()
    #expect(await waitUntil { seen.value.last == "connected" })
    await client.disconnect()

    #expect(await waitUntil { seen.value.last == "disconnected" && seen.value.count > 2 })
    let sequence = seen.value
    let connecting = try #require(sequence.firstIndex(of: "connecting"), "saw \(sequence)")
    let connected = try #require(sequence.firstIndex(of: "connected"), "saw \(sequence)")
    #expect(connecting < connected)
  }

  @Test
  func manualDisconnectShouldNotReconnect() async throws {
    let client = LiveRealtime.client()
    try await client.connect()
    await client.disconnect()
    let statuses = client.statusChanges

    await #expect(throws: TimeoutError.self) {
      try await withTimeout(.seconds(3)) {
        for await status in statuses where name(status) != "disconnected" { return }
      }
    }
    guard case .disconnected(nil) = client.status else {
      Issue.record("expected .disconnected(nil), got \(client.status)")
      return
    }
  }

  @Test
  func multipleConnectCalls() async throws {
    let transport = CountingTransport()
    try await withClient(configure: { $0.webSocketTransport = transport }) { client in
      try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<5 { group.addTask { try await client.connect() } }
        try await group.waitForAll()
      }

      #expect(client.status.isConnected)
      #expect(transport.count.value == 1)
    }
  }

  @Test
  func wrongAPIKeyFailsWithoutRetrying() async throws {
    let client = LiveRealtime.client(apikey: "not-a-key")

    let error = await #expect(throws: RealtimeError.self) {
      try await withTimeout(.seconds(10)) { try await client.connect() }
    }
    #expect(error?.isRetryable == false)
    #expect(client.status.error?.isRetryable == false)
  }

  @Test
  func serverLogLevelInfoConnects() async throws {
    try await withClient(configure: { $0.serverLogLevel = .info }) { client in
      try await client.connect()
      #expect(client.status.isConnected)
    }
  }

  @Test
  func heartbeatsAreAcknowledged() async throws {
    try await withClient(configure: { $0.heartbeatInterval = .seconds(1) }) { client in
      let heartbeats = client.heartbeats
      try await client.connect()

      let acknowledged = try await first(heartbeats) {
        if case .acknowledged = $0 { return true }
        return false
      }
      guard case .acknowledged(let latency) = acknowledged else { return }
      #expect(latency > .zero)
    }
  }

  // MARK: - Channels

  @Test
  func multipleChannels() async throws {
    try await withClient { client in
      let channels = (0..<3).map { _ in client.channel(uniqueTopic()) }

      try await withThrowingTaskGroup(of: Void.self) { group in
        for channel in channels { group.addTask { try await channel.subscribe() } }
        try await group.waitForAll()
      }

      #expect(channels.allSatisfy { $0.status.isSubscribed })
      #expect(client.channels.count == 3)
    }
  }

  @Test
  func channelReuse() async throws {
    try await withClient { client in
      let topic = uniqueTopic()
      let channel = client.channel(topic)
      try await channel.subscribe()

      #expect(client.channel(topic) === channel)
      #expect(client.channels.count == 1)
    }
  }

  @Test
  func removeChannel() async throws {
    try await withClient { client in
      let channel = client.channel(uniqueTopic())
      let other = client.channel(uniqueTopic())
      try await channel.subscribe()
      try await other.subscribe()

      await client.removeChannel(channel)

      #expect(channel.status.isSubscribed == false)
      #expect(client.channels.map(\.topic) == [other.topic])
      #expect(other.status.isSubscribed)
    }
  }

  @Test
  func removeAllChannels() async throws {
    try await withClient { client in
      let channels = [client.channel(uniqueTopic()), client.channel(uniqueTopic())]
      for channel in channels { try await channel.subscribe() }

      await client.removeAllChannels()

      #expect(client.channels.isEmpty)
      #expect(channels.allSatisfy { !$0.status.isSubscribed })
    }
  }
}
