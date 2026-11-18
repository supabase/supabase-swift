//
//  RealtimeCorePostgresTests.swift
//  RealtimeTests
//

import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

/// The Postgres changes transitions of ``RealtimeCore``: the join reply that confirms the join,
/// the `system` messages about the bindings, and the rejoin that adds a new binding.
@Suite
struct RealtimeCorePostgresTests {
  typealias Event = RealtimeCore.Event
  typealias Effect = RealtimeCore.Effect

  static let topic = "room"
  static let messages = PostgresJoinConfig(event: .insert, schema: "public", table: "messages")
  static let users = PostgresJoinConfig(event: .all, schema: "public", table: "users")
  static let withMessages = JoinSnapshot(bindings: [messages], presenceEnabled: false)
  static let noStreams = JoinSnapshot(bindings: [], presenceEnabled: false)

  /// The join reply `ok` confirms the join, as in realtime-js. With `waitsForSubscription`, the
  /// server holds that reply until the bindings are set up; without it, it sends it at once.
  @Test(arguments: [false, true])
  func joinWithBindingsConfirmsOnReply(waitsForSubscription: Bool) {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(
      Self.subscribe(
        w, configuration: Self.configuration(waitsForSubscription: waitsForSubscription),
        snapshot: Self.withMessages))

    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w, .success),
        .publishChannelStatus(.room, .subscribed),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
      ])
    #expect(harness.core.channels[.room]?.phase == .subscribed(joinRef: "1"))

    #expect(
      harness.send(.frame(Self.system(joinRef: "1", extension: "postgres_changes"))) == [
        .deliver(.room, .event(.postgresChangesReady))
      ])
    #expect(harness.core.channels[.room]?.phase == .subscribed(joinRef: "1"))
  }

  @Test
  func joinWithoutBindingsConfirmsOnReply() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.noStreams))

    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w, .success),
        .publishChannelStatus(.room, .subscribed),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
      ])
  }

  /// The server retries most failures, and realtime-js only passes the message on. The join
  /// stands, so broadcast and presence keep working.
  @Test(arguments: [false, true])
  func postgresFailureOnSubscribedChannelOnlyDelivers(waitsForSubscription: Bool) {
    var harness = CoreHarness.connected()
    _ = harness.send(
      Self.subscribe(
        harness.waiter(),
        configuration: Self.configuration(waitsForSubscription: waitsForSubscription),
        snapshot: Self.withMessages))
    _ = harness.send(.frame(Self.reply(ref: "1")))

    #expect(
      harness.send(
        .frame(Self.system(joinRef: "1", extension: "postgres_changes", error: "boom"))) == [
          .deliver(.room, .event(.postgresChangesFailed("boom")))
        ])
    #expect(harness.core.channels[.room]?.phase == .subscribed(joinRef: "1"))
  }

  @Test
  func postgresFailureBeforeTheReplyOnlyDelivers() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.withMessages))

    #expect(
      harness.send(
        .frame(Self.system(joinRef: "1", extension: "postgres_changes", error: "boom"))) == [
          .deliver(.room, .event(.postgresChangesFailed("boom")))
        ])
    #expect(harness.core.channels[.room]?.phase == .joining(ref: "1", attempt: 1))
    #expect(harness.send(.frame(Self.reply(ref: "1"))).first == .resume(w, .success))
  }

  @Test
  func staleSystemMessageIsIgnored() {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter(), snapshot: Self.withMessages))

    #expect(harness.send(.frame(Self.system(joinRef: "9", extension: "postgres_changes"))) == [])
    #expect(harness.core.channels[.room]?.phase == .joining(ref: "1", attempt: 1))
  }

  /// A `system` ok for the join confirms it, even before the reply.
  @Test(arguments: [noStreams, withMessages])
  func systemMessageConfirmsTheJoinBeforeTheReply(snapshot: JoinSnapshot) {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: snapshot))

    #expect(
      harness.send(.frame(Self.system(joinRef: "1", extension: "system"))) == [
        .resume(w, .success),
        .publishChannelStatus(.room, .subscribed),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
        .deliver(.room, .event(.replicationReady)),
      ])
    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
  }

  @Test
  func lateOkConfirmsATimedOutJoinWithBindings() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.withMessages))
    _ = harness.send(.timerFired(.joinTimeout(channel: .room, ref: "1")))

    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w, .success),
        .publishChannelStatus(.room, .subscribed),
        .cancel(.rejoin(channel: .room)),
      ])
    #expect(harness.core.channels[.room]?.phase == .subscribed(joinRef: "1"))
    #expect(harness.send(.timerFired(.rejoin(channel: .room))) == [])
  }

  @Test
  func postgresFailureForATimedOutJoinOnlyDelivers() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.withMessages))
    _ = harness.send(.timerFired(.joinTimeout(channel: .room, ref: "1")))

    #expect(
      harness.send(
        .frame(Self.system(joinRef: "1", extension: "postgres_changes", error: "boom"))) == [
          .deliver(.room, .event(.postgresChangesFailed("boom")))
        ])
    #expect(
      harness.core.channels[.room]?.phase
        == .waitingToRetry(attempt: 1, retryIn: .seconds(1), lastError: .joinTimeout))
    #expect(harness.core.channels[.room]?.subscribeWaiters == [w])
  }

  @Test
  func stalePostgresFailureDuringTheRejoinBackoffIsIgnored() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.withMessages))
    _ = harness.send(.timerFired(.joinTimeout(channel: .room, ref: "1")))

    #expect(
      harness.send(
        .frame(Self.system(joinRef: "9", extension: "postgres_changes", error: "boom"))) == [])
    #expect(
      harness.core.channels[.room]?.phase
        == .waitingToRetry(attempt: 1, retryIn: .seconds(1), lastError: .joinTimeout))
    #expect(harness.core.channels[.room]?.subscribeWaiters == [w])
  }

  @Test
  func timedOutJoinRefIsForgottenWhileWaitingForTheSocket() {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter(), snapshot: Self.noStreams))
    _ = harness.send(.timerFired(.joinTimeout(channel: .room, ref: "1")))
    _ = harness.send(.socketClosed(code: 1001, reason: nil))
    #expect(harness.core.channels[.room]?.phase == .waitingForSocket(attempt: 2))
    #expect(harness.core.channels[.room]?.timedOutJoinRef == nil)
    #expect(harness.send(.frame(Self.reply(ref: "1"))) == [])
  }

  @Test
  func newBindingOnSubscribedChannelRejoins() throws {
    var harness = Self.subscribed(snapshot: Self.noStreams)
    let snapshot = JoinSnapshot(bindings: [Self.messages], presenceEnabled: false)

    #expect(
      harness.send(.bindingsChanged(channel: .room, bindings: snapshot.bindings)) == [
        .send(Self.leave(joinRef: "1", ref: "2")),
        .publishChannelStatus(.room, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "3", snapshot: snapshot)),
        .schedule(.joinTimeout(channel: .room, ref: "3"), after: .seconds(10)),
      ])

    #expect(
      harness.send(.frame(Self.reply(ref: "3"))) == [
        .publishChannelStatus(.room, .subscribed),
        .deliver(.room, .event(.resubscribed)),
        .cancel(.joinTimeout(channel: .room, ref: "3")),
      ])
  }

  @Test
  func bindingAddedDuringTheJoinRejoinsOnConfirmation() throws {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.noStreams))

    #expect(
      harness.send(.bindingsChanged(channel: .room, bindings: Self.withMessages.bindings)) == [])
    #expect(
      harness.send(.frame(Self.reply(ref: "1"))) == [
        .resume(w, .success),
        .publishChannelStatus(.room, .subscribed),
        .send(Self.leave(joinRef: "1", ref: "2")),
        .publishChannelStatus(.room, .subscribing(attempt: 1)),
        .send(try Self.join(ref: "3", snapshot: Self.withMessages)),
        .schedule(.joinTimeout(channel: .room, ref: "3"), after: .seconds(10)),
        .cancel(.joinTimeout(channel: .room, ref: "1")),
      ])
  }

  @Test
  func sameBindingsDoNotRejoin() {
    var harness = Self.subscribed(snapshot: Self.withMessages)

    #expect(
      harness.send(.bindingsChanged(channel: .room, bindings: Self.withMessages.bindings)) == [])
  }

  @Test
  func removedBindingDoesNotRejoin() {
    var harness = Self.subscribed(
      snapshot: JoinSnapshot(bindings: [Self.messages, Self.users], presenceEnabled: false))

    #expect(
      harness.send(.bindingsChanged(channel: .room, bindings: Self.withMessages.bindings)) == [])
    #expect(harness.core.channels[.room]?.phase == .subscribed(joinRef: "1"))
  }

  /// `PostgresJoinConfig`'s `==` treats `.all` as matching any event; the rejoin rule does not.
  @Test
  func narrowerEventOnAJoinedTableRejoins() {
    var harness = Self.subscribed(
      snapshot: JoinSnapshot(bindings: [Self.users], presenceEnabled: false))
    var insertsOnly = Self.users
    insertsOnly.event = .insert

    let effects = harness.send(
      .bindingsChanged(channel: .room, bindings: [Self.users, insertsOnly]))

    #expect(effects.first == .send(Self.leave(joinRef: "1", ref: "2")))
  }

  /// A reply that comes after a `system` ok confirmed the join still stores the server's
  /// bindings, and changes nothing else.
  @Test
  func replyAfterASystemConfirmationStoresTheServerChanges() {
    var harness = CoreHarness.connected()
    _ = harness.send(Self.subscribe(harness.waiter(), snapshot: Self.withMessages))
    _ = harness.send(.frame(Self.system(joinRef: "1", extension: "postgres_changes")))

    let effects = harness.send(
      .frame(
        Self.reply(
          ref: "1",
          response: [
            "postgres_changes": [
              ["event": "INSERT", "schema": "public", "table": "messages", "id": 7]
            ]
          ])))

    #expect(effects == [])
    #expect(harness.core.channels[.room]?.phase == .subscribed(joinRef: "1"))
    #expect(
      harness.core.channels[.room]?.serverChanges == [ServerPostgresBinding(Self.messages, id: 7)])
  }

  @Test
  func serverChangesFromReplyDriveMatching() {
    var harness = CoreHarness.connected()
    _ = harness.send(
      Self.subscribe(
        harness.waiter(), configuration: Self.configuration(waitsForSubscription: true),
        snapshot: Self.withMessages))

    _ = harness.send(
      .frame(
        Self.reply(
          ref: "1",
          response: [
            "postgres_changes": [
              ["event": "INSERT", "schema": "public", "table": "messages", "id": 7]
            ]
          ])))

    let serverChanges = harness.core.channels[.room]?.serverChanges
    #expect(serverChanges == [ServerPostgresBinding(Self.messages, id: 7)])
  }

  /// The server may echo an event value this SDK does not know. The join still succeeds.
  @Test
  func unknownEchoedEventDoesNotFailTheJoin() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(
      Self.subscribe(
        w, configuration: Self.configuration(waitsForSubscription: true),
        snapshot: Self.withMessages))

    #expect(
      harness.send(
        .frame(
          Self.reply(
            ref: "1",
            response: [
              "postgres_changes": [
                ["event": "TRUNCATE", "schema": "public", "table": "messages", "id": 7]
              ]
            ]))) == [
          .resume(w, .success),
          .publishChannelStatus(.room, .subscribed),
          .cancel(.joinTimeout(channel: .room, ref: "1")),
        ])
    #expect(harness.core.channels[.room]?.serverChanges.map(\.event) == ["TRUNCATE"])
  }

  /// One echoed binding that does not decode is skipped. The others still drive matching.
  @Test
  func unreadableEchoedBindingIsSkipped() {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(
      Self.subscribe(
        w, configuration: Self.configuration(waitsForSubscription: true),
        snapshot: Self.withMessages))

    #expect(
      harness.send(
        .frame(
          Self.reply(
            ref: "1",
            response: [
              "postgres_changes": [
                ["event": "INSERT", "schema": "public", "table": "messages", "id": 7],
                ["event": "INSERT", "schema": 5],
              ]
            ]))) == [
          .resume(w, .success),
          .publishChannelStatus(.room, .subscribed),
          .cancel(.joinTimeout(channel: .room, ref: "1")),
        ])
    #expect(harness.core.channels[.room]?.serverChanges.map(\.id) == [7])
  }

  @Test
  func unreadableServerChangesFailTheJoin() throws {
    var harness = CoreHarness.connected()
    let w = harness.waiter()
    _ = harness.send(Self.subscribe(w, snapshot: Self.withMessages))
    let unreadable: JSONValue = "not a list"
    let decodingError = try #require(
      #expect(throws: (any Error).self) {
        try unreadable.decode(as: [ServerPostgresBinding.Lossy].self)
      })
    let failure = RealtimeError.unreadableJoinReply(decodingError)

    #expect(
      harness.send(
        .frame(Self.reply(ref: "1", response: ["postgres_changes": unreadable]))) == [
          .resume(w, .failure(failure)),
          .publishChannelStatus(.room, .failed(failure)),
          .cancel(.joinTimeout(channel: .room, ref: "1")),
        ])
  }

  // MARK: Helpers

  /// With `waitsForSubscription`, the server holds the join reply until the Postgres changes
  /// are set up.
  static func configuration(waitsForSubscription: Bool) -> RealtimeChannelConfiguration {
    var configuration = RealtimeChannelConfiguration()
    configuration.postgresChanges.waitsForSubscription = waitsForSubscription
    return configuration
  }

  static func subscribe(
    _ waiter: WaiterID, channel: ChannelID = .room,
    configuration: RealtimeChannelConfiguration = RealtimeChannelConfiguration(),
    snapshot: JoinSnapshot
  ) -> Event {
    .subscribe(
      channel: channel, topic: topic, configuration: configuration, waiter: waiter,
      snapshot: snapshot)
  }

  /// A connected harness whose channel joined with ref `"1"` and `snapshot`. It used waiter id 1.
  static func subscribed(snapshot: JoinSnapshot) -> CoreHarness {
    var harness = CoreHarness.connected()
    let room = harness.channel()
    _ = harness.send(subscribe(harness.waiter(), channel: room, snapshot: snapshot))
    _ = harness.send(.frame(reply(ref: "1")))
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
