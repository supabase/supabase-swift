import ConcurrencyExtras
import CustomDump
import Foundation
import HTTPTypes
import TestHelpers
import Testing

@testable import Auth

/// The one bounded refresh of an expired stored session that runs before `.initialSession`.
@Suite
struct StartupRefreshTests {
  private static let now = Date(timeIntervalSince1970: 1_800_000_000)

  private let key = uniqueStorageKey()
  private let clock = SignalingTestClock()
  private let http = RecordingTransport()
  private let localStorage = InMemoryTestStorage()

  @Test
  func refreshesAnExpiredSessionBeforeDeliveringInitialSession() async throws {
    http.respond { _, _ in Self.refreshResponse }
    try storeExpiredSession()

    let client = makeClient()
    #expect(client.status == .loading)
    var events = client.events().makeAsyncIterator()

    let first = await events.next()
    expectNoDifference(first, AuthChange(event: .initialSession, status: .signedIn(Self.refreshed)))
    #expect(http.requests.count == 1)

    try await client.seedSession(.valid)
    #expect(await events.next()?.event == .signedIn)
  }

  @Test
  func persistsTheRefreshedSession() async throws {
    http.respond { _, _ in Self.refreshResponse }
    try storeExpiredSession()

    let client = makeClient()
    await client.initialization()

    let stored = try #require(try localStorage.retrieve(key: key))
    expectNoDifference(try PersistedSessionCodec.decode(stored).session, Self.refreshed)
  }

  @Test
  func deliversTheExpiredSessionWhenTheRefreshFailsToConnect() async throws {
    http.respond { _, _ in throw URLError(.notConnectedToInternet) }
    try storeExpiredSession()

    let client = makeClient()
    var events = client.events().makeAsyncIterator()

    // The refresh request retries a network failure on the client's clock, within the deadline.
    await clock.advance(by: .seconds(2))

    let first = await events.next()
    expectNoDifference(first, AuthChange(event: .initialSession, status: .signedIn(Self.expired)))
  }

  @Test
  func deliversTheExpiredSessionWhenTheServerAnswersWithAnError() async throws {
    http.respond { _, _ in (HTTPResponse(status: .serviceUnavailable), Data("<html></html>".utf8)) }
    try storeExpiredSession()

    let client = makeClient()
    var events = client.events().makeAsyncIterator()

    let first = await events.next()
    expectNoDifference(first, AuthChange(event: .initialSession, status: .signedIn(Self.expired)))
  }

  @Test(
    arguments: [
      ("refresh_token_not_found", SignOutReason.sessionExpired),
      ("refresh_token_already_used", SignOutReason.sessionRevoked),
    ])
  func deliversASignedOutInitialSessionWhenTheServerRejectsTheRefreshToken(
    errorCode: String, reason: SignOutReason
  ) async throws {
    http.respond { _, _ in errorResponse(.badRequest, errorCode) }
    try storeExpiredSession()

    let client = makeClient()
    var events = client.events().makeAsyncIterator()

    let first = await events.next()
    expectNoDifference(first, AuthChange(event: .initialSession, status: .signedOut(reason)))
    #expect(try localStorage.retrieve(key: key) == nil)

    try await client.seedSession(.valid)
    #expect(await events.next()?.event == .signedIn)
  }

  @Test
  func deliversTheExpiredSessionAfterTheTimeoutAndCommitsALateRefreshAsTokenRefreshed()
    async throws
  {
    let gate = Gate()
    http.respond { _, _ in
      await gate.pass()
      return Self.refreshResponse
    }
    try storeExpiredSession()

    let client = makeClient()
    var events = client.events().makeAsyncIterator()
    await gate.arrivals(1)
    #expect(client.status == .loading)

    await clock.advance(by: .seconds(5))
    let first = await events.next()
    expectNoDifference(first, AuthChange(event: .initialSession, status: .signedIn(Self.expired)))

    gate.open()
    let second = await events.next()
    expectNoDifference(
      second, AuthChange(event: .tokenRefreshed, status: .signedIn(Self.refreshed)))
    #expect(http.requests.count == 1)
  }

