import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Auth

/// The contract of the event taxonomy: every operation of the auth v3 design (Appendix B) against
/// the events it emits and the status it leaves, each on its own client, storage, clock, and
/// transport.
@Suite(.timeLimit(.minutes(1)))
struct AuthEventMatrixTests {
  @Test(arguments: Row.launches)
  func launchEmitsItsEventsAndLeavesItsStatus(_ row: Row) async throws {
    try await row.verify()
  }

  @Test(arguments: Row.signUpsAndSignIns)
  func signingUpOrInEmitsItsEventsAndLeavesItsStatus(_ row: Row) async throws {
    try await row.verify()
  }

  @Test(arguments: Row.verifications)
  func verifyingACodeOrARedirectEmitsItsEventsAndLeavesItsStatus(_ row: Row) async throws {
    try await row.verify()
  }

  @Test(arguments: Row.refreshes)
  func refreshingEmitsItsEventsAndLeavesItsStatus(_ row: Row) async throws {
    try await row.verify()
  }

  @Test(arguments: Row.changesToTheSignedInUser)
  func changingTheSignedInUserEmitsItsEventsAndLeavesItsStatus(_ row: Row) async throws {
    try await row.verify()
  }

  @Test(arguments: Row.signOutsAndRevocations)
  func signingOutOrLosingTheSessionEmitsItsEventsAndLeavesItsStatus(_ row: Row) async throws {
    try await row.verify()
  }

  /// One row of Appendix B.
  struct Row: Sendable, CustomTestStringConvertible {
    /// What the status is after the operation.
    enum Status: Sendable {
      case signedIn
      case signedInAs(String)
      case signedInExpired
      case signedOut(SignOutReason)
      case loading
      case unchanged
    }

    /// The state the client is in before the operation.
    enum Starting: Sendable {
      case signedOut
      case signedIn
      case expired
    }

    /// What a run saw.
    struct Observation: Sendable {
      var events: [AuthEvent]
      var statusBefore: AuthStatus
      var statusAfter: AuthStatus
      var now: Date
    }

    let name: String
    let events: [AuthEvent]
    let status: Status
    let run: @Sendable (Race) async throws -> Observation

    var testDescription: String { name }

    func verify() async throws {
      let observation = try await run(Race())

      #expect(observation.events == events)
      switch status {
      case .signedIn:
        guard case .signedIn(let session) = observation.statusAfter else {
          Issue.record("Expected a signed-in status, got \(observation.statusAfter)")
          return
        }
        #expect(!session.isExpired(at: observation.now))
      case .signedInAs(let name):
        guard case .signedIn(let session) = observation.statusAfter else {
          Issue.record("Expected a signed-in status, got \(observation.statusAfter)")
          return
        }
        #expect(session.accessToken == "\(name)-access")
        #expect(!session.isExpired(at: observation.now))
      case .signedInExpired:
        guard case .signedIn(let session) = observation.statusAfter else {
          Issue.record("Expected a signed-in status, got \(observation.statusAfter)")
          return
        }
        #expect(session.isExpired(at: observation.now))
      case .signedOut(let reason):
        #expect(observation.statusAfter == .signedOut(reason))
      case .loading:
        #expect(observation.statusAfter == .loading)
      case .unchanged:
        #expect(observation.statusAfter == observation.statusBefore)
      }
    }

    /// A row for an operation on a client that already launched.
    static func operation(
      _ name: String,
      starting: Starting = .signedOut,
      autoRefresh: AuthClient.AutoRefreshPolicy = .manual,
      emits events: [AuthEvent],
      leaves status: Status,
      _ act: @escaping @Sendable (_ world: Race, _ client: AuthClient) async throws -> Void
    ) -> Row {
      Row(name: name, events: events, status: status) { world in
        let client = world.makeClient(autoRefresh: autoRefresh)
        switch starting {
        case .signedOut: break
        case .signedIn: try await client.seedSession(world.issue("held"))
        case .expired: try await client.seedSession(Self.expiredSession(world))
        }
        await client.initialization()

        let changes = client.events()
        let before = client.status
        try await act(world, client)
        client.dependencies.sessionStore.finishChanges()
        let received = await changes.collect()

        return Observation(
          events: received.dropFirst().map(\.event),
          statusBefore: before,
          statusAfter: client.status,
          now: world.now())
      }
    }

