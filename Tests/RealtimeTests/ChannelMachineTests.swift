//
//  ChannelMachineTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Testing

@testable import Realtime

@Suite
struct ChannelMachineTests {
  typealias State = ChannelMachine.State
  typealias Event = ChannelMachine.Event
  typealias Effect = ChannelMachine.Effect

  enum Shape: Equatable {
    case unsubscribed
    case subscribing(attempt: Int)
    case subscribed
    case resubscribing(attempt: Int, retryIn: Duration)
    case unsubscribing
    case failed

    init(_ state: State) {
      switch state {
      case .unsubscribed: self = .unsubscribed
      case .subscribing(let attempt, _): self = .subscribing(attempt: attempt)
      case .subscribed: self = .subscribed
      case .resubscribing(let attempt, let retryIn, _):
        self = .resubscribing(attempt: attempt, retryIn: retryIn)
      case .unsubscribing: self = .unsubscribing
      case .failed: self = .failed
      }
    }
  }

  struct Row: CustomTestStringConvertible {
    let name: String
    let from: State
    let event: Event
    let to: Shape
    let effects: [Effect]
    var testDescription: String { name }
  }

  static let configuration = ChannelMachine.Configuration(
    rejoin: .steps([.seconds(1), .seconds(2), .seconds(5), .seconds(10)]),
    rateLimitBackoff: .seconds(30),
    lingerAfterLastListener: .seconds(2)
  )

  static let ok = Event.joinReplied(.success(ChannelMachine.JoinReply(postgresChangeIDs: [1])))
  static let fatal = RealtimeError.joinError(reason: "Unauthorized: no")
  static let expired = RealtimeError.joinError(
    reason: "InvalidJWTToken: Token has expired 1 seconds ago")
  static let rateLimited = RealtimeError.joinError(
    reason: "ChannelRateLimitReached: Too many channels")
  static let transient = RealtimeError.joinError(reason: "RealtimeRestarting: standby")
  static let lost = RealtimeError.socketClosed(code: .abnormalClosure, reason: nil)
  static let waitingForSocket = State.resubscribing(attempt: 1, retryIn: .zero, lastError: lost)
  static let waitingForTimer = State.resubscribing(
    attempt: 2, retryIn: .seconds(2), lastError: transient)

