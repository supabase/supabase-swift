import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

/// Races between session commits, each made deterministic by holding a server response at a
/// gate until the competing call has finished.
@Suite(.timeLimit(.minutes(1)))
struct SessionLifecycleRaceTests {
  private static let refreshAfter = Race.lifetime - Refresher.refreshLeadTime.timeInterval

  @Test
  func signOutDuringARefreshDiscardsTheRefreshedSession() async throws {
    let race = Race()
    let gate = Gate()
    race.answerSignIn { _ in race.issue("signed-in") }
    race.answerRefresh(through: gate) { try Race.ok(race.issue("refreshed")) }
    race.answerSignOut()
    let client = race.makeClient()
    var events = client.authStateChanges.makeAsyncIterator()
    #expect(await events.next()?.event == .initialSession)
    try await client.signIn(email: "a@example.com", password: "secret")
    #expect(await events.next()?.event == .signedIn)

    let refresh = Task { try await client.refreshSession() }
    await gate.arrivals(1)
    try await client.signOut()
    gate.open()
    let result = await refresh.result

    #expect(result.isCancellationOrDiscard)
    #expect(client.currentSession == nil)
    #expect(race.relaunch().currentSession == nil)
    #expect(await events.next()?.event == .signedOut)
    try await client.signIn(email: "a@example.com", password: "secret")
    #expect(await events.next()?.event == .signedIn)
  }

  @Test
  func userUpdateDuringARefreshKeepsTheUserAndTheRotatedTokens() async throws {
    let race = Race()
    let gate = Gate()
    race.answerSignIn { _ in race.issue("signed-in") }
    race.answerRefresh(through: gate) { try Race.ok(race.issue("refreshed")) }
    race.answerUserUpdate(with: Race.user(nickname: "updated"))
    let client = race.makeClient()
    var events = client.authStateChanges.makeAsyncIterator()
    #expect(await events.next()?.event == .initialSession)
    try await client.signIn(email: "a@example.com", password: "secret")
    #expect(await events.next()?.event == .signedIn)

    let refresh = Task { try await client.refreshSession() }
    await gate.arrivals(1)
    try await client.update(user: UserAttributes(data: ["nickname": "updated"]))
    gate.open()
    _ = try await refresh.value

    #expect(await events.next()?.event == .userUpdated)
    let refreshed = await events.next()
    #expect(refreshed?.event == .tokenRefreshed)
    for session in [refreshed?.session, client.currentSession, race.relaunch().currentSession] {
      #expect(session?.refreshToken == "refreshed-refresh")
      #expect(session?.user.userMetadata["nickname"] == "updated")
    }
    #expect(race.refreshRequestCount == 1)
  }

  @Test
  func twoClientsForOneProjectRedeemTheRefreshTokenOnce() async throws {
    let race = Race()
    let gate = Gate()
    race.answerSignIn { _ in race.issue("signed-in", lifetime: 10) }
    race.answerRefresh(through: gate) { try Race.ok(race.issue("refreshed")) }
    let first = race.makeClient()
    let second = race.makeClient()
    var firstEvents = first.authStateChanges.makeAsyncIterator()
    var secondEvents = second.authStateChanges.makeAsyncIterator()
    #expect(await firstEvents.next()?.event == .initialSession)
    #expect(await secondEvents.next()?.event == .initialSession)
    try await first.signIn(email: "a@example.com", password: "secret")

    let firstSession = Task { try await first.session }
    await gate.arrivals(1)
    let secondSession = Task { try await second.session }
    gate.open()

    let sessions = try await [firstSession.value, secondSession.value]
    #expect(sessions.map(\.accessToken) == ["refreshed-access", "refreshed-access"])
    withKnownIssue(
      "A caller that read the token before the refresh committed sends it again once the flight ended",
      isIntermittent: true
    ) {
      #expect(race.refreshRequestCount == 1)
    }
    for events in [firstEvents, secondEvents] {
      var events = events
      #expect(await events.next()?.event == .signedIn)
      let change = await events.next()
      #expect(change?.event == .tokenRefreshed)
      #expect(change?.session?.accessToken == "refreshed-access")
    }
    #expect(second.currentSession?.accessToken == "refreshed-access")
  }

