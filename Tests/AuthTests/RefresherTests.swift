import Clocks
import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import TestHelpers
import Testing

@testable import Auth

@Suite
struct RefresherTests {
  private static let lifetime: TimeInterval = 3600
  private static let refreshAfter = lifetime - Refresher.refreshLeadTime.timeInterval

  @Test
  func refreshRunsNinetySecondsBeforeTheAccessTokenExpires() async throws {
    let world = World()
    let client = world.makeClient()
    try await client.seedSession(world.issueSession())
    await client.autoRefresh.start()

    await world.advance(to: Self.refreshAfter - 1)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    await world.advance(to: Self.refreshAfter)
    #expect(await world.refreshCount(settledAt: 1) == 1)
    await client.autoRefresh.stop()
  }

  @Test
  func commitOfANewSessionReschedulesTheRefresh() async throws {
    let world = World()
    let client = world.makeClient()
    try await client.seedSession(world.issueSession())
    await client.autoRefresh.start()

    await world.advance(to: 1000)
    try await client.seedSession(world.issueSession())

    await world.advance(to: Self.refreshAfter)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    await world.advance(to: 1000 + Self.refreshAfter - 1)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    await world.advance(to: 1000 + Self.refreshAfter)
    #expect(await world.refreshCount(settledAt: 1) == 1)
    await client.autoRefresh.stop()
  }

  @Test
  func signOutCancelsTheScheduledRefresh() async throws {
    let world = World()
    let client = world.makeClient()
    try await client.seedSession(world.issueSession())
    await client.autoRefresh.start()

    await world.advance(to: 1000)
    try await client.sessionStore.commit(.signedOut(.userInitiated, event: .signedOut))
    #expect(await waitUntil(timeout: 2) { world.clock.pendingSleepCount == 0 })

    await world.advance(to: Self.refreshAfter + 100)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    try await client.seedSession(world.issueSession())
    await world.advance(to: Self.refreshAfter + 100 + Self.refreshAfter)
    #expect(await world.refreshCount(settledAt: 1) == 1)
    await client.autoRefresh.stop()
  }

  @Test
  func refreshThatWakesAsACommitReschedulesItDoesNotRedeemTheNewSession() async throws {
    let world = World()
    let clock = GateClock()
    let client = world.makeClient(clock: clock)
    try await client.seedSession(world.issueSession())
    await client.autoRefresh.start()
    #expect(await waitUntil { clock.sleeperCount == 1 })

    try await client.seedSession(world.issueSession())
    #expect(await waitUntil { clock.sleeperCount == 2 })
    clock.releaseFirst(ignoringCancellation: true)

    #expect(await world.refreshCount(settledAt: 0) == 0)
    await client.autoRefresh.stop()
    clock.releaseFirst(ignoringCancellation: false)
  }

  @Test(arguments: [2.0 * 3600, -2.0 * 3600])
  func skewedDeviceClockRefreshesOncePerLifetime(skew: TimeInterval) async throws {
    let world = World(skew: skew)
    let client = world.makeClient()
    try await client.seedSession(world.issueSession())
    await client.autoRefresh.start()

    for lifetime in 1...3 {
      let due = Double(lifetime) * Self.refreshAfter
      await world.advance(to: due - 1)
      #expect(await world.refreshCount(settledAt: lifetime - 1) == lifetime - 1)
      await world.advance(to: due)
      #expect(await world.refreshCount(settledAt: lifetime) == lifetime)
    }
    await client.autoRefresh.stop()
  }

  @Test
  func failedRefreshRetriesWithBackoffUntilItSucceeds() async throws {
    let world = World(failures: [.serviceUnavailable, .serviceUnavailable])
    let client = world.makeClient()
    try await client.seedSession(world.issueSession())
    await client.autoRefresh.start()

    await world.advance(to: Self.refreshAfter)
    #expect(await world.refreshCount(settledAt: 1) == 1)
    let first = try #require(world.requestTimes.value.first)

    #expect(await world.waitForSleep())
    await world.advance(to: first + 0.999)
    #expect(await world.refreshCount(settledAt: 1) == 1)
    await world.advance(to: first + 2)
    #expect(await world.refreshCount(settledAt: 2) == 2)
    let second = world.requestTimes.value[1]

    #expect(await world.waitForSleep())
    await world.advance(to: second + 1.999)
    #expect(await world.refreshCount(settledAt: 2) == 2)
    let refreshedBy = second + 4
    await world.advance(to: refreshedBy)
    #expect(await world.refreshCount(settledAt: 3) == 3)
    let third = world.requestTimes.value[2]

    #expect((1...2).contains(second - first))
    #expect((2...4).contains(third - second))

    await world.advance(to: third + Self.refreshAfter - 1)
    #expect(await world.refreshCount(settledAt: 3) == 3)
    await world.advance(to: refreshedBy + Self.refreshAfter)
    #expect(await world.refreshCount(settledAt: 4) == 4)
    await client.autoRefresh.stop()
  }

