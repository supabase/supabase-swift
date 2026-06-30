//
//  LeakWarningTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import IssueReporting
import Testing

@testable import RealtimeV3

/// Tests that `Realtime` emits a debug warning when it is deinited with channels that
/// were joined but never left, and that no warning fires when all channels are properly left.
///
/// ## Deterministic deinit
/// Background routing and heartbeat tasks hold a strong reference to the `Realtime` actor
/// via closures. To ensure the actor deinits within the test, we call `disconnect()` first —
/// this cancels those tasks and releases their captures. Once the tasks are cancelled,
/// dropping the last strong reference to the `Realtime` variable triggers `deinit`.
///
/// ## disconnect() does NOT clear joinedTopics
/// `disconnect()` is intentionally NOT a substitute for `leave()`. It does not clear
/// `joinedTopics` because disconnecting is a transport-level operation, not a channel-level
/// leave. A channel that was subscribed but never left remains in `joinedTopics` so the
/// deinit warning still fires — guiding the developer to call `leave()` explicitly.
@Suite struct LeakWarningTests {

  // MARK: - warnsOnLeakedJoinedChannel

  /// A joined-but-unleft channel should trigger a warning when Realtime is deinited.
  @Test func warnsOnLeakedJoinedChannel() async {
    await withExpectedIssue("Realtime deinited with joined channel that was never left") {
      // Scope the Realtime actor in an inner async function so Swift ARC releases it
      // when the function returns — before we reach the withExpectedIssue check.
      await subscribeWithoutLeaving()
      // After subscribeWithoutLeaving() returns, the Realtime is fully released
      // and its deinit has fired, reporting the issue.
    }
  }

  /// Creates a Realtime client, subscribes a channel, disconnects (to cancel background tasks
  /// so the actor can deinit), then returns WITHOUT leaving the channel.
  ///
  /// When this function returns, all local references to `rt` are gone. Swift's ARC will
  /// release the actor, triggering `deinit` which fires the leak warning.
  private func subscribeWithoutLeaving() async {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: {
        var c = Configuration.default
        // Use .never reconnection and long heartbeat to prevent background tasks from
        // interfering with the test by triggering unexpected state transitions.
        c.reconnection = .never
        c.heartbeat = .seconds(3600)
        return c
      }(),
      transport: transport
    )

    server.autoReplyToJoins()
    let channel = await rt.channel("room:leak-test")
    try? await channel.subscribe()

    // Wait until the channel is fully joined before proceeding.
    for await s in await channel.state {
      if s == .joined { break }
    }

    // disconnect() cancels background tasks (routing + heartbeat) so the actor can deinit
    // once this function returns and `rt` goes out of scope.
    // Critically, disconnect() does NOT call leave() and does NOT clear joinedTopics.
    await rt.disconnect()

    // Yield several times to let cancelled tasks complete and release their strong
    // captures of `rt`, ensuring ARC can release the actor when `rt` drops.
    for _ in 0..<20 {
      await Task.yield()
    }

    // `rt` (and `channel`) go out of scope at the end of this function.
    // ARC releases `rt` → deinit fires → reportIssue is called.
  }

  // MARK: - noWarnWhenAllLeft

  /// A channel that is properly left before Realtime deinits should NOT trigger a warning.
  @Test func noWarnWhenAllLeft() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(
      url: URL(string: "wss://x")!,
      apiKey: "k",
      configuration: {
        var c = Configuration.default
        c.reconnection = .never
        c.heartbeat = .seconds(3600)
        return c
      }(),
      transport: transport
    )

    server.autoReplyToJoins()
    server.autoReplyToLeaves()

    let channel = await rt.channel("room:no-leak-test")
    try await channel.subscribe()

    // Wait until joined.
    for await s in await channel.state {
      if s == .joined { break }
    }

    // Properly leave the channel — removes the topic from joinedTopics.
    try await channel.leave()

    // disconnect() cancels background tasks so the actor can deinit.
    await rt.disconnect()

    // rt goes out of scope here → deinit → joinedTopics is empty → NO warning fires.
    // If a warning fires unexpectedly, the test framework routes it to a test failure.
  }
}
