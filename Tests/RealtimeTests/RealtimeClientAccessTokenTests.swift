//
//  RealtimeClientAccessTokenTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 20/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import TestHelpers
import Testing

@testable import Realtime

// A broken wait fails after a minute instead of hanging the run.
@Suite(.timeLimit(.minutes(1)))
struct RealtimeClientAccessTokenTests {
  @Test
  func theCallbackIsCalledTheLeewayBeforeTheTokenExpires() async throws {
    let expiry = LockIsolated<TimeInterval>(0)
    let provider = TokenProvider { call in call == 1 ? makeJWT(exp: expiry.value) : "refreshed" }
    let host = await makeHost(provider)
    expiry.setValue(expiresIn(120, on: host))
    try await subscribe(host)
    #expect(provider.calls == 1)

    // Due at 120 s - 60 s of leeway.
    await host.clock.advance(by: .seconds(59))
    #expect(provider.calls == 1)

    await host.clock.advance(by: .seconds(1))
    let push = try await host.receive(event: ChannelEvent.accessToken)
    #expect(push.payload["access_token"] == "refreshed")
    #expect(provider.calls == 2)
  }

  @Test
  func anExplicitTokenIsRefreshedTheLeewayBeforeItExpires() async throws {
    let provider = TokenProvider { call in "token-\(call)" }
    let host = await makeHost(provider)
    try await subscribe(host)

    await host.client.setAuth(makeJWT(exp: expiresIn(120, on: host)))
    await host.clock.advance(by: .seconds(59))
    #expect(provider.calls == 1)

    await host.clock.advance(by: .seconds(1))
    _ = try await host.receive(where: {
      $0.event == ChannelEvent.accessToken && $0.payload["access_token"] == "token-2"
    })
    #expect(provider.calls == 2)
  }

  @Test
  func aDisconnectStopsTheTimer() async throws {
    let expiry = LockIsolated<TimeInterval>(0)
    let provider = TokenProvider { _ in makeJWT(exp: expiry.value) }
    let host = await makeHost(provider)
    expiry.setValue(expiresIn(120, on: host))
    try await subscribe(host)
    await host.client.disconnect()

    await host.client.setAuth(makeJWT(exp: expiresIn(121, on: host)))
    await host.clock.advance(by: .seconds(61))

    #expect(provider.calls == 1)
  }

  @Test
  func aReconnectStartsTheTimerAgain() async throws {
    let expiry = LockIsolated<TimeInterval>(0)
    let provider = TokenProvider { call in call == 1 ? makeJWT(exp: expiry.value) : "refreshed" }
    let host = await makeHost(provider)
    expiry.setValue(expiresIn(120, on: host))
    try await subscribe(host)
    await host.client.disconnect()
    try await host.client.connect()

    await host.clock.advance(by: .seconds(60))

    await provider.waitForCall(2)
  }

  @Test
  func theTimerDoesNotCallTheCallbackWhenDisconnected() async {
    let provider = TokenProvider { _ in "token" }
    let host = await makeHost(provider)

    await host.client.refreshAccessTokenIfConnected()

    #expect(provider.calls == 0)
  }

  @Test
  func twoQuickSetAuthCallsCallTheCallbackOnceAndPushOnce() async throws {
    let provider = TokenProvider { call in "token-\(call)" }
    let host = await makeHost(provider)
    try await subscribe(host)
    await host.clock.advance(by: RealtimeClient.accessTokenRefreshInterval)

    await host.client.setAuth()
    await host.client.setAuth()

    #expect(provider.calls == 2)
    _ = try await host.receive(event: ChannelEvent.accessToken)
    #expect(accessTokenPushes(host) == ["token-2"])

    await host.clock.advance(by: RealtimeClient.accessTokenRefreshInterval)
    await host.client.setAuth()
    #expect(provider.calls == 3)
  }

  @Test
  func aSlowRefreshDoesNotOverwriteANewerToken() async throws {
    let gate = CallbackGate()
    let provider = TokenProvider { call in call == 1 ? "first" : await gate.park() }
    let host = await makeHost(provider)
    try await subscribe(host)
    await host.clock.advance(by: RealtimeClient.accessTokenRefreshInterval)

    let slowRefresh = Task { await host.client.setAuth() }
    await gate.waitForCall()

    await host.client.setAuth("newer")
    gate.release("stale")
    await slowRefresh.value

    #expect(await host.client.accessToken == "newer")
    _ = try await host.receive(event: ChannelEvent.accessToken)
    #expect(accessTokenPushes(host) == ["newer"])
  }

  @Test
  func setAuthWithTheStoredTokenKeepsTheRefreshInFlight() async throws {
    let gate = CallbackGate()
    let provider = TokenProvider { call in call == 1 ? "first" : await gate.park() }
    let host = await makeHost(provider)
    try await subscribe(host)
    await host.clock.advance(by: RealtimeClient.accessTokenRefreshInterval)

    let refresh = Task { await host.client.setAuth() }
    await gate.waitForCall()

    await host.client.setAuth("first")
    gate.release("fresh")
    await refresh.value

    #expect(await host.client.accessToken == "fresh")
  }

  @Test
  func concurrentRefreshesShareOneCallbackCall() async {
    let gate = CallbackGate()
    let provider = TokenProvider { _ in await gate.park() }
    let host = await makeHost(provider)

    let first = Task { await host.client.currentAccessToken() }
    await gate.waitForCall()
    // Inside the interval, a second caller that did not share the call would get no token.
    let second = Task { await host.client.currentAccessToken() }
    gate.release("shared")

    #expect(await first.value == "shared")
    #expect(await second.value == "shared")
    #expect(provider.calls == 1)
  }