    /// A session the device clock already considers expired, with a refresh token the server knows.
    static func expiredSession(_ world: Race) -> Session {
      var session = world.issue("held", lifetime: 60)
      session.expiresAt = world.now().addingTimeInterval(-60)
      session.receivedAt = world.now().addingTimeInterval(-120)
      return session
    }
  }
}

// MARK: - Launch

extension AuthEventMatrixTests.Row {
  /// How a client launched with `stored` in storage reads it, as the rows of "Client init".
  private static func launch(
    _ name: String,
    stored: @escaping @Sendable (Race) -> Session?,
    server: @escaping @Sendable (Race) -> Void = { _ in },
    emits events: [AuthEvent],
    leaves status: Status
  ) -> Self {
    Self(name: name, events: events, status: status) { world in
      server(world)
      let storage = LockedLocalStorage()
      if let session = stored(world) {
        try storage.store(
          key: world.storageKey, value: PersistedSessionCodec.encode(session))
      }
      let client = world.makeClient(autoRefresh: .automatic, storage: storage)
      var changes = client.events().makeAsyncIterator()

      let launched = await changes.next()
      client.dependencies.sessionStore.finishChanges()
      var rest: [AuthEvent] = []
      while let change = await changes.next() { rest.append(change.event) }
      return Observation(
        events: [launched?.event].compactMap { $0 } + rest,
        statusBefore: .loading,
        statusAfter: client.status,
        now: world.now())
    }
  }

  static let launches: [Self] = [
    launch(
      "Client init, stored valid session",
      stored: { $0.issue("stored") },
      emits: [.initialSession], leaves: .signedInAs("stored")),

    launch(
      "Client init, stored expired session, refresh succeeds",
      stored: { expiredSession($0) },
      server: { world in
        world.answerRefresh { try Race.ok(world.issue("refreshed")) }
      },
      emits: [.initialSession], leaves: .signedInAs("refreshed")),

    offlineLaunch,

    launch(
      "Client init, stored expired session, terminal rejection",
      stored: { expiredSession($0) },
      server: { world in
        world.answerRefresh {
          Race.error(.badRequest, code: "refresh_token_not_found", message: "gone")
        }
      },
      emits: [.initialSession], leaves: .signedOut(.sessionExpired)),

    launch(
      "Client init, nothing stored",
      stored: { _ in nil },
      emits: [.initialSession], leaves: .signedOut(.sessionMissing)),

    lockedLaunch,
  ]

  /// The refresh request fails to connect, so the expired session is delivered after the retry.
  private static let offlineLaunch = Self(
    name: "Client init, stored expired session, offline",
    events: [.initialSession], status: .signedInExpired
  ) { world in
    world.transport.respond { _, _ in throw URLError(.notConnectedToInternet) }
    let storage = InMemoryTestStorage()
    try storage.store(
      key: world.storageKey, value: PersistedSessionCodec.encode(expiredSession(world)))
    let client = world.makeClient(autoRefresh: .automatic, storage: storage)
    var changes = client.events().makeAsyncIterator()

    // The launch deadline and the retry of the failed refresh both sleep on the client's clock.
    #expect(await waitUntil { world.clock.pendingSleepCount >= 2 })
    await world.clock.advance(by: .seconds(2))
    let launched = await changes.next()
    client.dependencies.sessionStore.finishChanges()
    var rest: [AuthEvent] = []
    while let change = await changes.next() { rest.append(change.event) }
    return Observation(
      events: [launched?.event].compactMap { $0 } + rest,
      statusBefore: .loading,
      statusAfter: client.status,
      now: world.now())
  }

  /// Storage is locked at launch: nothing is emitted and the status stays `.loading` until the
  /// protected data becomes readable, when the one `.initialSession` arrives.
  private static let lockedLaunch = Self(
    name: "Client init, Keychain locked",
    events: [], status: .loading
  ) { world in
    let storage = LockedLocalStorage()
    try storage.store(
      key: world.storageKey, value: PersistedSessionCodec.encode(world.issue("stored")))
    storage.isLocked.setValue(true)
    let (lifecycle, lifecycleEvents) = AsyncStream.makeStream(of: AppLifecycleEvent.self)
    let client = world.makeClient(storage: storage, lifecycleEvents: { lifecycle })
    var changes = client.dependencies.sessionStore.changes().makeAsyncIterator()

    #expect(await waitUntil { storage.failedReads.value >= 1 })
    let statusWhileLocked = client.status

    storage.isLocked.setValue(false)
    lifecycleEvents.yield(.protectedDataDidBecomeAvailable)
    let launched = await changes.next()
    #expect(launched?.event == .initialSession)
    client.dependencies.sessionStore.finishChanges()
    var rest: [AuthEvent] = []
    while let change = await changes.next() { rest.append(change.event) }
    return Observation(
      events: [launched?.event].compactMap { $0 }.filter { $0 != .initialSession } + rest,
      statusBefore: .loading,
      statusAfter: statusWhileLocked,
      now: world.now())
  }
}

