//
//  RealtimeCorePostgresTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// The Postgres changes transitions of ``RealtimeCore``: the wait for "Subscribed to PostgreSQL"
/// after the join reply, its failure and timeout, and the rejoin that adds a new binding.
@Suite
struct RealtimeCorePostgresTests {
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  static let topic = "room"
  static let messages = PostgresJoinConfig(event: .insert, schema: "public", table: "messages")
  static let users = PostgresJoinConfig(event: .all, schema: "public", table: "users")
  static let withMessages = JoinSnapshot(bindings: [messages], presenceEnabled: false)
  static let noStreams = JoinSnapshot(bindings: [], presenceEnabled: false)

  @Test
  func joinWithBindingsWaitsForPostgresConfirmation() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.withMessages))

    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .schedule(.postgresTimeout(topic: Self.topic, ref: "1"), after: .seconds(15)),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
      ])
    #expect(
      harness.core.channels[Self.topic]?.phase == .joining(ref: "1", attempt: 1, stage: .postgres))

    #expect(
      harness.send(.frame(Self.system(joinRef: "1", extension: "postgres_changes"))) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .subscribed),
        .cancel(.postgresTimeout(topic: Self.topic, ref: "1")),
        .deliver(Self.topic, .event(.postgresChangesReady)),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .subscribed(joinRef: "1"))
  }

  /// Today's rule: the join waits for "Subscribed to PostgreSQL" only when it has bindings and
  /// the server does not hold the reply until they are set up.
  @Test
  func waitForSubscriptionConfirmsOnReply() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(
      Self.subscribe(w, configuration: Self.serverWaits, snapshot: Self.withMessages))

    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .subscribed),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
      ])
  }

  @Test
  func joinWithoutBindingsConfirmsOnReply() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.noStreams))

    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .subscribed),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
      ])
  }

  @Test
  func postgresFailureLeavesAndFails() {
    var harness = Self.waitingForPostgres()
    let failure = RealtimeError.postgresChangesFailed(reason: "boom")

    #expect(
      harness.send(
        .frame(Self.system(joinRef: "1", extension: "postgres_changes", error: "boom"))) == [
          .send(Self.leave(joinRef: "1", ref: "2")),
          .resume(WaiterID(rawValue: 1), .failure(failure)),
          .publishChannelStatus(Self.topic, .failed(failure)),
          .cancel(.postgresTimeout(topic: Self.topic, ref: "1")),
          .deliver(Self.topic, .event(.postgresChangesFailed("boom"))),
        ])
    #expect(harness.core.channels[Self.topic]?.phase == .failed(failure))
    #expect(harness.send(.timerFired(.postgresTimeout(topic: Self.topic, ref: "1"))) == [])
  }

  @Test
  func postgresFailureDuringTheReplyStageLeavesAndFails() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.withMessages))
    let failure = RealtimeError.postgresChangesFailed(reason: "boom")

    #expect(
      harness.send(
        .frame(Self.system(joinRef: "1", extension: "postgres_changes", error: "boom"))) == [
          .send(Self.leave(joinRef: "1", ref: "2")),
          .resume(w, .failure(failure)),
          .publishChannelStatus(Self.topic, .failed(failure)),
          .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
          .deliver(Self.topic, .event(.postgresChangesFailed("boom"))),
        ])
  }

  @Test
  func postgresFailureOnSubscribedChannelOnlyDelivers() {
    var harness = CoreHarness.connected()
    _ = harness.send(
      Self.subscribe(
        harness.waiter(), configuration: Self.serverWaits, snapshot: Self.withMessages))
    _ = harness.send(.frame(Self.reply(ref: "1")))

    #expect(
      harness.send(
        .frame(Self.system(joinRef: "1", extension: "postgres_changes", error: "boom"))) == [
          .deliver(Self.topic, .event(.postgresChangesFailed("boom")))
        ])
    #expect(harness.core.channels[Self.topic]?.phase == .subscribed(joinRef: "1"))
  }

  @Test
  func postgresTimeoutLeavesAndFails() {
    var harness = Self.waitingForPostgres()

    #expect(
      harness.send(.timerFired(.postgresTimeout(topic: Self.topic, ref: "1"))) == [
        .send(Self.leave(joinRef: "1", ref: "2")),
        .resume(WaiterID(rawValue: 1), .failure(.postgresChangesTimeout)),
        .publishChannelStatus(Self.topic, .failed(.postgresChangesTimeout)),
      ])
    #expect(harness.core.channels[Self.topic]?.phase == .failed(.postgresChangesTimeout))
    #expect(harness.send(.frame(Self.system(joinRef: "1", extension: "postgres_changes"))) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .failed(.postgresChangesTimeout))
  }

  @Test
  func staleSystemMessageIsIgnored() {
    var harness = Self.waitingForPostgres()

    #expect(harness.send(.frame(Self.system(joinRef: "9", extension: "postgres_changes"))) == [])
    #expect(harness.send(.timerFired(.postgresTimeout(topic: Self.topic, ref: "9"))) == [])
    #expect(
      harness.core.channels[Self.topic]?.phase == .joining(ref: "1", attempt: 1, stage: .postgres))
  }

  @Test
  func replicationSystemMessageDoesNotConfirmWhilePostgresPending() {
    var harness = Self.waitingForPostgres()

    #expect(
      harness.send(.frame(Self.system(joinRef: "1", extension: "system"))) == [
        .deliver(Self.topic, .event(.replicationReady))
      ])
    #expect(
      harness.core.channels[Self.topic]?.phase == .joining(ref: "1", attempt: 1, stage: .postgres))
  }

  /// Today's rule: with no Postgres wait pending, any `system` ok for the join confirms it.
  @Test
  func replicationSystemMessageConfirmsAJoinWithoutPostgresWait() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.noStreams))

    #expect(
      harness.send(.frame(Self.system(joinRef: "1", extension: "system"))) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .subscribed),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
        .deliver(Self.topic, .event(.replicationReady)),
      ])
    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
  }

  @Test
  func lateOkForAPostgresJoinWaitsForPostgres() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.withMessages))
    _ = harness.send(.timerFired(.joinTimeout(topic: Self.topic, ref: "1")))

    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .publishChannelStatus(Self.topic, .subscribing(attempt: 1)),
        .schedule(.postgresTimeout(topic: Self.topic, ref: "1"), after: .seconds(15)),
        .cancel(.rejoin(topic: Self.topic)),
      ])
    #expect(
      harness.core.channels[Self.topic]?.phase == .joining(ref: "1", attempt: 1, stage: .postgres))
    #expect(harness.core.channels[Self.topic]?.subscribeWaiters == [w])
    #expect(harness.send(.timerFired(.rejoin(topic: Self.topic))) == [])

    #expect(
      harness.send(.frame(Self.system(joinRef: "1", extension: "postgres_changes"))).first
        == .resume(w, .success))
  }

  @Test
  func timedOutJoinRefIsForgottenWhileWaitingForTheSocket() {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter(), snapshot: Self.noStreams))
    _ = harness.send(.timerFired(.joinTimeout(topic: Self.topic, ref: "1")))
    _ = harness.send(.disconnectRequested(code: nil, reason: nil))
    _ = harness.send(.timerFired(.rejoin(topic: Self.topic)))
    #expect(harness.core.channels[Self.topic]?.phase == .waitingForSocket(attempt: 2))
    #expect(harness.core.channels[Self.topic]?.timedOutJoinRef == nil)

    _ = harness.send(.socketOpenFailed(.transport("unreachable")))
    #expect(
      harness.core.channels[Self.topic]?.phase
        == .waitingToRetry(attempt: 2, retryIn: .seconds(2), lastError: .notConnected))
    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
  }

  @Test
  func newBindingOnSubscribedChannelRejoins() throws {
    var harness = Self.subscribed(snapshot: Self.noStreams)
    let snapshot = JoinSnapshot(bindings: [Self.messages], presenceEnabled: false)

    #expect(
      harness.send(.bindingsChanged(topic: Self.topic, snapshot: snapshot)) == [
        .send(Self.leave(joinRef: "1", ref: "2")),
        .publishChannelStatus(Self.topic, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "3", snapshot: snapshot)),
        .schedule(.joinTimeout(topic: Self.topic, ref: "3"), after: .seconds(10)),
      ])

    _ = harness.send(.frame(Self.reply(ref: "3")))
    #expect(
      harness.send(.frame(Self.system(joinRef: "3", extension: "postgres_changes"))) == [
        .publishChannelStatus(Self.topic, .subscribed),
        .deliver(Self.topic, .event(.resubscribed)),
        .cancel(.postgresTimeout(topic: Self.topic, ref: "3")),
        .deliver(Self.topic, .event(.postgresChangesReady)),
      ])
  }

  @Test
  func bindingAddedDuringTheJoinRejoinsOnConfirmation() throws {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.noStreams))

    #expect(harness.send(.bindingsChanged(topic: Self.topic, snapshot: Self.withMessages)) == [])
    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w, .success),
        .publishChannelStatus(Self.topic, .subscribed),
        .send(Self.leave(joinRef: "1", ref: "2")),
        .publishChannelStatus(Self.topic, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "3", snapshot: Self.withMessages)),
        .schedule(.joinTimeout(topic: Self.topic, ref: "3"), after: .seconds(10)),
        .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
      ])
  }

  @Test
  func sameBindingsDoNotRejoin() {
    var harness = Self.subscribed(snapshot: Self.withMessages)

    #expect(harness.send(.bindingsChanged(topic: Self.topic, snapshot: Self.withMessages)) == [])
  }

  @Test
  func removedBindingDoesNotRejoin() {
    var harness = Self.subscribed(
      snapshot: JoinSnapshot(bindings: [Self.messages, Self.users], presenceEnabled: false))

    #expect(harness.send(.bindingsChanged(topic: Self.topic, snapshot: Self.withMessages)) == [])
    #expect(harness.core.channels[Self.topic]?.phase == .subscribed(joinRef: "1"))
  }

  /// `PostgresJoinConfig`'s `==` treats `.all` as matching any event; the rejoin rule does not.
  @Test
  func narrowerEventOnAJoinedTableRejoins() {
    var harness = Self.subscribed(
      snapshot: JoinSnapshot(bindings: [Self.users], presenceEnabled: false))
    var insertsOnly = Self.users
    insertsOnly.event = .insert

    let effects = harness.send(
      .bindingsChanged(
        topic: Self.topic,
        snapshot: JoinSnapshot(bindings: [Self.users, insertsOnly], presenceEnabled: false)))

    #expect(effects.first == .send(Self.leave(joinRef: "1", ref: "2")))
  }

  @Test
  func serverChangesFromReplyDriveMatching() {
    var harness = CoreHarness.connected()
    _ = harness.send(
      Self.subscribe(
        harness.waiter(), configuration: Self.serverWaits, snapshot: Self.withMessages))

    _ = harness.send(
      .frame(
        Self.reply(
          ref: "1",
          response: [
            "postgres_changes": [
              ["event": "INSERT", "schema": "public", "table": "messages", "id": 7]
            ]
          ])))

    let serverChanges = harness.core.channels[Self.topic]?.serverChanges
    #expect(serverChanges == [Self.messages])
    #expect(serverChanges?.map(\.id) == [7])
  }

  @Test
  func unreadableServerChangesFailTheJoin() throws {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.withMessages))
    let unreadable: JSONValue = "not a list"
    let decodingError = try #require(
      #expect(throws: (any Error).self) {
        try unreadable.decode(as: [PostgresJoinConfig].self)
      })
    let failure = RealtimeError.unreadableJoinReply(decodingError)

    #expect(
      harness.send(
        .frame(Self.reply(ref: "1", response: ["postgres_changes": unreadable]))) == [
          .resume(w, .failure(failure)),
          .publishChannelStatus(Self.topic, .failed(failure)),
          .cancel(.joinTimeout(topic: Self.topic, ref: "1")),
        ])
  }

  // MARK: Helpers

  /// The server holds the join reply until the Postgres changes are set up.
  static var serverWaits: RealtimeChannelConfiguration {
    var configuration = RealtimeChannelConfiguration()
    configuration.postgresChanges.waitForSubscription = true
    return configuration
  }

  static func subscribe(
    _ waiter: WaiterID,
    configuration: RealtimeChannelConfiguration = RealtimeChannelConfiguration(),
    snapshot: JoinSnapshot
  ) -> Event {
    .subscribe(topic: topic, configuration: configuration, waiter: waiter, snapshot: snapshot)
  }

  /// A connected harness whose join with ref `"1"` carried ``messages`` and got its reply, so it
  /// waits for "Subscribed to PostgreSQL". It used waiter id 1.
  static func waitingForPostgres() -> CoreHarness {
    var harness = CoreHarness.connected()
    _ = harness.send(subscribe(harness.waiter(), snapshot: withMessages))
    _ = harness.send(.frame(reply(ref: "1")))
    return harness
  }

  /// A connected harness whose channel joined with ref `"1"` and `snapshot`. It used waiter id 1.
  static func subscribed(snapshot: JoinSnapshot) -> CoreHarness {
    var harness = CoreHarness.connected()
    _ = harness.send(subscribe(harness.waiter(), snapshot: snapshot))
    _ = harness.send(.frame(reply(ref: "1")))
    if !snapshot.bindings.isEmpty {
      _ = harness.send(.frame(system(joinRef: "1", extension: "postgres_changes")))
    }
    return harness
  }

  static func join(ref: Ref, snapshot: JoinSnapshot) throws -> RealtimeMessage {
    let payload = RealtimeJoinPayload(
      config: RealtimeJoinConfig(
        RealtimeChannelConfiguration(), bindings: snapshot.bindings,
        presenceEnabled: snapshot.presenceEnabled),
      accessToken: nil, version: nil)
    return RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_join",
      payload: try JSONObject(payload))
  }

  static func leave(joinRef: Ref, ref: Ref) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: ref, topic: "realtime:\(topic)", event: "phx_leave", payload: [:])
  }

  static func reply(ref: Ref, response: JSONObject = [:]) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: ref, ref: ref, topic: "realtime:\(topic)", event: "phx_reply",
      payload: ["status": "ok", "response": .object(response)])
  }

  static func system(joinRef: Ref?, extension: String, error: String? = nil) -> RealtimeMessage {
    RealtimeMessage(
      joinRef: joinRef, ref: nil, topic: "realtime:\(topic)", event: "system",
      payload: [
        "status": error == nil ? "ok" : "error",
        "extension": .string(`extension`),
        "message": .string(error ?? "Subscribed to PostgreSQL"),
      ])
  }
}