  @Test
  func aJoinUsesTheStoredTokenWhileARefreshIsInFlight() async {
    let gate = CallbackGate()
    let provider = TokenProvider { _ in await gate.park() }
    let host = await makeHost(provider)
    await host.client.setAuth("stored")

    let slowRefresh = Task { await host.client.setAuth() }
    await gate.waitForCall()

    #expect(await host.client.currentAccessToken() == "stored")
    gate.release("refreshed")
    await slowRefresh.value
    #expect(await host.client.currentAccessToken() == "refreshed")
    #expect(provider.calls == 1)
  }

  @Test
  func aCancelledCallerStopsWaitingForTheCallback() async {
    let gate = CallbackGate()
    let provider = TokenProvider { _ in await gate.park() }
    let host = await makeHost(provider)

    let waiting = Task { await host.client.currentAccessToken() }
    await gate.waitForCall()
    waiting.cancel()
    #expect(await waiting.value == nil)

    gate.release("late")
    #expect(await host.client.currentAccessToken() == "late")
    #expect(provider.calls == 1)
  }

  @Test
  func aCallbackThatIgnoresCancellationStillTimesOut() async {
    let clock = SignalingTestClock()
    let gate = CallbackGate()
    let provider = TokenProvider { call in call == 1 ? await gate.park() : "second" }
    let client = RealtimeClient(
      url: URL(string: "http://localhost:54321/realtime/v1")!,
      options: RealtimeClientOptions(accessToken: provider.callback, handleAppLifecycle: false),
      wsTransport: { _, _ in FakeWebSocket.fakes().0 },
      http: HTTPClient(transport: RecordingTransport()),
      clock: clock
    )

    async let token = client.currentAccessToken()
    await gate.waitForCall()
    await clock.advance(by: RealtimeClientOptions.defaultTimeout)
    #expect(await token == nil)

    await client.setAuth()
    #expect(await client.accessToken == "second")

    gate.release("too late")
    #expect(await client.accessToken == "second")
  }

  @Test
  func aRefreshForRejoinIgnoresTheInterval() async throws {
    let provider = TokenProvider { call in "token-\(call)" }
    let host = await makeHost(provider)
    try await subscribe(host)

    await host.client.setAuth()
    #expect(provider.calls == 1)

    await host.client.refreshTokenForRejoin()
    #expect(provider.calls == 2)
    #expect(await host.client.accessToken == "token-2")
  }

  // MARK: Helpers

  /// An `accessToken` callback that numbers its calls from 1 and answers each with `respond`.
  private final class TokenProvider: Sendable {
    private let count = LockIsolated(0)
    private let respond: @Sendable (_ call: Int) async -> String?
    private let callNumbers: AsyncStream<Int>
    private let callNumbersContinuation: AsyncStream<Int>.Continuation

    init(_ respond: @escaping @Sendable (_ call: Int) async -> String?) {
      self.respond = respond
      (callNumbers, callNumbersContinuation) = AsyncStream.makeStream()
    }

    var calls: Int { count.value }

    var callback: @Sendable () async throws -> String? {
      { [count, respond, callNumbersContinuation] in
        let call = count.withValue {
          $0 += 1
          return $0
        }
        callNumbersContinuation.yield(call)
        return await respond(call)
      }
    }

    /// Returns once call number `call` has started.
    func waitForCall(_ call: Int) async {
      for await started in callNumbers where started >= call { return }
    }
  }

  /// Holds callback calls in `park()` until the test releases them with a token. A parked call
  /// ignores cancellation, like a callback that never checks for it.
  private final class CallbackGate: Sendable {
    private let parked = LockIsolated<[CheckedContinuation<String?, Never>]>([])
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation

    init() {
      (started, startedContinuation) = AsyncStream.makeStream()
    }

    func park() async -> String? {
      await withCheckedContinuation { continuation in
        parked.withValue { $0.append(continuation) }
        startedContinuation.yield()
      }
    }

    /// Returns once a call is parked.
    func waitForCall() async {
      for await _ in started { return }
    }

    func release(_ token: String?) {
      let calls = parked.withValue {
        defer { $0 = [] }
        return $0
      }
      for call in calls {
        call.resume(returning: token)
      }
    }
  }

  /// An `exp` `seconds` after the host client's own now, so the refresh delay is exact.
  private func expiresIn(_ seconds: TimeInterval, on host: RealtimeTestHost) -> TimeInterval {
    host.client.now().addingTimeInterval(seconds).timeIntervalSince1970
  }

  private func makeHost(_ provider: TokenProvider) async -> RealtimeTestHost {
    await RealtimeTestHost(
      options: RealtimeClientOptions(
        heartbeatInterval: .seconds(3600),
        accessToken: provider.callback,
        handleAppLifecycle: false
      )
    )
  }

  private func subscribe(_ host: RealtimeTestHost) async throws {
    let channel = await host.client.channel("room")
    async let subscribed: Void = channel.subscribe()
    host.confirmJoin(try await host.receive(event: ChannelEvent.join))
    try await subscribed
  }

  private func accessTokenPushes(_ host: RealtimeTestHost) -> [String?] {
    host.frames.filter { $0.event == ChannelEvent.accessToken }
      .map { $0.payload["access_token"]?.stringValue }
  }
}