  @Test
  func waitsOnlyForTheConfiguredTimeout() async throws {
    let gate = Gate()
    http.respond { _, _ in
      await gate.pass()
      return Self.refreshResponse
    }
    try storeExpiredSession()

    let client = makeClient(initialRefreshTimeout: .seconds(2))
    var events = client.events().makeAsyncIterator()
    await gate.arrivals(1)

    await clock.advance(by: .seconds(2))
    let first = await events.next()
    expectNoDifference(first, AuthChange(event: .initialSession, status: .signedIn(Self.expired)))
    gate.open()
  }

  @Test
  func aCallerOfSessionJoinsTheStartupRefresh() async throws {
    let gate = Gate()
    http.respond { _, _ in
      await gate.pass()
      return Self.refreshResponse
    }
    try storeExpiredSession()

    let client = makeClient()
    let session = Task { try await client.session() }
    await gate.arrivals(1)
    gate.open()

    let joined = try await session.value
    expectNoDifference(joined, Self.refreshed)
    #expect(http.requests.count == 1)
  }

  @Test(arguments: [
    (AuthClient.AutoRefreshPolicy.manual, Duration.seconds(5)),
    (.disabled, .seconds(5)),
    (.automatic, .zero),
    (.automatic, .seconds(-1)),
  ])
  func skipsTheRefreshUnlessThePolicyIsAutomaticWithAPositiveTimeout(
    policy: AuthClient.AutoRefreshPolicy, timeout: Duration
  ) async throws {
    http.respond { _, _ in Self.refreshResponse }
    try storeExpiredSession()

    // With `.automatic`, auto refresh refreshes the expired session at once, in the background.
    // The app stays in the background, so only a startup refresh could send a request.
    let client = makeClient(
      autoRefresh: policy, initialRefreshTimeout: timeout, startsInBackground: true)
    await client.initialization()
    #expect(client.status == .signedIn(Self.expired))
    var events = client.events().makeAsyncIterator()

    let first = await events.next()
    expectNoDifference(first, AuthChange(event: .initialSession, status: .signedIn(Self.expired)))
    #expect(http.requests.isEmpty)
  }

  @Test
  func aSessionThatIsStillValidMakesNoRequest() async throws {
    http.respond { _, _ in Self.refreshResponse }
    try localStorage.store(
      key: key, value: PersistedSessionCodec.encode(Self.valid))

    let client = makeClient()
    await client.initialization()
    #expect(client.status == .signedIn(Self.valid))
    var events = client.events().makeAsyncIterator()

    let first = await events.next()
    expectNoDifference(first, AuthChange(event: .initialSession, status: .signedIn(Self.valid)))
    #expect(http.requests.isEmpty)
  }

  @Test
  func nothingStoredDeliversSignedOutWithoutARequest() async throws {
    let client = makeClient()
    var events = client.events().makeAsyncIterator()

    let first = await events.next()
    expectNoDifference(
      first, AuthChange(event: .initialSession, status: .signedOut(.sessionMissing)))
    #expect(http.requests.isEmpty)
  }

  @Test
  func initializationReturnsOnceTheRefreshSettles() async throws {
    http.respond { _, _ in Self.refreshResponse }
    try storeExpiredSession()

    let client = makeClient()
    await client.initialization()

    #expect(client.status == .signedIn(Self.refreshed))
  }

  @Test
  func aVerifiedEmailChangeOfTheSameUserWhileRefreshingIsAUserUpdate() async throws {
    let gate = Gate()
    http.respond { _, _ in
      await gate.pass()
      return Self.refreshResponse
    }
    try storeExpiredSession()
    let client = makeClient()
    var events = client.events().makeAsyncIterator()
    await gate.arrivals(1)

    var changed = Self.expired
    changed.user.email = "changed@example.com"
    try await client.dependencies.sessionStore.commit(.userChangeVerified(changed))

    #expect(await events.next()?.event == .initialSession)
    #expect(await events.next()?.event == .userUpdated)
    gate.open()
  }