  @Test
  func startWhileTheRefreshIsDueRefreshesAtOnce() async throws {
    let world = World()
    let client = world.makeClient()
    try await client.seedSession(world.issueSession())

    await world.advance(to: Self.lifetime - 60)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    await client.autoRefresh.start()
    #expect(await world.refreshCount(settledAt: 1) == 1)
    await client.autoRefresh.stop()
  }

  @Test
  func stoppingOneClientKeepsAutoRefreshOfAnotherClient() async throws {
    let world = World()
    let first = world.makeClient()
    let second = world.makeClient()
    #expect(first.sessionStore !== second.sessionStore)
    try await first.seedSession(world.issueSession())
    try await second.seedSession(world.issueSession())

    await first.autoRefresh.start()
    await second.autoRefresh.start()
    await second.autoRefresh.stop()

    #expect(await first.autoRefresh.isRegistered)
    #expect(await second.autoRefresh.isRegistered == false)
    await world.advance(to: Self.refreshAfter)
    #expect(await world.refreshCount(settledAt: 1) == 1)
    await first.autoRefresh.stop()
  }

  private let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)

  private func received(serverOffset: TimeInterval) -> ReceivedSession {
    ReceivedSession(
      session: makeSession(
        expiresAt: receivedAt.addingTimeInterval(Self.lifetime + serverOffset)),
      receivedAt: receivedAt
    )
  }

  @Test
  func expiryIsTheLocalReceiptTimePlusTheLifetime() {
    let session = received(serverOffset: 0)
    #expect(session.expiryDate == receivedAt.addingTimeInterval(Self.lifetime))
    #expect(!session.hasClockSkew)
  }

  @Test
  func earlierServerExpiryWithinTheToleranceMovesTheExpiryEarlier() {
    let session = received(serverOffset: -45)
    #expect(session.expiryDate == receivedAt.addingTimeInterval(Self.lifetime - 45))
    #expect(!session.hasClockSkew)
  }

  @Test(arguments: [-2.0 * 3600, -61, 61, 2.0 * 3600])
  func serverExpiryBeyondTheToleranceKeepsTheLocalExpiry(serverOffset: TimeInterval) {
    let session = received(serverOffset: serverOffset)
    #expect(session.expiryDate == receivedAt.addingTimeInterval(Self.lifetime))
    #expect(session.hasClockSkew)
  }

  @Test
  func laterServerExpiryWithinTheToleranceKeepsTheLocalExpiry() {
    let session = received(serverOffset: 45)
    #expect(session.expiryDate == receivedAt.addingTimeInterval(Self.lifetime))
    #expect(!session.hasClockSkew)
  }

  @Test
  func sessionWithoutAReceiptTimeExpiresAtTheServerTime() {
    let session = ReceivedSession(session: makeSession(expiresAt: receivedAt))
    #expect(session.expiryDate == receivedAt)
    #expect(!session.hasClockSkew)
  }

  private let retryable = AuthError(kind: .server, message: "unavailable")
  private let rejection = AuthError(kind: .sessionInvalidated, message: "already used")

  private func retryDelays(
    attempt: Int, after error: any Error, expiresIn: TimeInterval
  ) -> [TimeInterval] {
    let session = received(serverOffset: 0)
    let now = session.expiryDate.addingTimeInterval(-expiresIn)
    return (0..<200).map { _ in
      Refresher.delayBeforeRetry(attempt: attempt, after: error, for: session, now: now)
        .timeInterval
    }
  }

  @Test(arguments: [
    (1, 1.0...2.0), (2, 2.0...4.0), (3, 4.0...8.0), (6, 30.0...60.0), (64, 30.0...60.0),
  ])
  func retryDelayIsAJitteredBackoffCappedAtAMinute(attempt: Int, bounds: ClosedRange<Double>) {
    let delays = retryDelays(attempt: attempt, after: retryable, expiresIn: 3000)
    #expect(delays.allSatisfy { bounds.contains($0) })
  }

  @Test
  func retryDelayNeverLandsAfterTheAccessTokenExpires() {
    let delays = retryDelays(attempt: 6, after: retryable, expiresIn: 5)
    #expect(delays.allSatisfy { abs($0 - 5) < 0.001 })
  }

  @Test
  func retryAfterARejectionWaitsUntilTheAccessTokenExpires() {
    let delays = retryDelays(attempt: 1, after: rejection, expiresIn: 600)
    #expect(delays.allSatisfy { abs($0 - 600) < 0.001 })
  }

  @Test
  func retryOfAnExpiredAccessTokenUsesTheBackoff() {
    let delays = retryDelays(attempt: 2, after: rejection, expiresIn: -10)
    #expect(delays.allSatisfy { (2.0...4.0).contains($0) })
  }

  private func makeSession(expiresAt: Date) -> Session {
    Session(
      accessToken: "access",
      tokenType: "bearer",
      expiresIn: Self.lifetime,
      expiresAt: expiresAt.timeIntervalSince1970,
      refreshToken: "refresh",
      user: User(fromMockNamed: "user")
    )
  }
}