  @Test
  func repeatedRedirectURLExchangesTheCodeOnce() async throws {
    let race = Race()
    let gate = Gate()
    let exchanges = LockIsolated(0)
    race.answerCodeExchange(through: gate) {
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
    _ = try client.oauthSignInURL(provider: .github)
    let callback = URL(string: "com.example.app://callback?code=one-time-code")!

    await withKnownIssue("SDK-2070: a repeated redirect URL replays the code exchange") {
      let first = Task { try await client.session(from: callback) }
      await gate.arrivals(1)
      let second = Task { try await client.session(from: callback) }
      gate.open()

      let sessions = try await [first.value, second.value]
      #expect(sessions.map(\.accessToken) == ["exchanged-access", "exchanged-access"])
      #expect(race.requestCount(grantType: "pkce") == 1)
    }
  }

  @Test
  func stopThenStartBackToBackLeavesAutoRefreshRunning() async throws {
    let race = Race()
    let gate = Gate(isOpen: true)
    race.answerSignIn { _ in
      race.issue("signed-in", lifetime: Refresher.refreshLeadTime.timeInterval - 30)
    }
    race.answerRefresh(through: gate) { try Race.ok(race.issue("refreshed")) }
    let client = race.makeClient(autoRefresh: .automatic)
    await waitForTheStartAtCreation(of: client)
    await client.stopAutoRefresh()
    try await client.signIn(email: "a@example.com", password: "secret")
    #expect(race.refreshRequestCount == 0)

    await client.stopAutoRefresh()
    await client.startAutoRefresh()

    await gate.arrivals(1)
    #expect(race.refreshRequestCount == 1)
  }

  @Test
  func startThenStopBackToBackLeavesAutoRefreshStopped() async throws {
    let race = Race()
    race.answerSignIn { _ in race.issue("signed-in") }
    race.answerRefresh { try Race.ok(race.issue("refreshed")) }
    let client = race.makeClient(autoRefresh: .automatic)
    await waitForTheStartAtCreation(of: client)
    try await client.signIn(email: "a@example.com", password: "secret")

    await client.startAutoRefresh()
    await client.stopAutoRefresh()

    await race.advance(to: Race.lifetime + 60)
    #expect(race.refreshRequestCount == 0)
    withExtendedLifetime(client) {}
  }

  @Test
  func lockedStorageAtLaunchStaysLoadingThenEmitsOneInitialSession() async throws {
    let race = Race()
    race.answerSignOut()
    let stored = race.issue("stored")
    let storage = LockableLocalStorage()
    try storage.store(
      key: race.storageKey,
      value: PersistedSessionCodec.encode(ReceivedSession(session: stored, receivedAt: race.now()))
    )
    storage.isLocked.setValue(true)
    let client = race.makeClient(storage: storage)
    var events = client.authStateChanges.makeAsyncIterator()

    for _ in 0..<2 {
      let error = await #expect(throws: AuthError.self) { try await client.session }
      #expect(error?.kind == .storageUnavailable)
      #expect(client.currentSession == nil)
    }
    storage.isLocked.setValue(false)
    let session = try await client.session
    #expect(session.accessToken == "stored-access")

    let initial = await events.next()
    #expect(initial?.event == .initialSession)
    #expect(initial?.session?.accessToken == "stored-access")
    try await client.signOut()
    #expect(await events.next()?.event == .signedOut)
  }

  @Test(arguments: [2.0 * 3600, -2.0 * 3600])
  func skewedDeviceClockRefreshesOncePerTokenLifetime(skew: TimeInterval) async throws {
    let race = Race(skew: skew)
    race.answerSignIn { _ in race.issue("signed-in") }
    race.answerRefresh { try Race.ok(race.issue("refreshed")) }
    let client = race.makeClient(autoRefresh: .automatic)
    await waitForTheStartAtCreation(of: client)
    var events = client.authStateChanges.makeAsyncIterator()
    #expect(await events.next()?.event == .initialSession)
    try await client.signIn(email: "a@example.com", password: "secret")
    #expect(await events.next()?.event == .signedIn)

    for lifetime in 1...3 {
      let due = Double(lifetime) * Self.refreshAfter
      await race.waitForTheScheduledRefresh()
      await race.advance(to: due - 1, grace: .zero)
      _ = try await client.session
      #expect(race.refreshRequestCount == lifetime - 1)

      await race.advance(to: due)
      #expect(await events.next()?.event == .tokenRefreshed)
      _ = try await client.session
      #expect(race.refreshRequestCount == lifetime)
    }
  }

  @Test
  func rejectedRefreshOfAStillValidAccessTokenKeepsTheSessionSilently() async throws {
    let race = Race()
    race.answerSignIn { _ in race.issue("signed-in") }
    race.answerRefresh {
      Race.error(
        .badRequest, code: "refresh_token_already_used",
        message: "Invalid Refresh Token: Already Used")
    }
    let client = race.makeClient()
    var events = client.authStateChanges.makeAsyncIterator()
    #expect(await events.next()?.event == .initialSession)
    try await client.signIn(email: "a@example.com", password: "secret")
    #expect(await events.next()?.event == .signedIn)

    let error = await #expect(throws: AuthError.self) { try await client.refreshSession() }

    #expect(error?.kind == .sessionInvalidated)
    #expect(client.currentSession?.accessToken == "signed-in-access")
    let session = try await client.session
    #expect(session.accessToken == "signed-in-access")
    #expect(race.relaunch().currentSession?.accessToken == "signed-in-access")
    try await client.signIn(email: "a@example.com", password: "secret")
    #expect(await events.next()?.event == .signedIn)
    #expect(race.refreshRequestCount == 1)
  }

  @Test
  func concurrentSignInsAreEmittedInTheOrderTheyWereCommitted() async throws {
    let race = Race()
    let gate = Gate()
    race.answerSignIn(through: gate) { body in
      race.issue(body.contains("first@example.com") ? "first" : "second")
    }
    let client = race.makeClient()
    let observers = [client.authStateChanges, client.authStateChanges]

    let first = Task { try await client.signIn(email: "first@example.com", password: "secret") }
    let second = Task { try await client.signIn(email: "second@example.com", password: "secret") }
    await gate.arrivals(2)
    gate.open()
    _ = try await (first.value, second.value)

    var orders: [[String?]] = []
    for observer in observers {
      var events = observer.makeAsyncIterator()
      #expect(await events.next()?.event == .initialSession)
      var order: [String?] = []
      for _ in 0..<2 {
        let change = await events.next()
        #expect(change?.event == .signedIn)
        order.append(change?.session?.accessToken)
      }
      orders.append(order)
    }

    #expect(Set(orders[0]) == ["first-access", "second-access"])
    #expect(orders[1] == orders[0])
    #expect(client.currentSession?.accessToken == orders[0].last)
    #expect(race.relaunch().currentSession?.accessToken == orders[0].last)
  }

  @Test
  func streamIteratedAfterCommitsDeliversEveryChangeFromTheInitialSession() async throws {
    let race = Race()
    race.answerSignIn { _ in race.issue("signed-in") }
    race.answerSignOut()
    let client = race.makeClient()
    let stream = client.authStateChanges

    try await client.signIn(email: "a@example.com", password: "secret")
    try await client.signOut()

    var events = stream.makeAsyncIterator()
    let initial = await events.next()
    #expect(initial?.event == .initialSession)
    #expect(initial?.session == nil)
    let signIn = await events.next()
    #expect(signIn?.event == .signedIn)
    #expect(signIn?.session?.accessToken == "signed-in-access")
    let signOut = await events.next()
    #expect(signOut?.event == .signedOut)
    #expect(signOut?.session == nil)
  }

  /// Waits for the start of auto refresh that a client schedules when it is created. A start
  /// that lands after a sign-in re-arms the refresh, and a re-arm that races `advance` can sleep
  /// past the deadline the test advances to.
  private func waitForTheStartAtCreation(of client: AuthClient) async {
    let isStarted = await waitUntil { await client.dependencies.autoRefresh.isRegistered }
    #expect(isStarted)
  }
}

/// One project's world: a server behind a `RecordingTransport`, a `SignalingTestClock` that drives
/// both auto refresh and the injected `now`, and a storage key no other test uses.
private struct Race: Sendable {
  static let lifetime: TimeInterval = 3600
  private static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