  @Test
  func aFailedStartupRefreshIsRetriedAfterABackoffNotAtOnce() async throws {
    http.respond { _, _ in errorResponse(.serviceUnavailable, nil) }
    try storeExpiredSession()
    let client = makeClient()
    var events = client.events().makeAsyncIterator()

    _ = await events.next()
    let startupRequests = http.requests.count

    let retriedAtOnce = await waitUntil(timeout: 0.3) { [http] in
      http.requests.count > startupRequests
    }
    #expect(!retriedAtOnce)
    await clock.advance(by: .seconds(5))
    let retriedAfterBackoff = await waitUntil { [http] in http.requests.count > startupRequests }
    #expect(retriedAfterBackoff)
  }

  @Test
  func aRefreshThatCannotBeSavedIsRetriedAfterABackoffNotAtOnce() async throws {
    http.respond { _, _ in Self.refreshResponse }
    try storeExpiredSession()
    let client = makeClient(storage: WriteFailingStorage(wrapping: localStorage))
    var events = client.events().makeAsyncIterator()

    let first = await events.next()
    expectNoDifference(first, AuthChange(event: .initialSession, status: .signedIn(Self.expired)))
    let startupRequests = http.requests.count

    let retriedAtOnce = await waitUntil(timeout: 0.3) { [http] in
      http.requests.count > startupRequests
    }
    #expect(!retriedAtOnce)
  }

  // MARK: - Helpers

  private static let expired = session(
    named: "stored", receivedAt: now.addingTimeInterval(-3700))
  private static let refreshBody = try! AuthClient.Configuration.jsonEncoder.encode(
    session(named: "refreshed", receivedAt: now))
  /// What the server answers to a refresh.
  private static let refreshResponse = (HTTPResponse(status: .ok), refreshBody)
  /// The session as the client decodes it from ``refreshResponse``. The fixture user's dates do
  /// not survive a second JSON round trip, so the expected value is decoded once, from the bytes
  /// the client decodes.
  private static let refreshed = try! AuthClient.Configuration.jsonDecoder.decode(
    Session.self, from: refreshBody)
  private static let valid = session(named: "valid", receivedAt: now.addingTimeInterval(-60))

  private static func session(named name: String, receivedAt: Date) -> Session {
    Session(
      accessToken: "\(name)-access",
      tokenType: "bearer",
      expiresIn: .seconds(3600),
      expiresAt: receivedAt.addingTimeInterval(3600),
      receivedAt: receivedAt,
      refreshToken: "\(name)-refresh",
      user: User(fromMockNamed: "user")
    )
  }

  private func storeExpiredSession() throws {
    try localStorage.store(
      key: key,
      value: PersistedSessionCodec.encode(Self.expired))
  }

  private func makeClient(
    autoRefresh: AuthClient.AutoRefreshPolicy = .automatic,
    initialRefreshTimeout: Duration = .seconds(5),
    storage: (any AuthStorage)? = nil,
    startsInBackground: Bool = false
  ) -> AuthClient {
    var platform = AuthPlatform.live
    if startsInBackground {
      // No lifecycle event ever arrives, so auto refresh never starts.
      platform.hasBackgroundState = true
      platform.lifecycleEvents = { AsyncStream { _ in } }
    }
    return AuthClient(
      configuration: AuthClient.Configuration(
        url: clientURL,
        storageKey: key,
        storage: storage ?? localStorage,
        http: HTTPClientConfiguration(transport: http),
        autoRefresh: autoRefresh,
        observesAppLifecycle: startsInBackground,
        clock: clock,
        now: { Self.now },
        initialRefreshTimeout: initialRefreshTimeout
      ),
      pkce: .live,
      platform: platform
    )
  }
}

/// Reads from the storage it wraps and throws from every write, as a full disk does.
private struct WriteFailingStorage: AuthStorage {
  let wrapped: InMemoryTestStorage

  init(wrapping wrapped: InMemoryTestStorage) {
    self.wrapped = wrapped
  }

  func save(_ data: Data, key: String) async throws {
    throw AuthError(kind: .storageUnavailable, message: "disk full")
  }

  func load(key: String) async throws -> Data? {
    wrapped.retrieve(key: key)
  }

  func remove(key: String) async throws {
    try await wrapped.remove(key: key)
  }
}
