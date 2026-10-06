//
//  RealtimeEngineTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct RealtimeEngineTests {
  let clock = TestClock()
  let server: FakeRealtimeServer
  let engine: RealtimeEngine
  let topic = "realtime:room"

  init() {
    server = FakeRealtimeServer(clock: clock)
    var configuration = RealtimeEngineConfiguration(url: URL(string: "ws://fake")!)
    configuration.connection = .init(
      reconnect: .steps([.seconds(1)]), idleDisconnectAfter: .seconds(50))
    configuration.channel = .init(
      rejoin: .steps([.seconds(1)]), rateLimitBackoff: .seconds(30),
      lingerAfterLastListener: .seconds(2))
    configuration.accessToken = { "token" }
    engine = RealtimeEngine(configuration: configuration, transport: server.transport, clock: clock)
  }

  private var joins: [RealtimeMessageV2] { server.sentMessages.filter { $0.event == "phx_join" } }

  private func eventually(
    _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @escaping @Sendable () async -> Bool
  ) async {
    let satisfied = await waitUntil(condition: condition)
    #expect(satisfied, comment, sourceLocation: sourceLocation)
  }

  /// A sleeper reaches the clock only once its task has run, and an advance made before that
  /// strands it. `Task.megaYield()` spawns 20 background-priority tasks, which both falls short
  /// and starves under CI load; plain yields at the test's own priority do not.
  private func settle() async {
    for _ in 0..<1_000 { await Task.yield() }
  }

  private func advance(by duration: Duration) async {
    await settle()
    await clock.advance(by: duration)
  }

  private func connectionState() async -> ConnectionMachine.State { await engine.connectionState }
  private func channelState() async -> ChannelMachine.State? { await engine.channelState(topic) }

  private func expectConnected(sourceLocation: SourceLocation = #_sourceLocation) async {
    let isConnected = await engine.connectionState.isConnected
    #expect(isConnected, sourceLocation: sourceLocation)
  }

  private func expectSubscribed(sourceLocation: SourceLocation = #_sourceLocation) async {
    let isSubscribed = await engine.channelState(topic)?.isSubscribed
    #expect(isSubscribed == true, sourceLocation: sourceLocation)
  }

  // MARK: - Connection

  @Test
  func connectOpensTheSocketAndReportsConnected() async throws {
    let states = await engine.connectionStates()
    let seen = LockIsolated([ConnectionMachine.State]())
    let pump = Task { for await state in states { seen.withValue { $0.append(state) } } }
    defer { pump.cancel() }

    try await engine.connect()

    await expectConnected()
    #expect(server.connectCount == 1)
    await eventually { seen.value.contains { $0.isConnected } }
  }

  @Test
  func connectThrowsOnARefusedUpgradeAndStopsRetrying() async throws {
    server.refuseNextUpgrade(status: 401)

    let error = await #expect(throws: RealtimeError.self) {
      try await engine.connect()
    }
    #expect(error?.isRetryable == false)
    let state = await engine.connectionState
    #expect(state.error?.message.contains("401") == true)
    await advance(by: .seconds(5))
    #expect(server.connectCount == 0)
  }

  @Test
  func connectRetriesATransientUpgradeFailureOnTheClock() async throws {
    server.refuseNextUpgrade(status: 503)

    let connecting = Task { try await engine.connect() }
    await eventually { [engine] in
      if case .reconnecting(1, .seconds(1), _) = await engine.connectionState { return true }
      return false
    }
    await advance(by: .seconds(1))
    try await connecting.value

    await expectConnected()
    #expect(server.connectCount == 1)
  }

  @Test
  func wakeSignalDuringBackoffReconnectsAtOnce() async throws {
    server.refuseNextUpgrade(status: 503)
    let connecting = Task { try await engine.connect() }
    await eventually { [engine] in await engine.connectionState.error != nil }

    await engine.wake()
    try await connecting.value

    await expectConnected()
  }

  @Test
  func disconnectClosesNormallyAndLeavesChannelsUnsubscribed() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    await engine.disconnect()

    #expect(server.clientCloseCode == .normalClosure)
    #expect(!server.isConnected)
    if case .disconnected(nil) = await engine.connectionState {
    } else {
      Issue.record("expected disconnected(nil)")
    }
    if case .unsubscribed = await engine.channelState(topic) {
    } else {
      Issue.record("expected unsubscribed")
    }

    try await engine.subscribe(topic)
    #expect(server.connectCount == 2)
    #expect(joins.count == 2)
  }

  @Test
  func pauseKeepsChannelsAndResumeRejoins() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    await engine.pause()
    #expect(!server.isConnected)
    if case .resubscribing(_, .zero, _) = await engine.channelState(topic) {
    } else {
      Issue.record("expected resubscribing")
    }

    await engine.resume()
    await eventually { await self.engine.channelState(self.topic)?.isSubscribed == true }
    #expect(server.connectCount == 2)
    #expect(joins.count == 2)
    #expect(joins[0].ref != joins[1].ref)
  }

  @Test
  func removingTheLastChannelDisconnectsAfterTheIdleDelay() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    await engine.removeChannel(topic)
    await expectConnected()
    await advance(by: .seconds(50))
    await eventually { [engine] in await !engine.connectionState.isConnected }
    #expect(!server.isConnected)
  }

  // MARK: - Subscribe

  @Test
  func subscribeConnectsSendsTheJoinAndResolvesOnOk() async throws {
    await engine.addChannel(topic, config: RealtimeJoinConfig(isPrivate: true))

    try await engine.subscribe(topic)

    #expect(server.connectCount == 1)
    let join = try #require(joins.first)
    #expect(join.joinRef == join.ref)
    #expect(join.topic == topic)
    #expect(join.payload["access_token"] == "token")
    #expect(join.payload["config"]?.objectValue?["private"] == true)
    await expectSubscribed()
  }

  @Test
  func concurrentColdStartSubscribesBothConverge() async throws {
    await engine.addChannel("realtime:a")
    await engine.addChannel("realtime:b")

    async let first: Void = engine.subscribe("realtime:a")
    async let second: Void = engine.subscribe("realtime:b")
    _ = try await (first, second)

    #expect(server.connectCount == 1)
    #expect(Set(joins.map(\.topic)) == ["realtime:a", "realtime:b"])
  }

  @Test
  func joinOkMapsPostgresBindingIDsByPosition() async throws {
    var config = RealtimeJoinConfig()
    config.postgresChanges = [
      PostgresJoinConfig(event: .insert, schema: "public", table: "todos"),
      PostgresJoinConfig(event: .all, schema: "public", table: "users"),
    ]
    await engine.addChannel(topic, config: config)

    try await engine.subscribe(topic)

    let ids = await engine.postgresChangeIDs(topic)
    #expect(ids.count == 2)
  }

  @Test
  func joinErrorSurfacesTheServerReason() async throws {
    server.joinReply = .error(reason: "Unauthorized: You do not have permissions")
    await engine.addChannel(topic)

    let error = await #expect(throws: RealtimeError.self) {
      try await engine.subscribe(topic)
    }
    #expect(error?.serverCode == RealtimeError.ServerCode.unauthorized)
    #expect(error?.message == "Unauthorized: You do not have permissions")
    let channelState = await engine.channelState(topic)
    #expect(channelState?.error?.kind == RealtimeError.Kind.unauthorized)
    await expectConnected()
  }

  @Test
  func transientJoinErrorRejoinsOnTheClockAndEmitsResubscribed() async throws {
    server.joinReply = .error(reason: "RealtimeRestarting: standby")
    await engine.addChannel(topic)
    let inbound = await engine.inbound(topic)
    let events = LockIsolated([ChannelInbound]())
    let pump = Task { for await event in inbound { events.withValue { $0.append(event) } } }
    defer { pump.cancel() }

    let subscribing = Task { try await engine.subscribe(topic) }
    await eventually { [engine] in
      if case .resubscribing(1, .seconds(1), _) = await engine.channelState(topic) { return true }
      return false
    }
    server.joinReply = .ok
    await advance(by: .seconds(1))
    try await subscribing.value

    #expect(joins.count == 2)
    await eventually {
      events.value.contains { if case .resubscribed = $0 { return true } else { return false } }
    }
  }

  @Test
  func joinTimeoutLeavesTheOldRefAndRejoins() async throws {
    server.joinReply = .silent
    await engine.addChannel(topic)

    let subscribing = Task { try await engine.subscribe(topic) }
    await eventually { [self] in joins.count == 1 }
    await advance(by: .seconds(15))
    await eventually { [server] in server.sentMessages.contains { $0.event == "phx_leave" } }
    server.joinReply = .ok
    await advance(by: .seconds(1))
    try await subscribing.value

    #expect(joins.count == 2)
  }

  @Test
  func unsubscribeSendsLeaveAndEndsOnTheReply() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    await engine.unsubscribe(topic)

    let leave = try #require(server.sentMessages.first { $0.event == "phx_leave" })
    #expect(leave.joinRef == joins[0].ref)
    if case .unsubscribed = await engine.channelState(topic) {
    } else {
      Issue.record("expected unsubscribed")
    }
  }

  @Test
  func unsubscribeOnADeadSocketDoesNotStall() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)
    server.closeConnection(code: .abnormalClosure, reason: nil)
    await eventually { [engine] in await !engine.connectionState.isConnected }

    await engine.unsubscribe(topic)

    if case .unsubscribed = await engine.channelState(topic) {
    } else {
      Issue.record("expected unsubscribed")
    }
    #expect(!server.sentMessages.contains { $0.event == "phx_leave" })
  }

  // MARK: - Inbound

  @Test
  func malformedFrameIsDroppedAndTheSocketStaysUp() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    server.deliver(.text("not a frame"))
    server.deliver(.binary(Data([0xFF, 0x00])))
    await settle()

    await expectConnected()
    await expectSubscribed()
    #expect(server.connectCount == 1)
  }

  @Test
  func stalePhxCloseAndPhxErrorAreIgnored() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    server.push(
      RealtimeMessageV2(joinRef: "stale", ref: nil, topic: topic, event: "phx_close", payload: [:]))
    server.push(
      RealtimeMessageV2(joinRef: "stale", ref: nil, topic: topic, event: "phx_error", payload: [:]))
    await settle()

    await expectSubscribed()
  }

  @Test
  func currentPhxErrorRejoinsWithBackoff() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    server.errorChannel(topic: topic)
    await eventually { [engine] in
      if case .resubscribing(1, .seconds(1), _) = await engine.channelState(topic) { return true }
      return false
    }
    await advance(by: .seconds(1))

    await eventually { await self.engine.channelState(self.topic)?.isSubscribed == true }
    #expect(joins.count == 2)
  }

  @Test
  func inboundFanOutDeliversMessagesAndRemovesListenersOnCancel() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)
    let events = LockIsolated([ChannelInbound]())
    let pump = Task {
      for await event in await engine.inbound(topic) { events.withValue { $0.append(event) } }
    }
    await eventually { [engine] in await engine.listenerCount(topic) == 1 }

    server.pushFastlane(
      topic: topic, event: "broadcast", payload: ["type": "broadcast", "event": "ping"])
    server.pushBroadcast(topic: topic, event: "pong", payload: ["n": 1])
    server.pushSystem(topic: topic, status: "ok", message: "Subscribed to PostgreSQL")

    await eventually { events.value.count == 3 }
    guard case .message(let first) = events.value[0], case .broadcast(let second) = events.value[1]
    else {
      Issue.record("unexpected events \(events.value)")
      return
    }
    #expect(first.event == "broadcast")
    #expect(second.event == "pong")

    pump.cancel()
    await eventually { [engine] in await engine.listenerCount(topic) == 0 }
  }

  // MARK: - Outbound

  @Test
  func framesLeaveInCallOrder() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    for index in 0..<3 {
      _ = try await engine.send(
        topic, event: "broadcast", payload: ["event": .string("m\(index)")], awaitReply: false)
    }

    await eventually { [server] in server.sentMessages.count == 4 }
    #expect(
      server.sentMessages.map(\.event) == ["phx_join", "broadcast", "broadcast", "broadcast"])
    #expect(server.sentMessages.dropFirst().map { $0.payload["event"] } == ["m0", "m1", "m2"])
    #expect(server.sentMessages.dropFirst().allSatisfy { $0.joinRef == joins[0].ref })
  }

  @Test
  func sendWithReplyResolvesOnAckAndTimesOutOnTheClock() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    server.acknowledgesBroadcasts = true
    let reply = try await engine.send(topic, event: "broadcast", payload: [:], awaitReply: true)
    #expect(reply?["status"] == "ok")

    server.acknowledgesBroadcasts = false
    let pending = Task {
      try await engine.send(topic, event: "broadcast", payload: [:], awaitReply: true)
    }
    await advance(by: .seconds(15))
    let error = await #expect(throws: RealtimeError.self) { try await pending.value }
    #expect(error?.kind == .timeout)
  }

  @Test
  func sendOnAnUnsubscribedChannelThrowsNotSubscribed() async throws {
    await engine.addChannel(topic)
    try await engine.connect()

    let error = await #expect(throws: RealtimeError.self) {
      try await engine.send(topic, event: "broadcast", payload: [:], awaitReply: false)
    }
    #expect(error?.kind == .notSubscribed)
  }

  @Test
  func removeChannelRejectsASubscribeMadeDuringTheLeave() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    server.dropsClientFrames = true
    let removal = Task { await engine.removeChannel(topic) }
    await settle()
    let resubscribe = Task { try await engine.subscribe(topic) }
    await advance(by: .seconds(15))
    await removal.value

    let error = await #expect(throws: RealtimeError.self) { try await resubscribe.value }
    #expect(error?.kind == .notSubscribed)
  }

  @Test
  func repliesNobodyWaitsForAreNotRetained() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)
    server.acknowledgesBroadcasts = true

    for _ in 0..<3 {
      try await engine.send(topic, event: "broadcast", payload: [:], awaitReply: false)
    }
    try await engine.send(topic, event: "broadcast", payload: [:], awaitReply: true)

    let retained = await engine.pendingReplyCount
    #expect(retained == 0)
  }

  @Test
  func binaryBroadcastGoesOutAsKind3() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    try await engine.sendBroadcast(topic, event: "blob", data: Data([1, 2]))

    await eventually { [server] in server.sentFrames.count == 2 }
    let last = try #require(server.sentMessages.last)
    #expect(last.event == "broadcast")
    #expect(last.payload["event"] == "blob")
    if case .binary = server.sentFrames.last {} else { Issue.record("expected a binary frame") }
  }

  // MARK: - Heartbeat and loss

  @Test
  func heartbeatIsSentOnTheIntervalAndATimeoutReconnectsWithoutLeaking() async throws {
    try await engine.connect()
    await advance(by: .seconds(25))
    await eventually { [server] in server.sentMessages.contains { $0.event == "heartbeat" } }
    await expectConnected()

    server.repliesToHeartbeats = false
    await advance(by: .seconds(25))
    await advance(by: .seconds(10))
    await eventually { [engine] in
      if case .reconnecting = await engine.connectionState { return true }
      return false
    }
    let timedOut = await connectionState().error
    #expect(timedOut?.kind == .timeout)

    server.repliesToHeartbeats = true
    await advance(by: .seconds(1))
    await eventually { [server] in server.connectCount == 2 }
    await eventually { [engine] in await engine.connectionState.isConnected }
    await advance(by: .seconds(25))
    await advance(by: .seconds(10))
    await settle()
    #expect(server.connectCount == 2)
    await expectConnected()
  }

  @Test
  func socketLossReconnectsAndRejoinsWithANewJoinRef() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    server.closeConnection(code: .abnormalClosure, reason: "gone")
    await eventually { [engine] in
      if case .reconnecting(1, .seconds(1), _) = await engine.connectionState { return true }
      return false
    }
    let lost = await connectionState().error
    #expect(lost?.closeCode == .abnormalClosure)
    await advance(by: .seconds(1))

    await eventually { await self.engine.channelState(self.topic)?.isSubscribed == true }
    #expect(server.connectCount == 2)
    #expect(joins.count == 2)
    #expect(joins[0].ref != joins[1].ref)
  }

  @Test
  func failedSendClosesTheSocketAndReconnects() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    server.failsNextSend = true
    try await engine.send(topic, event: "broadcast", payload: [:], awaitReply: false)

    await eventually { [server] in server.clientCloseCode != nil }
    await advance(by: .seconds(1))
    await eventually { [server] in server.connectCount == 2 }
    await eventually { await self.engine.channelState(self.topic)?.isSubscribed == true }
  }

  @Test
  func pendingReplyFailsWithNotConnectedWhenTheSocketIsLost() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    let pending = Task {
      try await engine.send(topic, event: "broadcast", payload: [:], awaitReply: true)
    }
    await settle()
    server.closeConnection(code: .abnormalClosure, reason: nil)

    let error = await #expect(throws: RealtimeError.self) { try await pending.value }
    #expect(error?.kind == .notConnected)
  }

  // MARK: - Token state (SDK-2100)

  private func makeTokenEngine(provider: @escaping @Sendable () async throws -> String?)
    -> RealtimeEngine
  {
    var configuration = RealtimeEngineConfiguration(url: URL(string: "ws://fake")!)
    configuration.connection = .init(
      reconnect: .steps([.seconds(1)]), idleDisconnectAfter: .seconds(50))
    configuration.channel = .init(
      rejoin: .steps([.seconds(1)]), rateLimitBackoff: .seconds(30),
      lingerAfterLastListener: .seconds(2))
    configuration.accessToken = provider
    // The refresh test advances past the heartbeat interval. `TestClock.advance` resumes sleepers
    // with only 20 background yields between them, so the heartbeat reply can lose that race and
    // tear the socket down mid-test.
    configuration.heartbeatInterval = .seconds(1_000)
    return RealtimeEngine(configuration: configuration, transport: server.transport, clock: clock)
  }

  private var accessTokenPushes: [RealtimeMessageV2] {
    server.sentMessages.filter { $0.event == "access_token" }
  }

  @Test
  func refreshesBeforeExpiryAndPushesTheNewTokenToJoinedChannels() async throws {
    let calls = LockIsolated(0)
    let engine = makeTokenEngine {
      let call = calls.withValue {
        $0 += 1; return $0
      }
      return makeJWT(exp: Date().addingTimeInterval(120).timeIntervalSince1970 + Double(call))
    }
    await engine.addChannel(topic)
    try await engine.subscribe(topic)
    #expect(calls.value == 1)
    #expect(joins.first?.payload["access_token"] != nil)
    await advance(by: .seconds(61))

    await eventually { calls.value == 2 }
    await eventually { [self] in accessTokenPushes.count == 1 }
    #expect(server.connectCount == 1)
    #expect(
      accessTokenPushes.first?.payload["access_token"] != joins.first?.payload["access_token"])
    #expect(accessTokenPushes.first?.joinRef == joins.first?.ref)
  }

  @Test
  func pushesAtMostOneTokenPerWindowPerChannelAndKeepsTheNewest() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    await engine.setAuth("t1")
    await engine.setAuth("t2")
    await engine.setAuth("t3")
    await eventually { [self] in accessTokenPushes.count == 1 }
    #expect(accessTokenPushes[0].payload["access_token"] == "t1")
    await advance(by: .seconds(10))
    await eventually { [self] in accessTokenPushes.count == 2 }
    #expect(accessTokenPushes[1].payload["access_token"] == "t3")
    await advance(by: .seconds(10))
    await settle()
    #expect(accessTokenPushes.count == 2)
  }

  @Test
  func nilAndUnchangedTokensNeverReachTheWire() async throws {
    let engine = makeTokenEngine { nil }
    await engine.addChannel(topic)
    try await engine.subscribe(topic)
    #expect(joins.first?.payload["access_token"] == nil)

    await engine.setAuth(nil)
    await engine.setAuth("same")
    await eventually { [self] in accessTokenPushes.count == 1 }
    await engine.setAuth("same")
    await advance(by: .seconds(10))
    await settle()

    #expect(accessTokenPushes.count == 1)
    #expect(!server.sentMessages.contains { $0.payload["access_token"] == .null })
  }

  @Test
  func expiredTokenJoinErrorRefreshesOnceThenFails() async throws {
    let calls = LockIsolated(0)
    let engine = makeTokenEngine {
      let call = calls.withValue {
        $0 += 1; return $0
      }
      return "token-\(call)"
    }
    server.joinReply = .error(reason: "InvalidJWTToken: Token has expired 5 seconds ago")
    await engine.addChannel(topic)

    let error = await #expect(throws: RealtimeError.self) {
      try await engine.subscribe(topic)
    }

    #expect(error?.serverCode == RealtimeError.ServerCode.invalidJWTToken)
    #expect(calls.value == 2)
    #expect(joins.count == 2)
    #expect(joins[0].payload["access_token"] == "token-1")
    #expect(joins[1].payload["access_token"] == "token-2")
  }

  // MARK: - Presence (SDK-2101)

  private func metas(_ refs: [String]) -> JSONValue {
    .object(["metas": .array(refs.map { .object(["phx_ref": .string($0)]) })])
  }

  private var presencePushes: [RealtimeMessageV2] {
    server.sentMessages.filter { $0.event == "presence" }
  }

  @Test
  func presenceStateAndDiffsUpdateTheTrackerAndFanOut() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)
    let events = LockIsolated([ChannelInbound]())
    let pump = Task {
      for await event in await engine.inbound(topic) { events.withValue { $0.append(event) } }
    }
    defer { pump.cancel() }
    await eventually { [engine] in await engine.listenerCount(topic) == 1 }

    server.pushPresenceDiff(topic: topic, joins: ["u2": metas(["r2"])], leaves: [:])
    server.pushPresenceState(topic: topic, state: ["u1": metas(["r1"])])
    server.pushPresenceDiff(topic: topic, joins: [:], leaves: ["u1": metas(["r1"])])

    await eventually { events.value.count == 2 }
    let state = await engine.presenceState(topic)
    #expect(Set(state.entries.keys) == ["u2"])
    guard case .presenceChanged(let first) = events.value[0],
      case .presenceChanged(let second) = events.value[1]
    else {
      Issue.record("unexpected events \(events.value)")
      return
    }
    #expect(Set(first.joins.keys) == ["u1", "u2"])
    #expect(second.leaves["u1"]?.map(\.ref) == ["r1"])
  }

  @Test
  func trackSendsThePayloadAndRejoinResendsIt() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    try await engine.trackPresence(topic, payload: ["name": "ana"])
    await eventually { [self] in presencePushes.count == 1 }
    #expect(presencePushes[0].payload["event"] == "track")
    #expect(presencePushes[0].payload["payload"] == ["name": "ana"])
    #expect(joins[0].payload["config"]?.objectValue?["presence"]?.objectValue?["enabled"] == false)

    server.errorChannel(topic: topic)
    await advance(by: .seconds(1))
    await eventually { [self] in joins.count == 2 && presencePushes.count == 2 }

    #expect(joins[1].payload["config"]?.objectValue?["presence"]?.objectValue?["enabled"] == true)
    #expect(presencePushes[1].payload["payload"] == ["name": "ana"])
    #expect(presencePushes[1].joinRef == joins[1].ref)
  }

  @Test
  func rejoinCancelsTheOldPresenceWindow() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)
    try await engine.trackPresence(topic, payload: ["n": 1])
    await eventually { [self] in presencePushes.count == 1 }

    server.errorChannel(topic: topic)
    await advance(by: .seconds(1))
    await eventually { [self] in joins.count == 2 && presencePushes.count == 2 }

    try await engine.trackPresence(topic, payload: ["n": 2])
    await advance(by: .seconds(5))
    await settle()
    #expect(presencePushes.count == 2)
    await advance(by: .seconds(1))
    await eventually { [self] in presencePushes.count == 3 }
    #expect(presencePushes[2].payload["payload"] == ["n": 2])
  }

  @Test
  func trackCallsAreCoalescedToTheNewestPayloadInsideTheWindow() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)

    try await engine.trackPresence(topic, payload: ["n": 1])
    try await engine.trackPresence(topic, payload: ["n": 2])
    try await engine.trackPresence(topic, payload: ["n": 3])
    await eventually { [self] in presencePushes.count == 1 }
    #expect(presencePushes[0].payload["payload"] == ["n": 1])
    await advance(by: .seconds(6))
    await eventually { [self] in presencePushes.count == 2 }
    #expect(presencePushes[1].payload["payload"] == ["n": 3])

    try await engine.trackPresence(topic, payload: ["n": 3])
    await advance(by: .seconds(6))
    await settle()
    #expect(presencePushes.count == 2)
  }

  @Test
  func untrackSendsUntrackAndStopsTheRejoinResend() async throws {
    await engine.addChannel(topic)
    try await engine.subscribe(topic)
    try await engine.trackPresence(topic, payload: ["n": 1])
    await eventually { [self] in presencePushes.count == 1 }
    await advance(by: .seconds(6))
    try await engine.untrackPresence(topic)
    await eventually { [self] in presencePushes.count == 2 }
    #expect(presencePushes[1].payload["event"] == "untrack")

    server.errorChannel(topic: topic)
    await advance(by: .seconds(1))
    await eventually { [self] in joins.count == 2 }
    await settle()
    #expect(presencePushes.count == 2)
  }

  @Test
  func trackOnAnUnsubscribedChannelThrowsNotSubscribed() async throws {
    await engine.addChannel(topic)

    let error = await #expect(throws: RealtimeError.self) {
      try await engine.trackPresence(topic, payload: [:])
    }
    #expect(error?.kind == .notSubscribed)
  }
}
