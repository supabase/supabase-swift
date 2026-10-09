//
//  SupabaseClientRealtimeTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 08/10/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Logging
import TestHelpers
import Testing

@testable import Realtime
@testable import Supabase

@Suite(.timeLimit(.minutes(1)))
struct SupabaseClientRealtimeTests {
  let clock = TestClock()
  let server: FakeRealtimeServer

  init() {
    server = FakeRealtimeServer(clock: clock)
  }

  /// Answers every `/token` call with a new session, `user-token-1`, `user-token-2`, …, and
  /// `/logout` with 204.
  private static func authServer() -> ClosureTransport {
    let issued = LockIsolated(0)
    return ClosureTransport { request, _ in
      if request.path?.contains("/logout") == true {
        return (HTTPTypes.HTTPResponse(status: .noContent), nil)
      }
      let count = issued.withValue {
        $0 += 1
        return $0
      }
      let body = """
        {
          "access_token": "user-token-\(count)",
          "token_type": "bearer",
          "expires_in": 3600,
          "expires_at": \(Int(Date().timeIntervalSince1970) + 3600),
          "refresh_token": "refresh-\(count)",
          "user": {
            "id": "f33d3ec9-a2ee-47c4-80e1-5bd919f3d8b8",
            "aud": "authenticated",
            "app_metadata": {},
            "user_metadata": {},
            "created_at": "2022-03-30T10:33:41.005433Z",
            "updated_at": "2022-03-30T10:33:41.022688Z"
          }
        }
        """
      return (
        HTTPTypes.HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
        HTTPBody(Data(body.utf8))
      )
    }
  }

  private func makeClient(
    configure: (inout RealtimeClientOptions) -> Void = { _ in }
  ) -> SupabaseClient {
    var realtime = RealtimeClientOptions()
    realtime.webSocketTransport = server.transport
    realtime.handleAppLifecycle = false
    configure(&realtime)
    return SupabaseClient(
      supabaseURL: URL(string: "http://project-ref.supabase.co")!,
      supabaseKey: "anon-key",
      options: SupabaseClientOptions(
        auth: .init(storage: InMemoryLocalStorage(), automaticallyRefreshesToken: false),
        global: .init(
          http: .init(transport: Self.authServer()),
          logger: Logger(label: "global"),
          clock: clock),
        realtime: realtime
      )
    )
  }

  private var joins: [RealtimeMessageV2] { server.sentMessages.filter { $0.event == "phx_join" } }

  private func sentAccessToken(_ token: String) -> Bool {
    server.sentMessages.contains {
      $0.event == "access_token" && $0.payload["access_token"] == .string(token)
    }
  }

  @Test
  func authEventsDoNotCreateTheRealtimeClient() async throws {
    let client = makeClient()

    try await client.auth.signIn(email: "user@example.com", password: "secret")
    for _ in 0..<1_000 { await Task.yield() }

    #expect(client.mutableState.realtime == nil)
  }

  @Test
  func channelsJoinWithTheAnonKeyWithoutASession() async throws {
    let client = makeClient()

    try await client.channel("room").subscribe()

    #expect(joins.last?.payload["access_token"] == "anon-key")
  }

  @Test
  func channelsJoinWithTheSessionToken() async throws {
    let client = makeClient()
    try await client.auth.signIn(email: "user@example.com", password: "secret")

    try await client.channel("room").subscribe()

    #expect(joins.last?.payload["access_token"] == "user-token-1")
  }

  @Test
  func tokenRefreshReachesAJoinedChannel() async throws {
    let client = makeClient()
    try await client.auth.signIn(email: "user@example.com", password: "secret")
    try await client.channel("room").subscribe()

    try await client.auth.refreshSession()

    #expect(await waitUntil { sentAccessToken("user-token-2") })
  }

  @Test
  func signOutPushesTheAnonKeyToAJoinedChannel() async throws {
    let client = makeClient()
    try await client.auth.signIn(email: "user@example.com", password: "secret")
    try await client.channel("room").subscribe()

    try await client.auth.signOut()

    #expect(await waitUntil { sentAccessToken("anon-key") })
  }

  @Test
  func mfaChallengeVerifiedPushesTheNewTokenToAJoinedChannel() async throws {
    let client = makeClient()
    try await client.auth.signIn(email: "user@example.com", password: "secret")
    try await client.channel("room").subscribe()

    _ = try await client.auth.mfa.verify(
      params: MFAVerifyParams(factorId: UUID(), challengeId: UUID(), code: "123456"))

    #expect(await waitUntil { sentAccessToken("user-token-2") })
  }

  @Test
  func channelsAndRemoveAllChannelsDoNotCreateTheRealtimeClient() async {
    let client = makeClient()

    #expect(client.channels.isEmpty)
    await client.removeAllChannels()

    #expect(client.mutableState.realtime == nil)
  }

  @Test
  func aCustomLoggerSurvives() async {
    let client = makeClient { $0.logger = Logger(label: "custom") }

    #expect(client.realtime.engine.logger.label == "custom")
  }

  @Test
  func theGlobalLoggerIsUsedByDefault() async {
    let client = makeClient()

    let logger = client.realtime.engine.logger
    #expect(logger.label == "global")
    #expect(logger[metadataKey: "system"] == "realtime")
  }

  @Test
  func theFacadeForwardsToTheRealtimeClient() async {
    let client = makeClient()

    let channel = client.channel("room")

    #expect(client.realtime.channel("room") === channel)
    #expect(client.channels.map(\.topic) == ["room"])
    await client.removeChannel(channel)
    #expect(client.channels.isEmpty)
  }
}