struct World {
  private static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

  let clock = SignalingTestClock()
  let http = RecordingTransport()
  let requestTimes = LockIsolated<[TimeInterval]>([])
  private let start: SignalingTestClock.Instant
  private let skew: TimeInterval
  private let storageKey = uniqueStorageKey()

  init(skew: TimeInterval = 0, failures: [HTTPResponse.Status] = []) {
    start = clock.now
    self.skew = skew

    let failures = LockIsolated(failures)
    http.respond(when: { $0.url?.path.contains("/token") == true }) {
      [clock, start, requestTimes] _, _ in
      let elapsed = Self.elapsed(on: clock, since: start)
      let count = requestTimes.withValue {
        $0.append(elapsed)
        return $0.count
      }
      let failure = failures.withValue { $0.isEmpty ? nil : $0.removeFirst() }
      if let failure {
        return (HTTPResponse(status: failure), Data("<html></html>".utf8))
      }
      let session = Self.session(named: "refreshed-\(count)", issuedAt: elapsed)
      return (HTTPResponse(status: .ok), try AuthClient.Configuration.jsonEncoder.encode(session))
    }
  }

  func makeClient(clock sleepClock: (any Clock<Duration>)? = nil) -> Dependencies {
    .live(
      configuration: configuration(clock: sleepClock ?? clock),
      http: HTTPClient(transport: http),
      date: now
    )
  }

  func configuration(
    autoRefresh: AuthClient.AutoRefreshPolicy = .automatic,
    observesAppLifecycle: Bool = false,
    clock sleepClock: (any Clock<Duration>)? = nil
  ) -> AuthClient.Configuration {
    AuthClient.Configuration(
      url: clientURL,
      storageKey: storageKey,
      localStorage: InMemoryLocalStorage(),
      http: HTTPClientConfiguration(transport: http),
      autoRefresh: autoRefresh,
      observesAppLifecycle: observesAppLifecycle,
      clock: sleepClock ?? clock
    )
  }

  var now: @Sendable () -> Date {
    { [clock, start, skew] in
      Self.epoch.addingTimeInterval(skew + Self.elapsed(on: clock, since: start))
    }
  }

  func issueSession() -> Session {
    Self.session(named: "issued", issuedAt: Self.elapsed(on: clock, since: start))
  }

  func advance(to elapsed: TimeInterval) async {
    let step = elapsed - Self.elapsed(on: clock, since: start)
    await clock.advance(by: .seconds(step))
  }

  func waitForSleep() async -> Bool {
    await waitUntil { [clock] in clock.pendingSleepCount > 0 }
  }

  func refreshCount(settledAt expected: Int) async -> Int {
    await waitUntil(timeout: 5) { [requestTimes] in requestTimes.value.count >= expected }
    await waitUntil(timeout: 0.2) { [requestTimes] in requestTimes.value.count > expected }
    return requestTimes.value.count
  }

  private static func elapsed(
    on clock: SignalingTestClock, since start: SignalingTestClock.Instant
  ) -> TimeInterval {
    start.duration(to: clock.now).timeInterval
  }

  private static func session(named name: String, issuedAt elapsed: TimeInterval) -> Session {
    Session(
      accessToken: "\(name)-access",
      tokenType: "bearer",
      expiresIn: 3600,
      expiresAt: epoch.addingTimeInterval(elapsed + 3600).timeIntervalSince1970,
      refreshToken: "\(name)-refresh",
      user: User(fromMockNamed: "user")
    )
  }
}

private final class GateClock: Clock, @unchecked Sendable {
  private let sleepers = LockIsolated<[CheckedContinuation<Bool, Never>]>([])

  var now: ContinuousClock.Instant { ContinuousClock.now }
  var minimumResolution: Duration { .zero }

  var sleeperCount: Int { sleepers.value.count }

  func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration? = nil) async throws {
    let ignoresCancellation = await withCheckedContinuation { sleeper in
      sleepers.withValue { $0.append(sleeper) }
    }
    if !ignoresCancellation {
      try Task.checkCancellation()
    }
  }

  func releaseFirst(ignoringCancellation: Bool) {
    let sleeper = sleepers.withValue { $0.isEmpty ? nil : $0.removeFirst() }
    sleeper?.resume(returning: ignoringCancellation)
  }
}
