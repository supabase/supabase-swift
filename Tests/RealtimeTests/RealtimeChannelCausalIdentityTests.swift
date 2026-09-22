import ConcurrencyExtras
import Foundation
import Logging
import TestHelpers
import Testing

@testable import Realtime
@testable import RealtimeV2

@Suite
struct RealtimeChannelCausalIdentityTests {
  @Test
  @MainActor
  func channelRejectsStaleWireMessagesAndPublishesOnlyAcceptedIdentity() async throws {
    let (client, _) = FakeWebSocket.fakes()
    let socket = RealtimeClientV2(
      url: URL(string: "https://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(
        headers: ["apikey": "test-key"],
        accessToken: { "test-token" }
      ),
      wsTransport: { _, _ in client },
      http: HTTPClient(transport: RecordingTransport()),
      clock: ContinuousClock()
    )
    let channel = socket.channel("causal-wire")
    let lifecycleTrace = LockIsolated<[String]>([])
    let legacySystemCount = LockIsolated(0)
    let lifecycle = channel.lifecycleEvents()
    let lifecycleTask = Task {
      for await event in lifecycle {
        lifecycleTrace.withValue { trace in
          switch event {
          case .joinStarted(let join):
            trace.append("start:\(join.id):\(join.joinReference)")
          case .joinInvalidated(let join):
            trace.append("invalidate:\(join.id):\(join.joinReference)")
          case .statusChanged(let status, let join):
            trace.append("status:\(status):\(join?.id.uuidString ?? "none")")
          case .system(_, let join):
            trace.append("system:\(join.id):\(join.joinReference)")
          }
        }
      }
    }
    let legacySystem = channel.onSystem { _ in
      legacySystemCount.withValue { $0 += 1 }
    }
    defer {
      lifecycleTask.cancel()
      legacySystem.cancel()
      socket.disconnect()
    }

    await socket.connect()

    let subscribeA = Task { try await channel.subscribeWithError() }
    let joinA = try #require(await waitForJoin(on: channel))
    await channel.onMessage(systemMessage(join: joinA, topic: channel.topic))
    try await subscribeA.value
    #expect(legacySystemCount.value == 1)

    await channel.transportUnavailable()
    await channel.resetForReconnect()

    let subscribeB = Task { try await channel.subscribeWithError() }
    let joinB = try #require(await waitForJoin(on: channel, excluding: joinA.id))
    #expect(joinB.id != joinA.id)

    let sentinel = PostgresJoinConfig(
      event: .update,
      schema: "public",
      table: "causal_sentinel",
      filter: nil,
      id: 99
    )
    channel.callbackManager.setServerChanges(changes: [sentinel])

    await channel.onMessage(systemMessage(join: joinA, topic: channel.topic))
    await channel.onMessage(
      RealtimeMessageV2(
        joinRef: joinA.joinReference,
        ref: joinA.joinReference,
        topic: channel.topic,
        event: "phx_reply",
        payload: [
          "response": ["postgres_changes": []],
          "status": "ok",
        ]
      )
    )

    #expect(channel.status == .subscribing)
    #expect(legacySystemCount.value == 1)
    #expect(channel.callbackManager.serverChanges == [sentinel])

    await channel.onMessage(systemMessage(join: joinB, topic: channel.topic))
    try await subscribeB.value
    #expect(channel.status == .subscribed)
    #expect(legacySystemCount.value == 2)

    #expect(
      await waitUntil {
        lifecycleTrace.value.contains("system:\(joinB.id):\(joinB.joinReference)")
      })
    let trace = lifecycleTrace.value
    #expect(trace.contains("start:\(joinA.id):\(joinA.joinReference)"))
    #expect(trace.contains("invalidate:\(joinA.id):\(joinA.joinReference)"))
    #expect(trace.contains("start:\(joinB.id):\(joinB.joinReference)"))
    #expect(trace.contains("system:\(joinA.id):\(joinA.joinReference)"))
    #expect(trace.contains("system:\(joinB.id):\(joinB.joinReference)"))
    #expect(trace.filter { $0 == "system:\(joinA.id):\(joinA.joinReference)" }.count == 1)
  }

  @Test
  @MainActor
  func joinLifecycleIsOrderedAndStaleJoinMessagesCannotMutateCurrentJoin() async throws {
    let trace = LockIsolated<[String]>([])
    let joinCalls = LockIsolated(0)
    let acceptedSystems = LockIsolated<[UUID]>([])
    let acceptedReplies = LockIsolated<[UUID]>([])

    let manager = ChannelStateManager(
      topic: "causal-test",
      logger: supabaseDefaultLogger(label: "io.supabase.realtime"),
      maxRetryAttempts: 2,
      timeoutInterval: 1,
      clock: ContinuousClock(),
      makeRef: {
        joinCalls.withValue { $0 += 1 }
        return "join-\(joinCalls.value)"
      },
      ensureSocketConnected: { true },
      getClientChanges: { [] },
      joinOperation: { _, _ in },
      leaveOperation: {},
      retryDelay: { _ in 0.01 },
      stateDidChange: { state, join in
        let status: String
        switch state {
        case .unsubscribed: status = "unsubscribed"
        case .subscribing: status = "subscribing"
        case .subscribed: status = "subscribed"
        case .unsubscribing: status = "unsubscribing"
        }
        trace.withValue { $0.append("status:\(status):\(join?.joinReference ?? "none")") }
      },
      joinDidStart: { join in
        trace.withValue { $0.append("start:\(join.joinReference)") }
      },
      joinDidInvalidate: { join in
        trace.withValue { $0.append("invalidate:\(join.joinReference)") }
      }
    )

    let subscribeA = Task { try await manager.subscribe() }
    #expect(await waitUntil { joinCalls.value == 1 })
    let joinA = try #require(await manager.joinIdentity)
    #expect(
      await manager.acceptSystemMessage(joinRef: joinA.joinReference, successful: true) {
        join in
        acceptedSystems.withValue { $0.append(join.id) }
        trace.withValue { $0.append("system:\(join.joinReference)") }
      })
    try await subscribeA.value

    await manager.transportUnavailable()
    await manager.resetForReconnect()

    let subscribeB = Task { try await manager.subscribe() }
    #expect(await waitUntil { joinCalls.value == 2 })
    let joinB = try #require(await manager.joinIdentity)
    #expect(joinB.id != joinA.id)
    #expect(joinB.joinReference != joinA.joinReference)

    let pendingPush = PushV2(
      channel: nil,
      message: RealtimeMessageV2(
        joinRef: joinB.joinReference,
        ref: "pending-b",
        topic: "causal-test",
        event: "event",
        payload: [:]
      )
    )
    #expect(
      await manager.storePushIfJoinRefMatches(
        pendingPush,
        ref: "pending-b",
        joinRef: joinB.joinReference
      )
    )

    let staleSystemAccepted = await manager.acceptSystemMessage(
      joinRef: joinA.joinReference,
      successful: true
    ) { join in
      acceptedSystems.withValue { $0.append(join.id) }
    }
    #expect(!staleSystemAccepted)

    let staleReplyAccepted = await manager.acceptJoinReply(joinRef: joinA.joinReference) { join in
      acceptedReplies.withValue { $0.append(join.id) }
    }
    #expect(!staleReplyAccepted)
    #expect(
      await manager.removePush(ref: "pending-b", joinRef: joinA.joinReference) == nil,
      "A stale reply must not consume Join B's pending push"
    )
    #expect(
      await manager.removePush(ref: "pending-b", joinRef: joinB.joinReference) === pendingPush,
      "The current join must retain ownership of its pending push"
    )
    if case .subscribing = await manager.state {
      // Expected: neither stale message subscribed Join B.
    } else {
      Issue.record("Stale Join A message mutated Join B subscription state")
    }

    #expect(
      await manager.acceptJoinReply(joinRef: joinB.joinReference) { join in
        acceptedReplies.withValue { $0.append(join.id) }
        trace.withValue { $0.append("reply:\(join.joinReference)") }
      })
    try await subscribeB.value

    #expect(
      await manager.acceptSystemMessage(joinRef: joinB.joinReference, successful: true) {
        join in
        acceptedSystems.withValue { $0.append(join.id) }
        trace.withValue { $0.append("system:\(join.joinReference)") }
      })
    #expect(
      await manager.acceptSystemMessage(joinRef: joinB.joinReference, successful: true) {
        join in
        acceptedSystems.withValue { $0.append(join.id) }
        trace.withValue { $0.append("system:\(join.joinReference)") }
      })

    #expect(acceptedSystems.value == [joinA.id, joinB.id, joinB.id])
    #expect(acceptedReplies.value == [joinB.id])
    #expect(
      trace.value == [
        "status:subscribing:none",
        "start:join-1",
        "status:subscribed:join-1",
        "system:join-1",
        "invalidate:join-1",
        "status:unsubscribed:none",
        "status:subscribing:none",
        "start:join-2",
        "reply:join-2",
        "status:subscribed:join-2",
        "system:join-2",
        "system:join-2",
      ])
  }

  private func waitForJoin(
    on channel: RealtimeChannelV2,
    excluding excludedID: UUID? = nil
  ) async -> RealtimeChannelJoinIdentity? {
    for _ in 0..<200 {
      if let join = await channel.stateManager.joinIdentity, join.id != excludedID {
        return join
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
  }

  private func systemMessage(
    join: RealtimeChannelJoinIdentity,
    topic: String
  ) -> RealtimeMessageV2 {
    RealtimeMessageV2(
      joinRef: join.joinReference,
      ref: nil,
      topic: topic,
      event: "system",
      payload: [
        "extension": "postgres_changes",
        "status": "ok",
      ]
    )
  }
}