  let clock = SignalingTestClock()
  let transport = RecordingTransport()
  let localStorage = InMemoryLocalStorage()
  let storageKey = uniqueStorageKey()
  private let start: SignalingTestClock.Instant
  private let skew: TimeInterval

  /// - Parameter skew: How far the device clock runs ahead of the server's.
  init(skew: TimeInterval = 0) {
    start = clock.now
    self.skew = skew
  }

  var now: @Sendable () -> Date {
    { [clock, start, skew] in
      Self.epoch.addingTimeInterval(skew + start.duration(to: clock.now).timeInterval)
    }
  }

  private var elapsed: TimeInterval {
    start.duration(to: clock.now).timeInterval
  }

  func makeClient(
    autoRefresh: AuthClient.AutoRefreshPolicy = .manual,
    storage: (any AuthLocalStorage)? = nil
  ) -> AuthClient {
    makeClient(url: clientURL, autoRefresh: autoRefresh, storage: storage ?? localStorage)
  }

  /// A client for another project URL on the same storage, so it gets its own store and reads
  /// what the race left on disk, as the next launch would.
  func relaunch() -> AuthClient {
    makeClient(
      url: URL(string: "http://127.0.0.1:54321/auth/v1")!, autoRefresh: .manual,
      storage: localStorage)
  }

