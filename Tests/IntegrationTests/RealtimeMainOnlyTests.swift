//
//  RealtimeMainOnlyTests.swift
//
//
//  Created by Guilherme Souza on 23/10/26.
//

#if !os(Android) && !os(Linux)
  import Foundation
  import Realtime
  import Testing

  @Suite(
    .serialized,
    .timeLimit(.minutes(1)),
    .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION_TESTS"] != nil)
  )
  struct RealtimeMainOnlyTests {
    @Test
    func resubscribeSameInstanceDeliversBroadcast() async throws {
      let client = makeClient()
      let channel = client.channel(uniqueTopic()) { $0.broadcast.receiveOwnBroadcasts = true }
      try await channel.subscribeWithError()
      await channel.unsubscribe()
      #expect(channel.status == .unsubscribed)

      let messages = channel.broadcastStream(event: "again")
      try await channel.subscribeWithError()
      try await channel.broadcast(event: "again", message: ["text": "same instance"])

      #expect(client.channels.values.contains { $0 === channel })
      let received = try await first(messages, "broadcast after resubscribe")
      #expect(received["payload"]?.objectValue?["text"]?.stringValue == "same instance")
      await client.removeAllChannels()
    }

    @Test
    func broadcastWithAckWaitsForTheServerAndThrowsItsRejection() async throws {
      let client = makeClient()
      let channel = client.channel(uniqueTopic()) {
        $0.broadcast.acknowledgeBroadcasts = true
        $0.broadcast.receiveOwnBroadcasts = true
      }
      let messages = channel.broadcastStream(event: "confirmed")
      try await channel.subscribeWithError()

      try await channel.broadcast(event: "confirmed", message: ["text": "acknowledged"])
      let received = try await first(messages, "acknowledged broadcast")
      #expect(received["payload"]?.objectValue?["text"]?.stringValue == "acknowledged")

      let tooLarge = String(repeating: "x", count: 4 * 1024 * 1024)
      let error = await #expect(throws: RealtimeError.self) {
        try await channel.broadcast(event: "confirmed", message: ["text": .string(tooLarge)])
      }
      #expect(error?.kind == .payloadTooLarge)
      await client.removeAllChannels()
    }

    private func uniqueTopic() -> String {
      "rt2-\(UUID().uuidString)"
    }

    private func makeClient() -> RealtimeClient {
      RealtimeClient(
        url: URL(string: DotEnv.supabaseURL)!.appendingPathComponent("realtime/v1"),
        options: RealtimeClientOptions(headers: ["apikey": DotEnv.supabasePublishableKey]))
    }

    private struct Timeout: Error, CustomStringConvertible {
      let description: String
    }

    private func first<Element: Sendable>(
      _ stream: AsyncStream<Element>, _ what: String, within limit: Duration = .seconds(10)
    ) async throws -> Element {
      try await withThrowingTaskGroup(of: Element?.self) { group in
        group.addTask {
          for await element in stream { return element }
          return nil
        }
        group.addTask {
          try await Task.sleep(for: limit)
          return nil
        }
        defer { group.cancelAll() }
        guard let element = try await group.next() ?? nil else {
          throw Timeout(description: "\(what) not observed within \(limit)")
        }
        return element
      }
    }
  }
#endif