// MARK: - Sign-up and sign-in

extension AuthEventMatrixTests.Row {
  private static func answer(
    _ world: Race, _ method: HTTPRequest.Method, _ path: String,
    grant: String? = nil, with session: Session
  ) {
    world.transport.stub(method, path, query: grant.map { ["grant_type": $0] } ?? [:]) { _, _ in
      try Race.ok(session)
    }
  }

  static let signUpsAndSignIns: [Self] = [
    operation("signUp, auto-confirmed", emits: [.signedIn], leaves: .signedInAs("signed-up")) {
      world, client in
      answer(world, .post, "signup", with: world.issue("signed-up"))
      let result = try await client.signUp(email: "user@example.com", password: "secret")
      guard case .signedIn = result else {
        Issue.record("Expected a session, got \(result)")
        return
      }
    },

    operation("signUp, confirmation required", emits: [], leaves: .unchanged) { world, client in
      world.transport.stub(.post, "signup", data: MockData.signUpConfirmationRequired)
      let result = try await client.signUp(email: "user@example.com", password: "secret")
      guard case .confirmationRequired = result else {
        Issue.record("Expected a pending confirmation, got \(result)")
        return
      }
    },

    operation("signIn(email:password:)", emits: [.signedIn], leaves: .signedInAs("password")) {
      world, client in
      answer(world, .post, "token", grant: "password", with: world.issue("password"))
      try await client.signIn(email: "user@example.com", password: "secret")
    },

    operation("signIn(phone:password:)", emits: [.signedIn], leaves: .signedInAs("password")) {
      world, client in
      answer(world, .post, "token", grant: "password", with: world.issue("password"))
      try await client.signIn(phone: "+15555550100", password: "secret")
    },

    operation("signInAnonymously", emits: [.signedIn], leaves: .signedInAs("anonymous")) {
      world, client in
      answer(world, .post, "signup", with: world.issue("anonymous"))
      try await client.signInAnonymously()
    },

    operation("signInWithIDToken", emits: [.signedIn], leaves: .signedInAs("id-token")) {
      world, client in
      answer(world, .post, "token", grant: "id_token", with: world.issue("id-token"))
      try await client.signInWithIDToken(IDTokenCredentials(provider: .apple, idToken: "token"))
    },

    operation("signInWithWeb3", emits: [.signedIn], leaves: .signedInAs("web3")) { world, client in
      answer(world, .post, "token", grant: "web3", with: world.issue("web3"))
      try await client.signInWithWeb3(
        Web3Credentials(chain: .solana, message: "message", signature: "signature"))
    },

    operation(
      "signInWithOAuth, finished by exchangeCodeForSession", emits: [.signedIn],
      leaves: .signedInAs("oauth")
    ) {
      world, client in
      answer(world, .post, "token", grant: "pkce", with: world.issue("oauth"))
      let flow = try await client.oauthSignInURL(.github)
      _ = try await client.exchangeCodeForSession("one-time-code", flowID: flow.id)
    },

    operation(
      "signInWithSSO, finished by exchangeCodeForSession", emits: [.signedIn],
      leaves: .signedInAs("sso")
    ) {
      world, client in
      world.transport.stub(.post, "sso") { _, _ in
        try Race.ok(["url": URL(string: "https://idp.example.com/sso")!])
      }
      answer(world, .post, "token", grant: "pkce", with: world.issue("sso"))
      let flow = try await client.ssoSignInURL(.domain("example.com"))
      _ = try await client.exchangeCodeForSession("one-time-code", flowID: flow.id)
    },

    operation(
      "signInWithOAuth with a presenter", emits: [.signedIn], leaves: .signedInAs("presented")
    ) {
      world, client in
      answer(world, .post, "token", grant: "pkce", with: world.issue("presented"))
      let presenter = ClosurePresenter { _, _ in URL(string: "\(callback)?code=one-time-code")! }
      try await client.signInWithOAuth(.github, presenter: presenter)
    },

    operation(
      "signInWithSSO with a presenter", emits: [.signedIn], leaves: .signedInAs("presented")
    ) {
      world, client in
      world.transport.stub(.post, "sso") { _, _ in
        try Race.ok(["url": URL(string: "https://idp.example.com/sso")!])
      }
      answer(world, .post, "token", grant: "pkce", with: world.issue("presented"))
      let presenter = ClosurePresenter { _, _ in URL(string: "\(callback)?code=one-time-code")! }
      try await client.signInWithSSO(.domain("example.com"), presenter: presenter)
    },

    operation("exchangeCodeForSession", emits: [.signedIn], leaves: .signedInAs("exchanged")) {
      world, client in
      answer(world, .post, "token", grant: "pkce", with: world.issue("exchanged"))
      _ = try await client.oauthSignInURL(.github)
      _ = try await client.exchangeCodeForSession("one-time-code")
    },

    operation(
      "signUp while signed in replaces the session", starting: .signedIn, emits: [.signedIn],
      leaves: .signedInAs("signed-up")
    ) {
      world, client in
      answer(world, .post, "signup", with: world.issue("signed-up"))
      _ = try await client.signUp(email: "new@example.com", password: "secret")
    },
  ]
}