  private func makeClient(
    url: URL, autoRefresh: AuthClient.AutoRefreshPolicy, storage: any AuthLocalStorage
  ) -> AuthClient {
    var platform = AuthPlatform.live
    platform.lifecycleEvents = { AsyncStream { $0.finish() } }
    return AuthClient(
      configuration: AuthClient.Configuration(
        url: url,
        storageKey: storageKey,
        localStorage: storage,
        http: HTTPClientConfiguration(transport: transport),
        autoRefresh: autoRefresh,
        observesAppLifecycle: false,
        clock: clock
      ),
      date: now,
      pkce: .live,
      platform: platform
    )
  }

  /// A session the server issues now, named by its access token `<name>-access` and its refresh
  /// token `<name>-refresh`. Its `expiresAt` is on the server clock, which the device clock is
  /// `skew` ahead of.
  func issue(_ name: String, lifetime: TimeInterval = Self.lifetime) -> Session {
    Session(
      accessToken: "\(name)-access",
      tokenType: "bearer",
      expiresIn: lifetime,
      expiresAt: Self.epoch.addingTimeInterval(elapsed + lifetime).timeIntervalSince1970,
      refreshToken: "\(name)-refresh",
      user: User(fromMockNamed: "user")
    )
  }

  static func user(nickname: String) -> User {
    var user = User(fromMockNamed: "user")
    user.userMetadata["nickname"] = .string(nickname)
    return user
  }

  func advance(to elapsed: TimeInterval, grace: Duration = .seconds(1)) async {
    await clock.advance(by: .seconds(elapsed - self.elapsed), grace: grace)
  }

  /// Waits until auto refresh sleeps toward its deadline, so that advancing the clock fires it.
  func waitForTheScheduledRefresh() async {
    let isScheduled = await waitUntil { [clock] in clock.pendingSleepCount > 0 }
    #expect(isScheduled)
  }

  var refreshRequestCount: Int {
    requestCount(grantType: "refresh_token")
  }

  func requestCount(grantType: String) -> Int {
    transport.requests.filter { Self.isToken($0.head, grantType: grantType) }.count
  }

  /// Answers a password sign-in with the session `session` returns for the request body.
  func answerSignIn(
    through gate: Gate? = nil, _ session: @escaping @Sendable (_ body: String) -> Session
  ) {
    answerToken("password", through: gate) { try Self.ok(session($0)) }
  }