  static let rows: [Row] = [
    // §9.2 subscribe
    Row(
      name: "subscribe sends the join",
      from: .unsubscribed, event: .subscribeRequested,
      to: .subscribing(attempt: 1), effects: [.sendJoin]),
    Row(
      name: "subscribe after a fatal failure tries again",
      from: .failed(fatal), event: .subscribeRequested,
      to: .subscribing(attempt: 1), effects: [.sendJoin]),
    Row(
      name: "subscribe while subscribed resolves at once",
      from: .subscribed, event: .subscribeRequested,
      to: .subscribed, effects: [.resolveSubscribe]),
    Row(
      name: "subscribe while subscribing joins the wait",
      from: .subscribing(attempt: 1, isRejoin: false), event: .subscribeRequested,
      to: .subscribing(attempt: 1), effects: []),
    Row(
      name: "socket connected while subscribing sends the join",
      from: .subscribing(attempt: 1, isRejoin: false), event: .socketConnected,
      to: .subscribing(attempt: 1), effects: [.sendJoin]),
    // join ok
    Row(
      name: "first join ok resolves and re-tracks presence",
      from: .subscribing(attempt: 1, isRejoin: false), event: ok,
      to: .subscribed, effects: [.resolveSubscribe, .resendPresenceTrack]),
    Row(
      name: "a rejoin ok also emits the discontinuity",
      from: .subscribing(attempt: 2, isRejoin: true), event: ok,
      to: .subscribed, effects: [.resolveSubscribe, .resendPresenceTrack, .emitResubscribed]),
    // join errors by class
    Row(
      name: "fatal join error fails without a timer",
      from: .subscribing(attempt: 1, isRejoin: false), event: .joinReplied(.failure(fatal)),
      to: .failed, effects: [.rejectSubscribe, .finishDataStreams]),
    Row(
      name: "expired token refreshes once",
      from: .subscribing(attempt: 1, isRejoin: false), event: .joinReplied(.failure(expired)),
      to: .resubscribing(attempt: 1, retryIn: .zero), effects: [.refreshToken]),
    Row(
      name: "token refreshed sends the join again",
      from: .resubscribing(attempt: 1, retryIn: .zero, lastError: expired),
      event: .tokenRefreshed,
      to: .subscribing(attempt: 2), effects: [.sendJoin]),
    Row(
      name: "expired token after a refresh is fatal",
      from: .subscribing(attempt: 2, isRejoin: true), event: .joinReplied(.failure(expired)),
      to: .failed, effects: [.rejectSubscribe, .finishDataStreams]),
    Row(
      name: "rate limit backs off for the long interval",
      from: .subscribing(attempt: 1, isRejoin: false), event: .joinReplied(.failure(rateLimited)),
      to: .resubscribing(attempt: 1, retryIn: .seconds(30)),
      effects: [.scheduleRejoin(after: .seconds(30))]),
    Row(
      name: "retry class uses the rejoin steps",
      from: .subscribing(attempt: 1, isRejoin: false), event: .joinReplied(.failure(transient)),
      to: .resubscribing(attempt: 1, retryIn: .seconds(1)),
      effects: [.scheduleRejoin(after: .seconds(1))]),
    Row(
      name: "a later retry uses the next step",
      from: .subscribing(attempt: 3, isRejoin: true), event: .joinReplied(.failure(transient)),
      to: .resubscribing(attempt: 3, retryIn: .seconds(5)),
      effects: [.scheduleRejoin(after: .seconds(5))]),
    Row(
      name: "join timeout leaves the old ref and schedules a rejoin",
      from: .subscribing(attempt: 1, isRejoin: false), event: .joinTimedOut,
      to: .resubscribing(attempt: 1, retryIn: .seconds(1)),
      effects: [.sendLeave, .scheduleRejoin(after: .seconds(1))]),
    Row(
      name: "rejoin timer sends the join with the next attempt",
      from: waitingForTimer, event: .rejoinTimerFired,
      to: .subscribing(attempt: 3), effects: [.sendJoin]),
    // while subscribed
    Row(
      name: "system token expired refreshes and rejoins",
      from: .subscribed, event: .systemError(message: "Token has expired 3 seconds ago"),
      to: .resubscribing(attempt: 1, retryIn: .zero), effects: [.refreshToken]),
    Row(
      name: "the phx_close after a system error is ignored",
      from: .resubscribing(attempt: 1, retryIn: .zero, lastError: expired), event: .serverClosed,
      to: .resubscribing(attempt: 1, retryIn: .zero), effects: []),
    Row(
      name: "system rate limit backs off for the long interval",
      from: .subscribed, event: .systemError(message: "Too many messages per second"),
      to: .resubscribing(attempt: 1, retryIn: .seconds(30)),
      effects: [.scheduleRejoin(after: .seconds(30))]),
    Row(
      name: "system permission revoked is fatal and finishes streams",
      from: .subscribed,
      event: .systemError(
        message: "You no longer have permission to read from this Channel topic: x"),
      to: .failed, effects: [.finishDataStreams]),
    Row(
      name: "any other system error rejoins with backoff",
      from: .subscribed, event: .systemError(message: "Node request timeout"),
      to: .resubscribing(attempt: 1, retryIn: .seconds(1)),
      effects: [.scheduleRejoin(after: .seconds(1))]),
    Row(
      name: "phx_error rejoins with backoff",
      from: .subscribed, event: .serverErrored,
      to: .resubscribing(attempt: 1, retryIn: .seconds(1)),
      effects: [.scheduleRejoin(after: .seconds(1))]),
    Row(
      name: "a bare phx_close while subscribed rejoins with backoff",
      from: .subscribed, event: .serverClosed,
      to: .resubscribing(attempt: 1, retryIn: .seconds(1)),
      effects: [.scheduleRejoin(after: .seconds(1))]),
    Row(
      name: "socket lost while subscribed waits for the socket",
      from: .subscribed, event: .socketLost(lost),
      to: .resubscribing(attempt: 1, retryIn: .zero), effects: []),
    Row(
      name: "socket lost while subscribing keeps the attempt",
      from: .subscribing(attempt: 2, isRejoin: true), event: .socketLost(lost),
      to: .resubscribing(attempt: 2, retryIn: .zero), effects: []),
    Row(
      name: "socket lost while waiting on a timer cancels it",
      from: waitingForTimer, event: .socketLost(lost),
      to: .resubscribing(attempt: 2, retryIn: .zero), effects: [.cancelRejoin]),
    Row(
      name: "socket back while resubscribing rejoins",
      from: waitingForSocket, event: .socketConnected,
      to: .subscribing(attempt: 2), effects: [.sendJoin]),
    Row(
      name: "bindings changed while subscribed leaves and rejoins",
      from: .subscribed, event: .bindingsChanged,
      to: .subscribing(attempt: 1), effects: [.sendLeave, .sendJoin]),
    Row(
      name: "bindings changed while joining resends the join with them",
      from: .subscribing(attempt: 1, isRejoin: false), event: .bindingsChanged,
      to: .subscribing(attempt: 1), effects: [.sendLeave, .sendJoin]),
    Row(
      name: "bindings changed while unsubscribed waits for the next join",
      from: .unsubscribed, event: .bindingsChanged, to: .unsubscribed, effects: []),
    // unsubscribe
    Row(
      name: "unsubscribe while subscribed sends the leave",
      from: .subscribed, event: .unsubscribeRequested,
      to: .unsubscribing, effects: [.cancelLinger, .sendLeave]),
    Row(
      name: "leave completed ends the subscription",
      from: .unsubscribing, event: .leaveCompleted, to: .unsubscribed, effects: []),
    Row(
      name: "phx_close after a leave ends the subscription",
      from: .unsubscribing, event: .serverClosed, to: .unsubscribed, effects: []),
    Row(
      name: "unsubscribe while subscribing rejects the pending subscribe",
      from: .subscribing(attempt: 1, isRejoin: false), event: .unsubscribeRequested,
      to: .unsubscribed, effects: [.sendLeave, .rejectSubscribe]),
    Row(
      name: "unsubscribe while waiting on a timer cancels it",
      from: waitingForTimer, event: .unsubscribeRequested,
      to: .unsubscribed, effects: [.cancelRejoin, .rejectSubscribe]),
    Row(
      name: "unsubscribe after a failure clears it",
      from: .failed(fatal), event: .unsubscribeRequested, to: .unsubscribed, effects: []),
    Row(
      name: "socket lost while unsubscribing counts as left",
      from: .unsubscribing, event: .socketLost(lost), to: .unsubscribed, effects: []),
    // linger
    Row(
      name: "last listener ended starts the linger",
      from: .subscribed, event: .lastListenerEnded,
      to: .subscribed, effects: [.scheduleLinger(after: .seconds(2))]),
    Row(
      name: "a new listener cancels the linger",
      from: .subscribed, event: .listenerAdded, to: .subscribed, effects: [.cancelLinger]),
    Row(
      name: "linger timer leaves",
      from: .subscribed, event: .lingerTimerFired,
      to: .unsubscribing, effects: [.sendLeave]),
    // stale
    Row(
      name: "a stale join reply while unsubscribed is ignored",
      from: .unsubscribed, event: ok, to: .unsubscribed, effects: []),
    Row(
      name: "a stale rejoin timer while subscribed is ignored",
      from: .subscribed, event: .rejoinTimerFired, to: .subscribed, effects: []),
  ]

