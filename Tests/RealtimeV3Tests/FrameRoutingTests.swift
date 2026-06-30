//
//  FrameRoutingTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Testing

@testable import RealtimeV3

@Suite struct FrameRoutingTests {
  @Test func phxReplyResolvesPendingPush() async throws {
    let (transport, server) = InMemoryTransport.pair()
    let rt = Realtime(url: URL(string: "wss://x")!, apiKey: "k", transport: transport)
    try await rt.connect()

    // Register a pending push for ref "1" in a concurrent task.
    async let pendingReply = rt._test_awaitReply(ref: "1", timeoutError: .channelJoinTimeout)

    // Wait until the registry has the push registered before injecting the reply.
    // This prevents a race where the frame arrives before the continuation is stored.
    var attempts = 0
    while await rt._test_pendingCount == 0 {
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      attempts += 1
      if attempts > 1000 {
        Issue.record("push not registered within timeout")
        return
      }
    }

    // Inject a phx_reply frame from the server.
    server.send(.text(#"[null,"1","realtime:room:1","phx_reply",{"status":"ok","response":{}}]"#))

    let result = try await pendingReply
    #expect(result.status == "ok")
  }
}
