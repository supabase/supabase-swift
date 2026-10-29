import ConcurrencyExtras
import Foundation
import Helpers
import Phoenix
import PhoenixTesting
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct TokenBoxTests {
  @Test
  func theTokenIsRefreshedOneMinuteBeforeItExpires() async throws {
    let callback = TokenCallback(makeJWT(expiresIn: 180))
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    let connection = try await harness.connect()
    try await harness.client.channel("room").subscribeWithError()
    callback.set("t2")
    let callsBefore = callback.calls

    await harness.advance(by: .seconds(110))
    #expect(callback.calls == callsBefore, "no call before the leeway")
    await harness.advance(by: .seconds(15))

    let pushed = await within(.seconds(5)) { await connection.nextSent("access_token") }
    #expect(pushed?.accessToken == "t2")
  }

  @Test
  func setAuthCallsTheCallbackAtMostOncePerTenSeconds() async throws {
    let callback = TokenCallback("t1")
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    let connection = try await harness.connect()
    try await harness.client.channel("room").subscribeWithError()
    await harness.advance(by: .seconds(10))
    let callsBefore = callback.calls
    callback.appendsCallNumber = true

    for _ in 0..<50 {
      await harness.client.setAuth()
    }

    #expect(callback.calls == callsBefore + 1)
    let pushed = await connection.nextSent("access_token")
    #expect(pushed.accessToken == "t1-\(callsBefore + 1)")
    await harness.socket.settle()
    #expect(connection.unreadSent.allSatisfy { $0.event != "access_token" })
  }

  @Test
  func aTokenSetDuringACallbackCallWinsOverItsResult() async throws {
    let callback = TokenCallback("t1")
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    let connection = try await harness.connect()
    try await harness.client.channel("room").subscribeWithError()
    await harness.advance(by: .seconds(10))
    callback.hold()
    let refreshing = Task { await harness.client.setAuth() }
    await callback.nextHeldCall()

    await harness.client.setAuth("explicit")
    callback.release(returning: "stale")
    await refreshing.value

    let pushed = await connection.nextSent("access_token")
    #expect(pushed.accessToken == "explicit")
    await harness.socket.settle()
    #expect(connection.unreadSent.allSatisfy { $0.event != "access_token" })
  }

  @Test
  func aNilFromTheCallbackKeepsTheToken() async throws {
    let callback = TokenCallback("t1")
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    let connection = try await harness.connect()
    try await harness.client.channel("room").subscribeWithError()
    _ = await connection.nextSent("phx_join")
    await harness.advance(by: .seconds(10))
    callback.set(nil)

    await harness.client.setAuth()
    try await harness.client.channel("other").subscribeWithError()

    let join = await connection.nextSent("phx_join")
    #expect(join.accessToken == "t1")
    #expect(connection.unreadSent.allSatisfy { $0.event != "access_token" })
  }

  @Test
  func aHungCallbackDoesNotHoldUpAReconnect() async throws {
    let callback = TokenCallback("t1")
    let harness = RealtimeHarness {
      $0.accessToken = callback.closure
      $0.reconnectDelay = .seconds(1)
    }
    let connection = try await harness.connect()
    try await harness.client.channel("room").subscribeWithError()
    await harness.advance(by: .seconds(10))
    callback.hold()

    await connection.fail()
    await harness.advance(by: .seconds(1))
    await callback.nextHeldCall()
    await harness.advance(by: RealtimeClientOptions.defaultTimeout / 2)

    let next = try #require(
      await harness.nextConnection(within: .seconds(5)),
      "the socket connects once the wait for the callback ends")
    await next.open()
    let rejoin = await next.nextSent("phx_join")
    #expect(rejoin.accessToken == "t1")
  }

  @Test
  func aCancelledSetAuthReturnsWhileTheCallbackHangs() async throws {
    let callback = TokenCallback("t1")
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    try await harness.connect()
    await harness.advance(by: .seconds(10))
    callback.hold()
    let refreshing = Task { await harness.client.setAuth() }
    await callback.nextHeldCall()

    refreshing.cancel()

    let returned = await within(.seconds(5)) { await refreshing.value }
    #expect(returned != nil, "the cancelled setAuth returns before the callback")
  }

  @Test
  func signingOutDiscardsTheUserTokenFromAnEarlierCallbackCall() async throws {
    let userToken = makeJWT(expiresIn: 3600)
    let callback = TokenCallback(userToken)
    let harness = RealtimeHarness { $0.accessToken = callback.closure }
    let connection = try await harness.connect()
    try await harness.client.channel("room").subscribeWithError()
    await harness.advance(by: .seconds(10))
    callback.hold()
    let heartbeatRefresh = Task { await harness.client.setAuth() }
    await callback.nextHeldCall()

    await harness.client.setAuth("anon-key")
    callback.release(returning: userToken)
    await heartbeatRefresh.value
    callback.set(nil)
    await harness.advance(by: .seconds(10))
    await harness.client.setAuth()
    try await harness.client.channel("other").subscribeWithError()

    let pushed = await connection.nextSent("access_token")
    #expect(pushed.accessToken == "anon-key")
    let otherJoin = await connection.nextSent("phx_join")
    #expect(otherJoin.topic == "realtime:other")
    #expect(otherJoin.accessToken == "anon-key")
    #expect(connection.unreadSent.allSatisfy { $0.event != "access_token" })
  }

  @Test
  func aTokenSetWhileTheJoinIsInFlightReachesTheChannel() async throws {
    let harness = RealtimeHarness(replies: .realtime(join: { _ in nil })) {
      $0.headers[.authorization] = "Bearer t1"
    }
    let connection = try await harness.connect()
    let channel = harness.client.channel("room")
    let subscribing = Task { try await channel.subscribeWithError() }
    let join = await connection.nextSent("phx_join")
    #expect(join.accessToken == "t1")

    await harness.client.setAuth("t2")
    await connection.reply(to: join)
    try await subscribing.value

    let pushed = await within(.seconds(5)) { await connection.nextSent("access_token") }
    #expect(pushed?.accessToken == "t2")
  }
}