  @Test(arguments: rows)
  func transition(row: Row) {
    var state = row.from

    let effects = ChannelMachine.transition(&state, row.event, configuration: Self.configuration)

    #expect(Shape(state) == row.to)
    #expect(effects == row.effects)
  }

  @Test
  func failedStateExposesTheServerError() {
    var state = State.subscribing(attempt: 1, isRejoin: false)
    _ = ChannelMachine.transition(
      &state, .joinReplied(.failure(Self.fatal)), configuration: Self.configuration)

    #expect(state.error?.serverCode == .unauthorized)
    #expect(!state.isSubscribed)
    #expect(State.subscribed.isSubscribed)
    #expect(State.subscribed.error == nil)
  }

  @Test
  func systemErrorsBecomeChannelClosedErrors() {
    var state = State.subscribed
    _ = ChannelMachine.transition(
      &state, .systemError(message: "Too many messages per second"),
      configuration: Self.configuration)

    #expect(state.error?.kind == .channelClosed)
    #expect(state.error?.message == "Too many messages per second")
  }

  // MARK: - Classification (§3.5)

  struct ClassRow: CustomTestStringConvertible {
    let reason: String
    let expected: ChannelMachine.ErrorClass
    var testDescription: String { reason }
  }

  static let classes: [ClassRow] = [
    .init(reason: "TopicNameRequired: x", expected: .fatal),
    .init(reason: "MalformedJWT: x", expected: .fatal),
    .init(reason: "JwtSignatureError: x", expected: .fatal),
    .init(reason: "JwtSignerError: x", expected: .fatal),
    .init(reason: "InvalidJWTToken: Fields `role` and `exp` are required in JWT", expected: .fatal),
    .init(reason: "Unauthorized: x", expected: .fatal),
    .init(reason: "PrivateOnly: x", expected: .fatal),
    .init(reason: "TenantNotFound: x", expected: .fatal),
    .init(reason: "RealtimeDisabledForTenant: x", expected: .fatal),
    .init(reason: "RealtimeDisabledForConfiguration: x", expected: .fatal),
    .init(reason: "UnableToReplayMessages: x", expected: .fatal),
    .init(reason: "InvalidJWTToken: Token has expired 10 seconds ago", expected: .authRefresh),
    .init(reason: "ConnectionRateLimitReached: x", expected: .rateLimit),
    .init(reason: "ClientJoinRateLimitReached: x", expected: .rateLimit),
    .init(reason: "ChannelRateLimitReached: x", expected: .rateLimit),
    .init(reason: "RealtimeRestarting: x", expected: .retry),
    .init(reason: "InitializingProjectConnection: x", expected: .retry),
    .init(reason: "IncreaseConnectionPool: x", expected: .retry),
    .init(reason: "DatabaseLackOfConnections: x", expected: .retry),
    .init(reason: "DatabaseConnectionRateLimitReached: x", expected: .rateLimit),
    .init(reason: "UnableToConnectToProject: x", expected: .retry),
    .init(reason: "QueryCanceled: x", expected: .retry),
    .init(reason: "MissingPartition: x", expected: .retry),
    .init(reason: "TimeoutOnRpcCall: x", expected: .retry),
    .init(reason: "ErrorOnRpcCall: x", expected: .retry),
    .init(reason: "PostgresChangesSubscribeTimeout: x", expected: .retry),
    .init(reason: "UnknownErrorOnChannel: x", expected: .retry),
    .init(reason: "BrandNewCode: x", expected: .retry),
    .init(reason: "Realtime was unable to connect to the project database", expected: .retry),
    .init(reason: "Unknown Error on Channel", expected: .retry),
  ]

