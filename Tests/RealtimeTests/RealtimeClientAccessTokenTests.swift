//
//  RealtimeClientAccessTokenTests.swift
//  RealtimeTests
//
//  Created by Guilherme Souza on 20/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimeClientAccessTokenTests {
  @Test
  func theCallbackIsCalledTheLeewayBeforeTheTokenExpires() async throws {
    let expiry = Date().addingTimeInterval(120).timeIntervalSince1970
    let provider = TokenProvider { call in call == 1 ? makeJWT(exp: expiry) : "refreshed" }
    let host = await makeHost(provider)
    try await subscribe(host)
    #expect(provider.calls == 1)

    // Due at 120 s - 60 s of leeway. Two seconds either side absorb the whole-second rounding
    // of `exp`.
    await host.clock.advance(by: .seconds(58))
    #expect(provider.calls == 1)

    await host.clock.advance(by: .seconds(4))
    let push = try await host.receive(event: ChannelEvent.accessToken)
    #expect(push.payload["access_token"] == "refreshed")
    #expect(provider.calls == 2)
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
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (release, releaseContinuation) = AsyncStream<String>.makeStream()
    let provider = TokenProvider { call in
      guard call == 2 else { return "first" }
      startedContinuation.yield()
      for await token in release { return token }
      return nil
    }
    let host = await makeHost(provider)
    try await subscribe(host)
    await host.clock.advance(by: RealtimeClient.accessTokenRefreshInterval)

    let slowRefresh = Task { await host.client.setAuth() }
    var startedIterator = started.makeAsyncIterator()
    await startedIterator.next()

    await host.client.setAuth("newer")
    releaseContinuation.yield("stale")
    await slowRefresh.value

    #expect(await host.client.accessToken == "newer")
    _ = try await host.receive(event: ChannelEvent.accessToken)
    #expect(accessTokenPushes(host) == ["newer"])
  }

  @Test
  func concurrentRefreshesShareOneCallbackCall() async {
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (release, releaseContinuation) = AsyncStream<String>.makeStream()
    let provider = TokenProvider { _ in
      startedContinuation.yield()
      for await token in release { return token }
      return nil
    }
    let host = await makeHost(provider)

    async let first = host.client.currentAccessToken()
    var startedIterator = started.makeAsyncIterator()
    await startedIterator.next()
    async let second = host.client.currentAccessToken()
    releaseContinuation.yield("shared")

    #expect(await [first, second] == ["shared", "shared"])
    #expect(provider.calls == 1)
  }

  @Test
  func aJoinUsesTheStoredTokenWhileARefreshIsInFlight() async {
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (release, releaseContinuation) = AsyncStream<String>.makeStream()
    let provider = TokenProvider { _ in
      startedContinuation.yield()
      for await token in release { return token }
      return nil
    }
    let host = await makeHost(provider)
    await host.client.setAuth("stored")

    let slowRefresh = Task { await host.client.setAuth() }
    var startedIterator = started.makeAsyncIterator()
    await startedIterator.next()

    #expect(await host.client.currentAccessToken() == "stored")
    releaseContinuation.yield("refreshed")
    await slowRefresh.value
    #expect(await host.client.currentAccessToken() == "refreshed")
    #expect(provider.calls == 1)
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

  @Test
  func anExplicitTokenIsRefreshedTheLeewayBeforeItExpires() async throws {
    let provider = TokenProvider { call in "token-\(call)" }
    let host = await makeHost(provider)
    try await subscribe(host)

    await host.client.setAuth(makeJWT(exp: Date().addingTimeInterval(120).timeIntervalSince1970))
    await host.clock.advance(by: .seconds(58))
    #expect(provider.calls == 1)

    await host.clock.advance(by: .seconds(4))
    _ = try await host.receive(where: {
      $0.event == ChannelEvent.accessToken && $0.payload["access_token"] == "token-2"
    })
    #expect(provider.calls == 2)
  }

  // MARK: Helpers

  /// An `accessToken` callback that numbers its calls from 1 and answers each with `respond`.
  private final class TokenProvider: Sendable {
    private let count = LockIsolated(0)
    private let respond: @Sendable (_ call: Int) async -> String?

    init(_ respond: @escaping @Sendable (_ call: Int) async -> String?) {
      self.respond = respond
    }

    var calls: Int { count.value }

    var callback: @Sendable () async throws -> String? {
      { [count, respond] in
        let call = count.withValue {
          $0 += 1
          return $0
        }
        return await respond(call)
      }
    }
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