final class TokenCallback: Sendable {
  private struct State {
    var token: String?
    var calls = 0
    var appendsCallNumber = false
    var isHeld = false
    var held: [CheckedContinuation<String?, Never>] = []
  }

  private let state: LockIsolated<State>
  private let started: AsyncStream<Void>
  private let startedSink: AsyncStream<Void>.Continuation

  init(_ token: String?) {
    state = LockIsolated(State(token: token))
    (started, startedSink) = AsyncStream<Void>.makeStream()
  }

  var calls: Int { state.value.calls }

  var appendsCallNumber: Bool {
    get { state.value.appendsCallNumber }
    set { state.withValue { $0.appendsCallNumber = newValue } }
  }

  func set(_ token: String?) {
    state.withValue { $0.token = token }
  }

  func hold() {
    state.withValue { $0.isHeld = true }
  }

  func release(returning token: String?) {
    let held = state.withValue { state in
      state.isHeld = false
      defer { state.held = [] }
      return state.held
    }
    for call in held {
      call.resume(returning: token)
    }
  }

  func nextHeldCall() async {
    for await _ in started { return }
  }

  var closure: @Sendable () async throws -> String? {
    { [self] in await call() }
  }

  private func call() async -> String? {
    await withCheckedContinuation { continuation in
      let reply: String?? = state.withValue { state in
        state.calls += 1
        if state.isHeld {
          state.held.append(continuation)
          return .none
        }
        guard state.appendsCallNumber, let token = state.token else { return .some(state.token) }
        return .some("\(token)-\(state.calls)")
      }
      if let reply {
        continuation.resume(returning: reply)
      } else {
        startedSink.yield()
      }
    }
  }
}

func makeJWT(expiresIn seconds: TimeInterval) -> String {
  let exp = Date().addingTimeInterval(seconds).timeIntervalSince1970.rounded(.down)
  let claims: [String: Any] = ["role": "authenticated", "exp": exp]
  let header = Base64URL.encode(Data("{\"alg\":\"HS256\"}".utf8))
  let payload = Base64URL.encode(
    try! JSONSerialization.data(withJSONObject: claims, options: .sortedKeys))
  return "\(header).\(payload).sig"
}

extension OutboundFrame {
  var accessToken: String? {
    payload.jsonObject["access_token"]?.stringValue
  }
}