  @Test(arguments: classes)
  func classifiesJoinErrors(row: ClassRow) {
    #expect(ChannelMachine.classify(RealtimeError.joinError(reason: row.reason)) == row.expected)
  }

  @Test(arguments: [
    ("Token has expired 3 seconds ago", ChannelMachine.ErrorClass.authRefresh),
    ("Too many messages per second", .rateLimit),
    ("Too many presence messages per second", .rateLimit),
    ("Client presence rate limit exceeded", .rateLimit),
    ("You no longer have permission to read from this Channel topic: x", .fatal),
    ("Query was cancelled, please try again", .retry),
    ("Realtime was unable to connect to the project database", .retry),
  ])
  func classifiesSystemMessages(message: String, expected: ChannelMachine.ErrorClass) {
    #expect(ChannelMachine.classify(RealtimeError.channelClosed(message: message)) == expected)
  }

  // MARK: - Join reply verification

  @Test
  func joinReplyMapsIDsByPositionWhenBindingsMatch() throws {
    let declared = [
      PostgresJoinConfig(event: .insert, schema: "public", table: "todos", filter: nil),
      PostgresJoinConfig(event: .all, schema: "public", table: nil, filter: "id=eq.1"),
    ]
    var replied = declared
    replied[0].id = 11
    replied[1].id = 22

    let ids = try ChannelMachine.verify(declared: declared, replied: replied).get()

    #expect(ids == [11, 22])
  }

  @Test
  func joinReplyWithADifferentBindingIsAFatalMismatch() {
    let declared = [PostgresJoinConfig(event: .insert, schema: "public", table: "todos")]
    var replied = [PostgresJoinConfig(event: .insert, schema: "public", table: "users")]
    replied[0].id = 1

    let result = ChannelMachine.verify(declared: declared, replied: replied)

    guard case .failure(let error) = result else {
      Issue.record("expected a mismatch")
      return
    }
    #expect(error.kind == .server)
    #expect(!error.isRetryable)
    #expect(error.message.contains("mismatch"))
  }

  @Test
  func joinReplyWithFewerBindingsThanDeclaredIsAMismatch() {
    let declared = [PostgresJoinConfig(event: .insert, schema: "public", table: "todos")]

    let result = ChannelMachine.verify(declared: declared, replied: [])

    #expect((try? result.get()) == nil)
  }

  @Test
  func joinReplyWithNoBindingsOnEitherSideIsEmpty() throws {
    #expect(try ChannelMachine.verify(declared: [], replied: []).get() == [])
  }
}
