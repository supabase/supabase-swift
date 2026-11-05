import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth
@testable import Realtime
@testable import Supabase

@Suite(.timeLimit(.minutes(1)))
struct SupabaseClientRealtimeTokenTests {
  private func makeClient(
    transport: some ClientTransport = RecordingTransport(),
    accessToken: (@Sendable () async throws -> String?)? = nil
  ) -> SupabaseClient {
    SupabaseClient(
      supabaseURL: URL(string: "https://project-ref.supabase.co")!,
      supabaseKey: "PUBLISHABLE_KEY",
      options: SupabaseClientOptions(
        auth: .init(storage: InMemoryTestStorage(), autoRefresh: .manual, accessToken: accessToken),
        global: .init(http: .init(transport: transport)),
        realtime: RealtimeClientOptions(handleAppLifecycle: false)
      )
    )
  }

  @Test
  func theSameTokenIsPushedOnce() {
    let client = makeClient(accessToken: { nil })

    #expect(client.realtimeTokenToPush(event: .signedIn, session: .stub(accessToken: "a")) == "a")
    #expect(
      client.realtimeTokenToPush(event: .tokenRefreshed, session: .stub(accessToken: "a")) == nil)
    #expect(
      client.realtimeTokenToPush(event: .userUpdated, session: .stub(accessToken: "a")) == nil)
    #expect(
      client.realtimeTokenToPush(event: .mfaChallengeVerified, session: .stub(accessToken: "b"))
        == "b")
    #expect(
      client.realtimeTokenToPush(event: .userUpdated, session: .stub(accessToken: "b")) == nil)
  }

  @Test
  func signedOutResetsToTheKeyAndTheNextSessionPushesAgain() {
    let client = makeClient(accessToken: { nil })

    #expect(client.realtimeTokenToPush(event: .signedIn, session: .stub(accessToken: "a")) == "a")
    #expect(client.realtimeTokenToPush(event: .signedOut, session: nil) == "PUBLISHABLE_KEY")
    #expect(client.realtimeTokenToPush(event: .signedIn, session: .stub(accessToken: "a")) == "a")
  }

  @Test
  func mfaVerifyPushesTheAAL2TokenToRealtime() async throws {
    let transport = RecordingTransport()
    transport.respond(when: { $0.path == "/auth/v1/token?grant_type=password" }) { _, _ in
      (HTTPResponse(status: .ok), sessionJSON(accessToken: "aal1-token", refreshToken: "refresh-1"))
    }
    let factorID = UUID()
    transport.respond(when: { $0.path == "/auth/v1/factors/\(factorID.uuidString)/verify" }) {
      _, _ in
      (HTTPResponse(status: .ok), sessionJSON(accessToken: "aal2-token", refreshToken: "refresh-2"))
    }
    let client = makeClient(transport: transport)
    let realtime = client.realtime

    _ = try await client.auth.signIn(email: "a@b.c", password: "x")
    await waitUntil { await realtime.accessToken == "aal1-token" }

    _ = try await client.auth.mfa.verify(factorID: factorID, challengeID: UUID(), code: "123456")
    await waitUntil { await realtime.accessToken == "aal2-token" }

    #expect(await realtime.accessToken == "aal2-token")
  }

  @Test
  func clientDeallocatesWithAnActiveEventsSubscription() async {
    final class WeakBox: @unchecked Sendable {
      weak var client: SupabaseClient?
    }
    let box = WeakBox()
    let task = LockIsolated<Task<Void, Never>?>(nil)

    func scope() {
      let client = makeClient()
      box.client = client
      let events = client.auth.events()
      task.setValue(Task { for await _ in events {} })
    }
    scope()

    await waitUntil { box.client == nil }

    #expect(box.client == nil, "SupabaseClient leaked while an events() subscription was active.")
    task.value?.cancel()
  }
}
