import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite(.timeLimit(.minutes(1)))
struct AuthClientRedirectTests {
  private let race = Race()
  private let callback = URL(string: "com.example.app://callback?code=one-time-code")!

  init() {
    race.answerSignIn { [race] body in
      race.issue(body.contains("sentinel@example.com") ? "sentinel" : "signed-in")
    }
  }

  @Test
  func oauthSignInURLPersistsTheVerifierBeforeReturning() async throws {
    let client = race.makeClient()

    let (url, flowID) = try await client.oauthSignInURL(.github)

    let record = try #require(try storedFlow(flowID))
    #expect(record.purpose == .signIn)
    #expect(
      queryItem("code_challenge", in: url) == PKCE.live.generateCodeChallenge(record.verifier))
    #expect(queryItem("code_challenge_method", in: url) == "s256")
    #expect(queryItem("provider", in: url) == "github")
  }

  @Test
  func oauthOptionsBuildTheAuthorizeURL() async throws {
    let client = race.makeClient()

    let (url, flowID) = try await client.oauthSignInURL(
      .github,
      options: OAuthOptions(
        scopes: ["repo", "user"],
        redirectTo: URL(string: "com.example.app://login")!,
        queryItems: [URLQueryItem(name: "access_type", value: "offline")]
      )
    )

    #expect(queryItem("scopes", in: url) == "repo user")
    #expect(queryItem("redirect_to", in: url) == "com.example.app://login")
    #expect(queryItem("access_type", in: url) == "offline")
    #expect(try storedFlow(flowID)?.redirectTo == URL(string: "com.example.app://login")!)
  }

  @Test
  func linkIdentityURLStartsALinkIdentityFlow() async throws {
    race.answerIdentityAuthorize(url: URL(string: "https://github.com/login/oauth/authorize")!)
    race.answerCodeExchange { [race] in try Race.ok(race.issue("linked")) }
    let client = race.makeClient()
    try await client.signIn(email: "user@example.com", password: "secret")

    let (url, flowID) = try await client.linkIdentityURL(.github)

    #expect(url == URL(string: "https://github.com/login/oauth/authorize")!)
    #expect(try storedFlow(flowID)?.purpose == .linkIdentity)
    let authorize = try #require(
      race.transport.requests.first { $0.head.url?.path.hasSuffix("/authorize") == true })
    #expect(authorize.head.url?.query?.contains("code_challenge=") == true)

    let events = try await events(on: client) {
      let result = try await client.handleRedirect(callback)
      #expect(describe(result) == "signedIn linked-access verification: nil")
    }
    #expect(events == [.userUpdated])
  }

  @Test
  func duplicateDeliveryExchangesOnce() async throws {
    let gate = Gate()
    let exchanges = LockIsolated(0)
    race.answerCodeExchange(through: gate) { [race] in
      let count = exchanges.withValue {
        $0 += 1
        return $0
      }
      guard count == 1 else {
        return Race.error(.notFound, code: "flow_state_not_found", message: "invalid flow state")
      }
      return try Race.ok(race.issue("exchanged"))
    }
    let client = race.makeClient()
    _ = try await client.oauthSignInURL(.github)
    let callback = callback

    let first = Task { try await client.handleRedirect(callback) }
    await gate.arrivals(1)
    let second = Task { try await client.handleRedirect(callback) }
    gate.open()
    let results = try await [first.value, second.value]
    let later = try await client.handleRedirect(callback)

    #expect(describe(results[0]) == "signedIn exchanged-access verification: nil")
    #expect(results[1] == results[0])
    #expect(later == results[0])
    #expect(race.requestCount(grantType: "pkce") == 1)
  }

  @Test
  func recoveryFlowEmitsPasswordRecovery() async throws {
    race.answer(.post, "recover")
    race.answerCodeExchange { [race] in try Race.ok(race.issue("recovered")) }
    let client = race.makeClient()
    try await client.resetPasswordForEmail("user@example.com")

    let events = try await events(on: client) {
      let result = try await client.handleRedirect(callback)
      #expect(describe(result) == "signedIn recovered-access verification: recovery")
    }

    #expect(events == [.passwordRecovery])
  }

  @Test
  func emailChangeFlowEmitsUserUpdated() async throws {
    race.answerUserUpdate(with: User(fromMockNamed: "user"))
    race.answerCodeExchange { [race] in try Race.ok(race.issue("changed")) }
    let client = race.makeClient()
    try await client.signIn(email: "user@example.com", password: "secret")
    try await client.update(user: UserAttributes(email: "new@example.com"))

    let events = try await events(on: client) {
      let result = try await client.handleRedirect(callback)
      #expect(describe(result) == "signedIn changed-access verification: email_change")
    }

    #expect(events == [.userUpdated])
  }

  @Test
  func implicitRecoveryLinkCommitsOnce() async throws {
    race.answerUser(User(fromMockNamed: "user"))
    let client = race.makeClient()
    let link = URL(
      string: """
        com.example.app://callback#access_token=implicit-access&refresh_token=implicit-refresh\
        &expires_in=3600&token_type=bearer&type=recovery&sb=
        """
    )!

    let events = try await events(on: client) {
      let result = try await client.handleRedirect(link)
      guard case .signedIn(let session, let verification) = result else {
        Issue.record("Expected .signedIn, got \(String(describing: result))")
        return
      }
      #expect(session.accessToken == "implicit-access")
      #expect(verification == .recovery)
      #expect(race.relaunch().currentSession?.accessToken == "implicit-access")
    }

    #expect(events == [.passwordRecovery])
  }

  @Test
  func anExplicitMissingFlowIDThrowsWithoutARequest() async throws {
    let client = race.makeClient()
    _ = try await client.oauthSignInURL(.github)

    await #expect {
      try await client.exchangeCodeForSession("one-time-code", flowID: UUID())
    } throws: { ($0 as? AuthError)?.kind == .oauthFlowFailed }

    #expect(race.requestCount(grantType: "pkce") == 0)
  }

  @Test
  func aCodeWithNoPendingFlowThrowsWithoutARequest() async throws {
    let client = race.makeClient()

    await #expect {
      try await client.handleRedirect(callback)
    } throws: { ($0 as? AuthError)?.kind == .oauthFlowFailed }

    #expect(race.requestCount(grantType: "pkce") == 0)
  }

  @Test
  func sbFlowIDSelectsItsFlow() async throws {
    race.answerCodeExchange { [race] in try Race.ok(race.issue("exchanged")) }
    let client = race.makeClient()
    let a = try await client.oauthSignInURL(.github).flowID
    let b = try await client.oauthSignInURL(.google).flowID
    let verifierA = try #require(try storedFlow(a)).verifier

    try await client.handleRedirect(
      URL(string: "com.example.app://callback?code=one-time-code&sb_flow_id=\(a.uuidString)")!)

    #expect(exchangeBodies() == [exchangeBody(verifier: verifierA)])
    #expect(try storedFlow(a) == nil)
    #expect(try storedFlow(b) != nil)
  }

  @Test
  func theNewestFlowIsUsedWithoutAnID() async throws {
    race.answerCodeExchange { [race] in try Race.ok(race.issue("exchanged")) }
    let client = race.makeClient()
    let a = try await client.oauthSignInURL(.github).flowID
    let b = try await client.oauthSignInURL(.google).flowID
    let verifierB = try #require(try storedFlow(b)).verifier

    try await client.handleRedirect(callback)

    #expect(exchangeBodies() == [exchangeBody(verifier: verifierB)])
    #expect(try storedFlow(a) != nil)
    #expect(try storedFlow(b) == nil)
  }

  @Test
  func aRejectedExchangeRemovesTheFlow() async throws {
    race.answerCodeExchange {
      Race.error(.badRequest, code: "flow_state_not_found", message: "invalid flow state")
    }
    let client = race.makeClient()
    let flowID = try await client.oauthSignInURL(.github).flowID

    await #expect {
      try await client.exchangeCodeForSession("one-time-code", flowID: flowID)
    } throws: { ($0 as? AuthError)?.errorCode == .flowStateNotFound }

    #expect(try storedFlow(flowID) == nil)
    #expect(try await client.dependencies.flowStore.newest() == nil)
  }

  @Test
  func aTransportErrorKeepsTheFlow() async throws {
    let attempts = LockIsolated(0)
    race.answerCodeExchange { [race] in
      let attempt = attempts.withValue {
        $0 += 1
        return $0
      }
      guard attempt > 1 else { throw URLError(.timedOut) }
      return try Race.ok(race.issue("exchanged"))
    }
    let client = race.makeClient()
    let flowID = try await client.oauthSignInURL(.github).flowID

    await #expect {
      try await client.exchangeCodeForSession("one-time-code", flowID: flowID)
    } throws: { ($0 as? AuthError)?.kind == .transport }
    #expect(try storedFlow(flowID) != nil)

    let session = try await client.exchangeCodeForSession("one-time-code", flowID: flowID)

    #expect(session.accessToken == "exchanged-access")
    #expect(race.requestCount(grantType: "pkce") == 2)
    #expect(try storedFlow(flowID) == nil)
  }

  @Test
  func anUnrelatedURLReturnsNilWithoutARequest() async throws {
    let client = race.makeClient()
    let unrelated = URL(string: "com.example.app://settings?tab=profile")!

    let result = try await client.handleRedirect(unrelated)

    #expect(result == nil)
    #expect(race.transport.requests.isEmpty)
    #expect(client.isAuthRedirect(unrelated) == false)
    #expect(client.isAuthRedirect(URL(string: "com.example.app://callback?code=x")!))
  }

  @Test
  func anErrorRedirectThrowsItsError() async throws {
    let client = race.makeClient()
    let url = URL(
      string: "com.example.app://callback?error=access_denied&error_code=otp_expired")!

    await #expect {
      try await client.handleRedirect(url)
    } throws: { ($0 as? AuthError)?.errorCode == .otpExpired }
  }

  @Test
  func emailChangePendingCommitsNothing() async throws {
    let client = race.makeClient()
    try await client.signIn(email: "user@example.com", password: "secret")
    let before = client.currentSession
    let url = URL(
      string: "com.example.app://callback#message=Confirm+the+link+sent+to+the+other+email")!

    let events = try await events(on: client) {
      let result = try await client.handleRedirect(url)
      #expect(result == .emailChangePending(message: "Confirm the link sent to the other email"))
      #expect(client.currentSession == before)
    }

    #expect(events.isEmpty)
  }

  @Test
  func everyPKCECallSendsAChallenge() async throws {
    race.answer(.post, "signup") { try Race.ok(User(fromMockNamed: "user")) }
    race.answer(.post, "otp")
    race.answer(.post, "resend")
    race.answer(.post, "recover")
    race.answerUserUpdate(with: User(fromMockNamed: "user"))
    let client = race.makeClient()
    try await client.signIn(email: "user@example.com", password: "secret")

    let calls: [(name: String, call: () async throws -> Void)] = [
      ("signUp", { _ = try await client.signUp(email: "a@example.com", password: "secret") }),
      ("signInWithOTP", { try await client.signInWithOTP(email: "a@example.com") }),
      ("resend", { try await client.resend(email: "a@example.com", type: .signup) }),
      ("resetPasswordForEmail", { try await client.resetPasswordForEmail("a@example.com") }),
      ("update", { try await client.update(user: UserAttributes(email: "b@example.com")) }),
    ]

    for (index, (name, call)) in calls.enumerated() {
      try await call()

      let body = race.transport.requests.last?.body.map { String(decoding: $0, as: UTF8.self) }
      #expect(body?.contains("\"code_challenge\"") == true, "\(name)")
      #expect(try pendingFlowCount() == index + 1, "\(name)")
    }
  }

  @Test
  func aRejectedStartingRequestRemovesItsFlow() async throws {
    race.answer(.post, "otp") {
      Race.error(
        .tooManyRequests, code: "over_email_send_rate_limit", message: "email rate limit exceeded")
    }
    race.answerCodeExchange { [race] in try Race.ok(race.issue("exchanged")) }
    let client = race.makeClient()
    let previous = try await client.oauthSignInURL(.github).flowID
    let previousVerifier = try #require(try storedFlow(previous)).verifier

    await #expect {
      try await client.signInWithOTP(email: "user@example.com")
    } throws: { ($0 as? AuthError)?.errorCode == .overEmailSendRateLimit }
    #expect(try pendingFlowCount() == 1)

    try await client.handleRedirect(callback)

    #expect(exchangeBodies() == [exchangeBody(verifier: previousVerifier)])
  }

  @Test
  func aTransportErrorOnTheStartingRequestKeepsItsFlow() async throws {
    race.answer(.post, "otp") { throw URLError(.timedOut) }
    let client = race.makeClient()

    await #expect {
      try await client.signInWithOTP(email: "user@example.com")
    } throws: { ($0 as? AuthError)?.kind == .transport }

    #expect(try pendingFlowCount() == 1)
  }

  @Test
  func linkIdentityURLWithoutASessionLeavesNoFlow() async throws {
    let client = race.makeClient()

    await #expect {
      try await client.linkIdentityURL(.github)
    } throws: { ($0 as? AuthError)?.kind == .sessionMissing }

    #expect(try pendingFlowCount() == 0)
    #expect(race.transport.requests.isEmpty)
  }

  @Test
  func resendPicksThePurposeFromTheType() async throws {
    race.answer(.post, "resend")
    let client = race.makeClient()

    try await client.resend(email: "a@example.com", type: .emailChange)
    #expect(try await client.dependencies.flowStore.newest()?.purpose == .emailChange)

    try await client.resend(email: "a@example.com", type: .signup)
    #expect(try await client.dependencies.flowStore.newest()?.purpose == .signIn)
  }

  // MARK: - Helpers

  /// Names the session by its access token, so the check does not depend on how the other
  /// session fields survive the JSON round trip through the stub.
  private func describe(_ result: RedirectResult?) -> String {
    switch result {
    case .signedIn(let session, let verification):
      "signedIn \(session.accessToken) verification: \(verification?.rawValue ?? "nil")"
    case .emailChangePending(let message): "emailChangePending \(message)"
    case nil: "nil"
    }
  }

  private func storedFlow(_ id: UUID) throws -> PendingFlowRecord? {
    try race.localStorage
      .retrieve(key: PendingFlowRecord.key(id: id, storageKey: race.storageKey))
      .map(PendingFlowRecord.decode)
  }

  private func pendingFlowCount() throws -> Int {
    try race.localStorage
      .retrieve(key: PendingFlowIndex.key(storageKey: race.storageKey))
      .map(PendingFlowIndex.decode)?.flows.count ?? 0
  }

  private func queryItem(_ name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == name }?.value
  }

  private func exchangeBodies() -> [[String: String]] {
    race.transport.requests
      .filter { $0.head.url?.query?.contains("grant_type=pkce") == true }
      .compactMap { request in
        request.body.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
      }
  }

  private func exchangeBody(verifier: String) -> [String: String] {
    ["auth_code": "one-time-code", "code_verifier": verifier]
  }

  /// The events `action` emits. A password sign-in after it marks the end of the list, so a
  /// missing or an extra event shows.
  private func events(
    on client: AuthClient,
    during action: () async throws -> Void
  ) async throws -> [AuthChangeEvent] {
    let stream = client.authStateChanges
    try await action()
    try await client.signIn(email: "sentinel@example.com", password: "secret")

    var events: [AuthChangeEvent] = []
    for await change in stream.dropFirst() {
      if change.event == .signedIn, change.session?.accessToken == "sentinel-access" {
        break
      }
      events.append(change.event)
    }
    return events
  }
}

extension Race {
  /// Answers `method /<path>` with `response`, an empty JSON object by default.
  fileprivate func answer(
    _ method: HTTPTypes.HTTPRequest.Method,
    _ path: String,
    with response: @escaping @Sendable () throws -> (HTTPResponse, Data) = {
      try Race.ok([String: String]())
    }
  ) {
    transport.respond(when: {
      $0.method == method && $0.url?.path.hasSuffix("/\(path)") == true
    }) { _, _ in try response() }
  }
}