  func answerRefresh(
    through gate: Gate? = nil, _ response: @escaping @Sendable () throws -> (HTTPResponse, Data)
  ) {
    answerToken("refresh_token", through: gate) { _ in try response() }
  }

  func answerCodeExchange(
    through gate: Gate, _ response: @escaping @Sendable () throws -> (HTTPResponse, Data)
  ) {
    answerToken("pkce", through: gate) { _ in try response() }
  }

  func answerSignOut() {
    transport.respond(when: { $0.url?.path.hasSuffix("/logout") == true }) { _, _ in
      (HTTPResponse(status: .noContent), Data())
    }
  }

  func answerUserUpdate(with user: User) {
    transport.respond(when: { $0.method == .put && $0.url?.path.hasSuffix("/user") == true }) {
      _, _ in try Self.ok(user)
    }
  }

  private func answerToken(
    _ grantType: String,
    through gate: Gate?,
    _ response: @escaping @Sendable (_ body: String) throws -> (HTTPResponse, Data)
  ) {
    transport.respond(when: { Self.isToken($0, grantType: grantType) }) { _, body in
      await gate?.pass()
      return try response(String(decoding: body ?? Data(), as: UTF8.self))
    }
  }

  private static func isToken(_ request: HTTPTypes.HTTPRequest, grantType: String) -> Bool {
    request.url?.path.hasSuffix("/token") == true
      && request.url?.query?.contains("grant_type=\(grantType)") == true
  }

  static func ok(_ value: some Encodable) throws -> (HTTPResponse, Data) {
    (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(value))
  }

  static func error(
    _ status: HTTPResponse.Status, code: String, message: String
  ) -> (HTTPResponse, Data) {
    (
      HTTPResponse(status: status, headerFields: [.apiVersionHeaderName: "2024-01-01"]),
      Data(#"{"code":"\#(code)","message":"\#(message)"}"#.utf8)
    )
  }
}

/// Holds every request that reaches it until ``open()``, and lets a test wait for arrivals.
private final class Gate: Sendable {
  private struct State {
    var arrivals = 0
    var isOpen: Bool
    var held: [CheckedContinuation<Void, Never>] = []
    var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
  }

  private let state: LockIsolated<State>

  init(isOpen: Bool = false) {
    state = LockIsolated(State(isOpen: isOpen))
  }

  func pass() async {
    await withCheckedContinuation { request in
      let resumed = state.withValue { state in
        state.arrivals += 1
        let arrived = state.arrivals
        var resumed = state.watchers.filter { $0.count <= arrived }.map(\.continuation)
        state.watchers.removeAll { $0.count <= arrived }
        if state.isOpen {
          resumed.append(request)
        } else {
          state.held.append(request)
        }
        return resumed
      }
      for continuation in resumed { continuation.resume() }
    }
  }

  /// Returns once `count` requests in total reached the gate.
  func arrivals(_ count: Int) async {
    await withCheckedContinuation { watcher in
      let reached = state.withValue { state in
        guard state.arrivals < count else { return true }
        state.watchers.append((count, watcher))
        return false
      }
      if reached { watcher.resume() }
    }
  }

  func open() {
    let held = state.withValue { state in
      state.isOpen = true
      defer { state.held = [] }
      return state.held
    }
    for request in held { request.resume() }
  }
}

private final class LockableLocalStorage: AuthLocalStorage {
  private let storage = InMemoryLocalStorage()
  let isLocked = LockIsolated(false)

  func store(key: String, value: Data) throws {
    try storage.store(key: key, value: value)
  }

  func retrieve(key: String) throws -> Data? {
    if isLocked.value {
      throw AuthError(kind: .storageUnavailable, message: "The device is locked.")
    }
    return try storage.retrieve(key: key)
  }

  func remove(key: String) throws {
    try storage.remove(key: key)
  }
}

extension Result<Session, any Error> {
  fileprivate var isCancellationOrDiscard: Bool {
    switch self {
    case .success: false
    case .failure(let error as AuthError): error.kind == .refreshDiscarded
    case .failure(let error): error is CancellationError
    }
  }
}
