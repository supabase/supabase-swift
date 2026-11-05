//
//  ServerErrorRejoinTests.swift
//  RealtimeTests
//

import Clocks
import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// A server `phx_error` on a joined channel, end to end through the shell: the channel waits on
/// the test clock, joins again, and reports the rejoin. A live server cannot be made to send
/// `phx_error` on demand, so the test host plays the server.
@Suite
struct ServerErrorRejoinTests {
  @Test
  func serverErrorRejoinsAndEmitsResubscribed() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(requestTimeout: .seconds(10), handleAppLifecycle: false))
    let channel = await host.client.channel("room")
    var events = await channel.events().makeAsyncIterator()
    let firstJoin = try await host.subscribe(channel)
    var statuses = await channel.statusChanges().makeAsyncIterator()
    #expect(await statuses.next() == .subscribed)

    host.sendError(for: firstJoin)
    guard case .resubscribing(1, let retryIn, let error)? = await statuses.next() else {
      Issue.record("Expected a rejoin wait, got \(await channel.status)")
      return
    }
    #expect(retryIn == .seconds(1))
    #expect(error.kind == .channelError)
    #expect(await host.client.liveChannel(for: "room") === channel)

    await host.clock.advance(by: .seconds(1))
    let rejoin = try await host.receive {
      $0.event == ChannelEvent.join && $0.joinRef != firstJoin.joinRef
    }
    #expect(await channel.status == .subscribing)
    host.confirmJoin(rejoin)

    #expect(await events.next() == .resubscribed)
    #expect(await channel.status == .subscribed)
  }

  @Test
  func pushWaitingForAReplyFailsWithChannelError() async throws {
    let host = await RealtimeTestHost(
      options: RealtimeClientOptions(requestTimeout: .seconds(10), handleAppLifecycle: false))
    let channel = await host.client.channel("room")
    let join = try await host.subscribe(channel)

    let push = Task { try await channel.track(["name": "ana"] as JSONObject) }
    _ = try await host.receive(event: "presence")
    host.sendError(for: join)

    await expectError(.channelError) { try await push.value }
  }
}