// MARK: - Verification and redirects

extension AuthEventMatrixTests.Row {
  static let callback = "com.example.app://callback"

  private static func implicitRedirect(type: String?, world: Race) -> URL {
    let session = world.issue("redirected")
    var items = [
      "access_token=\(session.accessToken)", "refresh_token=\(session.refreshToken)",
      "token_type=bearer", "expires_in=3600",
    ]
    if let type { items.append("type=\(type)") }
    return URL(string: "\(callback)#\(items.joined(separator: "&"))")!
  }

  static let verifications: [Self] = [
    operation(
      "verifyOTP(type: .recovery)", emits: [.passwordRecovery], leaves: .signedInAs("recovery")
    ) {
      world, client in
      world.transport.stub(.post, "verify") { _, _ in try Race.ok(world.issue("recovery")) }
      try await client.verifyOTP(email: "user@example.com", token: "123456", type: .recovery)
    },

    operation(
      "verifyOTP(type: .emailChange), session", starting: .signedIn, emits: [.userUpdated],
      leaves: .signedInAs("changed")
    ) {
      world, client in
      world.transport.stub(.post, "verify") { _, _ in try Race.ok(world.issue("changed")) }
      try await client.verifyOTP(tokenHash: "hash", type: .emailChange)
    },

    operation(
      "verifyOTP(type: .phoneChange), session", starting: .signedIn, emits: [.userUpdated],
      leaves: .signedInAs("changed")
    ) {
      world, client in
      world.transport.stub(.post, "verify") { _, _ in try Race.ok(world.issue("changed")) }
      try await client.verifyOTP(phone: "+15555550100", token: "123456", type: .phoneChange)
    },

    operation(
      "verifyOTP(type: .emailChange), first half", starting: .signedIn, emits: [],
      leaves: .unchanged
    ) {
      world, client in
      world.transport.stub(.post, "verify", data: MockData.emailChangeSingleConfirmation)
      let result = try await client.verifyOTP(tokenHash: "hash", type: .emailChange)
      guard case .emailChangePending = result else {
        Issue.record("Expected a pending change, got \(result)")
        return
      }
    },

    operation("verifyOTP(email:), other type", emits: [.signedIn], leaves: .signedInAs("verified"))
    {
      world, client in
      world.transport.stub(.post, "verify") { _, _ in try Race.ok(world.issue("verified")) }
      try await client.verifyOTP(email: "user@example.com", token: "123456", type: .email)
    },

    operation("verifyOTP(phone:), other type", emits: [.signedIn], leaves: .signedInAs("verified"))
    {
      world, client in
      world.transport.stub(.post, "verify") { _, _ in try Race.ok(world.issue("verified")) }
      try await client.verifyOTP(phone: "+15555550100", token: "123456", type: .sms)
    },

    operation(
      "verifyOTP(tokenHash:), other type", emits: [.signedIn], leaves: .signedInAs("verified")
    ) {
      world, client in
      world.transport.stub(.post, "verify") { _, _ in try Race.ok(world.issue("verified")) }
      try await client.verifyOTP(tokenHash: "hash", type: .magiclink)
    },

    operation(
      "handleRedirect with type=recovery", emits: [.passwordRecovery],
      leaves: .signedInAs("redirected")
    ) {
      world, client in
      world.answerUser(world.issue("redirected").user)
      _ = try await client.handleRedirect(implicitRedirect(type: "recovery", world: world))
    },

    operation(
      "handleRedirect with a recovery flow", emits: [.passwordRecovery],
      leaves: .signedInAs("recovery")
    ) {
      world, client in
      world.transport.stub(.post, "recover") { _, _ in (HTTPResponse(status: .ok), Data("{}".utf8))
      }
      world.answerCodeExchange { try Race.ok(world.issue("recovery")) }
      try await client.resetPassword(email: "user@example.com")
      _ = try await client.handleRedirect(URL(string: "\(callback)?code=one-time-code")!)
    },

    operation(
      "handleRedirect, other redirect", emits: [.signedIn], leaves: .signedInAs("redirected")
    ) {
      world, client in
      world.answerUser(world.issue("redirected").user)
      _ = try await client.handleRedirect(implicitRedirect(type: nil, world: world))
    },

    operation(
      "handleRedirect, other redirect with a code", emits: [.signedIn], leaves: .signedInAs("coded")
    ) {
      world, client in
      world.answerCodeExchange { try Race.ok(world.issue("coded")) }
      _ = try await client.oauthSignInURL(.github)
      _ = try await client.handleRedirect(URL(string: "\(callback)?code=one-time-code")!)
    },

    operation("importSession", emits: [.signedIn], leaves: .signedIn) {
      world, client in
      world.answerUser(world.issue("imported").user)
      try await client.importSession(accessToken: unexpiredAccessToken, refreshToken: "refresh")
    },

    operation(
      "importSession, refreshed, still one event", emits: [.signedIn],
      leaves: .signedInAs("imported")
    ) {
      world, client in
      world.answerRefresh { try Race.ok(world.issue("imported")) }
      try await client.importSession(accessToken: expiredAccessToken, refreshToken: "refresh")
    },
  ]
}

