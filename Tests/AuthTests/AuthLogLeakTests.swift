import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Auth

/// Drives a real `AuthClient` through every flow that handles a session, with a `.trace` logger,
/// and asserts that no token, verifier, password, or one-time code reaches a log line.
///
/// The tokens are opaque on purpose. A JWT-shaped one would also be caught by the redactor's
/// pattern; an opaque one is kept out only by the typed descriptions and the key rules.
@Suite(.timeLimit(.minutes(1)))
struct AuthLogLeakTests {
  private let recorder = LogRecorder()
  private let race: Race

  private let password = "password-secret-9f2"
  private let authorizationCode = "one-time-code-secret-7c1"

  init() {
    race = Race(logger: recorder.makeLogger())
  }

  private func expectNoLeak(
    of secrets: [String], sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      !recorder.entries.isEmpty, "Nothing was logged, so this proves nothing.",
      sourceLocation: sourceLocation)
    for secret in secrets {
      let line = recorder.entries.first { $0.contains(secret) }
      #expect(line == nil, "\(secret) reached: \(line ?? "")", sourceLocation: sourceLocation)
    }
  }

  @Test
  func signInRefreshAndSignOutKeepTokensOutOfTheLog() async throws {
    race.answerSignIn { [race] _ in race.issue("signin") }
    race.answerRefresh { [race] in try Race.ok(race.issue("refreshed")) }
    race.answerSignOut()
    let client = race.makeClient()

    try await client.signIn(email: "user@example.com", password: password)
    _ = try await client.session()
    _ = try await client.refreshSession()
    try await client.signOut()

    expectNoLeak(of: [
      password, "signin-access", "signin-refresh", "refreshed-access", "refreshed-refresh",
    ])
  }

  @Test
  func aFailedRefreshKeepsTheTokenAndTheServerBodyOutOfTheLog() async throws {
    race.answerSignIn { [race] _ in race.issue("held") }
    race.answerRefresh {
      (
        HTTPResponse(status: .badGateway),
        Data("upstream said: refresh_token=echoed-refresh-secret".utf8)
      )
    }
    let client = race.makeClient()
    try await client.signIn(email: "user@example.com", password: password)

    _ = try? await client.refreshSession()

    expectNoLeak(of: [password, "held-access", "held-refresh", "echoed-refresh-secret"])
  }

  @Test
  func readingAStoredSessionKeepsTheTokensOutOfTheLog() async throws {
    race.answerSignIn { [race] _ in race.issue("stored") }
    try await race.makeClient().signIn(email: "user@example.com", password: password)

    let relaunched = race.relaunch()
    _ = try await relaunched.session()
    var changes = relaunched.events().makeAsyncIterator()
    let initial = await changes.next()

    #expect(initial?.event == .initialSession)
    expectNoLeak(of: [password, "stored-access", "stored-refresh"])
  }

  @Test
  func aPKCERedirectKeepsTheVerifierAndTheCodeOutOfTheLog() async throws {
    race.answerCodeExchange { [race] _ in try Race.ok(race.issue("pkce")) }
    let client = race.makeClient()

    let flow = try await client.oauthSignInURL(.github)
    let verifier = try #require(
      try await client.dependencies.flowStore.pendingFlows().first?.verifier)
    let callback = URL(
      string: "com.example.app://callback?code=\(authorizationCode)#access_token=fragment-secret")!
    _ = try await client.handleRedirect(callback)

    #expect(flow.url.absoluteString.contains("code_challenge="))
    expectNoLeak(of: [
      verifier, authorizationCode, "fragment-secret", "pkce-access", "pkce-refresh",
    ])
  }

  @Test
  func autoRefreshFailuresKeepTheTokensOutOfTheLog() async throws {
    race.answerSignIn { [race] _ in race.issue("auto") }
    race.answerRefresh { throw URLError(.notConnectedToInternet) }
    let client = race.makeClient(autoRefresh: .automatic)
    try await client.signIn(email: "user@example.com", password: password)

    await race.waitForTheScheduledRefresh()
    await race.advance(to: Race.lifetime - Refresher.refreshLeadTime.timeInterval)
    #expect(await waitUntil { race.refreshRequestCount > 0 })

    expectNoLeak(of: [password, "auto-access", "auto-refresh"])
  }
}
