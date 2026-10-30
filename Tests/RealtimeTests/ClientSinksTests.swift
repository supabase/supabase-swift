//
//  ClientSinksTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct ClientSinksTests {
  let url = URL(string: "http://localhost:54321/realtime/v1")!

  @Test
  func concurrentChannelCallsReturnOneInstance() async {
    let client = RealtimeClient(url: url, options: RealtimeClientOptions(handleAppLifecycle: false))

    let ids = await withTaskGroup(of: ObjectIdentifier.self) { group in
      for _ in 0..<200 {
        group.addTask { ObjectIdentifier(client.channel("room")) }
      }
      return await group.reduce(into: Set<ObjectIdentifier>()) { $0.insert($1) }
    }

    #expect(ids.count == 1)
    #expect(client.channels.count == 1)
  }

  // `reportIssue` reaches `withKnownIssue` only on Darwin.
  #if canImport(Darwin)
    @Test
    func channelWithDifferentConfigurationReportsIssue() {
      let client = RealtimeClient(
        url: url, options: RealtimeClientOptions(handleAppLifecycle: false))
      let first = client.channel("room")

      var second: RealtimeChannel?
      withKnownIssue {
        second = client.channel("room") { $0.isPrivate = true }
      }

      #expect(first === second)
      #expect(second?.configuration.isPrivate == false)
    }
  #endif

  @Test
  func statusChangesReplaysCurrentStatus() async {
    let client = RealtimeClient(url: url, options: RealtimeClientOptions(handleAppLifecycle: false))

    let statuses = client.statusChanges()

    var iterator = statuses.makeAsyncIterator()
    let first = await iterator.next()
    guard case .disconnected(nil) = first else {
      Issue.record("Expected .disconnected(nil), got \(String(describing: first))")
      return
    }
    guard case .disconnected(nil) = client.status else {
      Issue.record("Expected .disconnected(nil), got \(client.status)")
      return
    }
  }

  @Test
  func heartbeatsReplayLatestOnly() async {
    let client = RealtimeClient(url: url, options: RealtimeClientOptions(handleAppLifecycle: false))

    let early = client.heartbeats()
    #expect(client.sinks.heartbeats.current == nil)

    await client.recordHeartbeat(.sent)

    var earlyIterator = early.makeAsyncIterator()
    #expect(await earlyIterator.next() == .sent)

    var lateIterator = client.heartbeats().makeAsyncIterator()
    #expect(await lateIterator.next() == .sent)
  }

  @Test
  func creatingChannelDoesNotCancelIdleDisconnect() async throws {
    let harness = IdleDisconnectHarness(url: url)
    let client = harness.client
    try await client.connect()

    await client.removeChannel(client.channel("room"))
    #expect(await client.idleDisconnectTaskCount == 1)

    _ = client.channel("x")
    #expect(await client.idleDisconnectTaskCount == 1)

    await harness.clock.advance(by: .seconds(5))

    for await status in client.statusChanges() {
      if case .disconnected(nil) = status { break }
    }
  }

  @Test
  func subscribeCancelsIdleDisconnect() async throws {
    let harness = IdleDisconnectHarness(url: url)
    let client = harness.client
    try await client.connect()

    await client.removeChannel(client.channel("room"))
    #expect(await client.idleDisconnectTaskCount == 1)

    let channel = client.channel("x")
    try await channel.subscribe()
    #expect(await client.idleDisconnectTaskCount == 0)

    await harness.clock.advance(by: .seconds(5))

    #expect(client.status.isConnected)
    await client.disconnect()
  }
}

/// A connected-on-demand client with a 5 s idle disconnect, whose server confirms every join.
private final class IdleDisconnectHarness: Sendable {
  let clock = SignalingTestClock()
  let client: RealtimeClient
  private let responder: Task<Void, Never>

  init(url: URL) {
    let (socket, server) = FakeWebSocket.fakes()
    client = RealtimeClient(
      url: url,
      options: RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: .seconds(5),
        handleAppLifecycle: false
      ),
      wsTransport: { _, _ in socket },
      http: HTTPClient(transport: RecordingTransport()),
      clock: clock
    )
    responder = Task {
      for await event in server.events {
        guard let message = event.realtimeMessage, message.event == "phx_join" else { continue }
        server.send(
          RealtimeMessage(
            joinRef: message.joinRef,
            ref: message.ref,
            topic: message.topic,
            event: "phx_reply",
            payload: ["response": ["postgres_changes": .array([])], "status": "ok"]
          )
        )
      }
    }
  }

  deinit {
    responder.cancel()
  }
}

extension RealtimeClient {
  fileprivate var idleDisconnectTaskCount: Int { tasks.tasks(at: .idleDisconnect).count }
}