// MARK: - Refresh

extension AuthEventMatrixTests.Row {
  static let refreshes: [Self] = [
    operation(
      "lazy refresh succeeds", starting: .expired, emits: [.tokenRefreshed],
      leaves: .signedInAs("refreshed")
    ) {
      world, client in
      world.answerRefresh { try Race.ok(world.issue("refreshed")) }
      _ = try await client.session()
    },

    operation(
      "refreshSession succeeds", starting: .signedIn, emits: [.tokenRefreshed],
      leaves: .signedInAs("refreshed")
    ) {
      world, client in
      world.answerRefresh { try Race.ok(world.issue("refreshed")) }
      _ = try await client.refreshSession()
    },

    operation(
      "scheduled refresh succeeds", starting: .signedIn, autoRefresh: .automatic,
      emits: [.tokenRefreshed], leaves: .signedInAs("refreshed")
    ) { world, client in
      world.answerRefresh { try Race.ok(world.issue("refreshed")) }
      #expect(await waitUntil { await client.dependencies.autoRefresh.isRegistered })
      await world.waitForTheScheduledRefresh()
      await world.advance(to: Race.lifetime - Refresher.refreshLeadTime.timeInterval)
      #expect(
        await waitUntil { client.currentSession?.accessToken == "refreshed-access" })
    },

    operation("refresh fails, retryable", starting: .signedIn, emits: [], leaves: .unchanged) {
      world, client in
      world.answerRefresh { (HTTPResponse(status: .serviceUnavailable), Data()) }
      await #expect(throws: AuthError.self) { try await client.refreshSession() }
    },

    operation(
      "refresh fails, terminal, token still valid", starting: .signedIn, emits: [],
      leaves: .unchanged
    ) {
      world, client in
      world.answerRefresh {
        Race.error(.badRequest, code: "refresh_token_not_found", message: "gone")
      }
      await #expect(throws: AuthError.self) { try await client.refreshSession() }
    },

    operation(
      "refresh fails, terminal, token expired (session_expired)", starting: .expired,
      emits: [.signedOut], leaves: .signedOut(.sessionExpired)
    ) { world, client in
      world.answerRefresh {
        Race.error(.badRequest, code: "refresh_token_not_found", message: "gone")
      }
      await #expect(throws: AuthError.self) { try await client.refreshSession() }
    },

    operation(
      "refresh fails, terminal, token expired (session revoked)", starting: .expired,
      emits: [.signedOut], leaves: .signedOut(.sessionRevoked)
    ) { world, client in
      world.answerRefresh {
        Race.error(.badRequest, code: "refresh_token_already_used", message: "used")
      }
      await #expect(throws: AuthError.self) { try await client.refreshSession() }
    },
  ]
}

// MARK: - Changes to the signed-in user

extension AuthEventMatrixTests.Row {
  static let changesToTheSignedInUser: [Self] = [
    operation("updateUser", starting: .signedIn, emits: [.userUpdated], leaves: .signedIn) {
      world, client in
      world.answerUserUpdate(with: Race.user(nickname: "new"))
      _ = try await client.updateUser(UpdateUser(userMetadata: ["nickname": "new"]))
    },

    operation(
      "linkIdentity(idToken:)", starting: .signedIn, emits: [.userUpdated],
      leaves: .signedInAs("linked")
    ) {
      world, client in
      world.transport.stub(.post, "token", query: ["grant_type": "id_token"]) { _, _ in
        try Race.ok(world.issue("linked"))
      }
      try await client.linkIdentity(idToken: IDTokenCredentials(provider: .apple, idToken: "token"))
    },

    operation("unlinkIdentity", starting: .signedIn, emits: [.userUpdated], leaves: .signedIn) {
      world, client in
      let identity = try #require(client.currentUser?.identities?.first)
      world.transport.stub(
        .delete, "user/identities/\(identity.id.uuidString)", data: Data("{}".utf8))
      try await client.unlinkIdentity(identity)
    },

    operation(
      "linkIdentity via OAuth", starting: .signedIn, emits: [.userUpdated],
      leaves: .signedInAs("linked")
    ) {
      world, client in
      world.answerIdentityAuthorize(url: URL(string: "https://github.com/login/oauth/authorize")!)
      world.answerCodeExchange { try Race.ok(world.issue("linked")) }
      _ = try await client.linkIdentityURL(.github)
      _ = try await client.handleRedirect(URL(string: "\(callback)?code=one-time-code")!)
    },

    operation(
      "mfa.verify", starting: .signedIn, emits: [.mfaChallengeVerified], leaves: .signedInAs("aal2")
    ) {
      world, client in
      let factorID = UUID()
      world.transport.stub(.post, "factors/\(factorID.uuidString)/verify") { _, _ in
        try Race.ok(world.issue("aal2"))
      }
      try await client.mfa.verify(factorID: factorID, challengeID: UUID(), code: "123456")
    },

    operation(
      "recoveryCodes.verify", starting: .signedIn, emits: [.mfaChallengeVerified],
      leaves: .signedInAs("aal2")
    ) {
      world, client in
      world.transport.stub(.post, "factors/recovery-codes/verify") { _, _ in
        try Race.ok(world.issue("aal2"))
      }
      try await client.mfa.recoveryCodes.verify(code: "abcd-1234")
    },
  ]

}

// MARK: - Sign-out and revocation

extension AuthEventMatrixTests.Row {
  static let signOutsAndRevocations: [Self] = [
    operation(
      "signOut(.global)", starting: .signedIn, emits: [.signedOut],
      leaves: .signedOut(.userInitiated)
    ) {
      world, client in
      world.answerSignOut()
      try await client.signOut(scope: .global)
    },

    operation(
      "signOut(.local)", starting: .signedIn, emits: [.signedOut],
      leaves: .signedOut(.userInitiated)
    ) {
      world, client in
      world.answerSignOut()
      try await client.signOut(scope: .local)
    },

    operation("signOut(.others)", starting: .signedIn, emits: [], leaves: .unchanged) {
      world, client in
      world.answerSignOut()
      try await client.signOut(scope: .others)
    },

    operation(
      "session_not_found on an authorized call", starting: .signedIn, emits: [.signedOut],
      leaves: .signedOut(.sessionRevoked)
    ) { world, client in
      world.transport.stub(.get, "user") { _, _ in
        Race.error(.forbidden, code: "session_not_found", message: "Session not found")
      }
      await #expect(throws: AuthError.self) { try await client.user() }
    },
  ]
}
