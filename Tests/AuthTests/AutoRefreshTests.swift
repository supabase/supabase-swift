import ConcurrencyExtras
import Foundation
import HTTPTypes
import TestHelpers
import Testing

#if canImport(UIKit)
  import UIKit
#endif

@testable import Auth

@Suite
struct AutoRefreshTests {
  private static let lifetime: TimeInterval = 3600
  private static let refreshAfter = lifetime - Refresher.refreshLeadTime.timeInterval

  @Test
  func clientCreatedWhileActiveRefreshesOnScheduleWithoutALifecycleEvent() async throws {
    let world = World()
    let client = makeClient(world)
    try await client.seedSession(world.issueSession())

    #expect(await waitUntil { await client.dependencies.autoRefresh.isRegistered })
    await world.advance(to: Self.refreshAfter - 1)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    await world.advance(to: Self.refreshAfter)
    #expect(await world.refreshCount(settledAt: 1) == 1)
  }

  #if !canImport(UIKit) && !os(watchOS)
    // While another suite runs `withMainSerialExecutor`, every job goes to the main queue, which
    // this test blocks.
    @Suite(.mainSerialExecutorSerialized)
    struct WhileTheMainThreadIsBlocked {
      @Test
      func autoRefreshStartsWhileTheMainThreadIsBlocked() async throws {
        let world = World()
        let mainIsBlocked = LockIsolated(false)
        let unblockMain = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
          mainIsBlocked.setValue(true)
          _ = unblockMain.wait(timeout: .now() + 10)
          mainIsBlocked.setValue(false)
        }
        defer { unblockMain.signal() }
        try #require(await waitUntil { mainIsBlocked.value })

        let client = AuthClient(configuration: world.configuration(observesAppLifecycle: true))
        try await client.seedSession(world.issueSession())

        let mainWasBlockedAtRegistration = LockIsolated(false)
        #expect(
          await waitUntil(timeout: 2) {
            guard await client.dependencies.autoRefresh.isRegistered else { return false }
            mainWasBlockedAtRegistration.setValue(mainIsBlocked.value)
            return true
          })
        #expect(
          mainWasBlockedAtRegistration.value,
          "The main queue unblocked itself before auto refresh started.")
      }
    }
  #endif

  #if canImport(UIKit) && !os(watchOS)
    @Test
    func becomingActiveIsAForegroundEvenWithoutEnteringTheForeground() async {
      let events = await AuthPlatform.live.lifecycleEvents()
      let received = LockIsolated<[AppLifecycleEvent]>([])
      let collecting = Task {
        for await event in events { received.withValue { $0.append(event) } }
      }
      defer { collecting.cancel() }
      #expect(await waitUntil(timeout: 2) { received.value.count == 1 })

      await MainActor.run {
        NotificationCenter.default.post(
          name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(
          name: UIApplication.didBecomeActiveNotification, object: nil)
      }

      #expect(await waitUntil(timeout: 2) { received.value.count == 3 })
      #expect(Array(received.value.dropFirst()) == [.background, .foreground])
    }
  #endif

  @Test
  func foregroundRefreshesAtOnceWhenTheSessionIsDue() async throws {
    let world = World()
    let (events, lifecycle) = AsyncStream.makeStream(of: AppLifecycleEvent.self)
    lifecycle.yield(.foreground)
    let client = makeClient(world, lifecycle: events)
    let autoRefresh = client.dependencies.autoRefresh
    try await client.seedSession(world.issueSession())
    #expect(await waitUntil { await autoRefresh.isRegistered })

    lifecycle.yield(.background)
    #expect(await waitUntil { await !autoRefresh.isRegistered })
    await world.advance(to: Self.refreshAfter + 60)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    lifecycle.yield(.foreground)
    #expect(await world.refreshCount(settledAt: 1) == 1)
  }

  @Test
  func launchInTheBackgroundWaitsForTheForeground() async throws {
    let world = World()
    let (events, lifecycle) = AsyncStream.makeStream(of: AppLifecycleEvent.self)
    let client = makeClient(world, lifecycle: events)
    try await client.seedSession(world.issueSession())

    await world.advance(to: Self.refreshAfter + 60)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    lifecycle.yield(.background)
    #expect(await world.refreshCount(settledAt: 0) == 0)
    #expect(await client.dependencies.autoRefresh.isRegistered == false)

    lifecycle.yield(.foreground)
    #expect(await world.refreshCount(settledAt: 1) == 1)
  }

  @Test
  func stopThenStartEndsRunning() async {
    let client = makeClient(World())
    #expect(await waitUntil { await client.dependencies.autoRefresh.isRegistered })

    for _ in 0..<20 {
      await client.stopAutoRefresh()
      await client.startAutoRefresh()
      #expect(await client.dependencies.autoRefresh.isRegistered)
    }
  }

  @Test
  func startThenStopEndsStopped() async {
    let client = makeClient(World())
    #expect(await waitUntil { await client.dependencies.autoRefresh.isRegistered })

    for _ in 0..<20 {
      await client.startAutoRefresh()
      await client.stopAutoRefresh()
      #expect(await client.dependencies.autoRefresh.isRegistered == false)
    }
  }

  @Test
  func foregroundDoesNotResumeAutoRefreshTheAppStopped() async {
    let autoRefresh = World().makeClient().autoRefresh

    await autoRefresh.stop()
    await autoRefresh.handle(.background)
    await autoRefresh.handle(.foreground)

    #expect(await autoRefresh.isRegistered == false)
  }

  @Test
  func startInTheBackgroundWaitsForTheForeground() async {
    let autoRefresh = World().makeClient().autoRefresh

    await autoRefresh.handle(.background)
    await autoRefresh.start()
    #expect(await autoRefresh.isRegistered == false)

    await autoRefresh.handle(.foreground)
    #expect(await autoRefresh.isRegistered)
    await autoRefresh.stop()
  }

  @Test
  func stoppingAnotherClientKeepsTheRetryBackoff() async throws {
    let world = World(failures: [.serviceUnavailable])
    let first = world.makeClient()
    let second = world.makeClient()
    #expect(first.sessionStore !== second.sessionStore)
    try await first.seedSession(world.issueSession())
    await first.autoRefresh.start()
    await second.autoRefresh.start()

    await world.advance(to: Self.refreshAfter)
    #expect(await world.refreshCount(settledAt: 1) == 1)
    #expect(await world.waitForSleep())

    await second.autoRefresh.stop()
    #expect(await world.refreshCount(settledAt: 1) == 1)

    await world.advance(to: Self.refreshAfter + 2)
    #expect(await world.refreshCount(settledAt: 2) == 2)
    await first.autoRefresh.stop()
  }

  @Test(
    .disabled(
      if: ProcessInfo.processInfo.environment["SWIFT_NIGHTLY"] == "true",
      "SDK-2597: reportIssue crashes swift-issue-reporting on the nightly toolchain"
    )
  )
  func manualPolicyNeverStartsTheScheduler() async throws {
    let world = World()
    let client = makeClient(world, autoRefresh: .manual)
    try await client.seedSession(world.issueSession())

    await withKnownIssue(isIntermittent: true) {
      await client.startAutoRefresh()
    }
    #expect(await client.dependencies.autoRefresh.isRegistered == false)

    await world.advance(to: Self.lifetime)
    #expect(await world.refreshCount(settledAt: 0) == 0)
    _ = try await client.session
    #expect(await world.refreshCount(settledAt: 1) == 1)
  }

  @Test
  func disabledPolicyThrowsInsteadOfRefreshingAnExpiredSession() async throws {
    let world = World()
    let client = makeClient(world, autoRefresh: .disabled)
    try await client.seedSession(world.issueSession())

    await world.advance(to: Self.lifetime - 10)
    _ = try await client.session
    #expect(await world.refreshCount(settledAt: 0) == 0)

    await world.advance(to: Self.lifetime + 1)
    let error = await #expect(throws: AuthError.self) { try await client.session }
    #expect(error?.kind == .refreshDisabled)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    _ = try await client.refreshSession()
    #expect(await world.refreshCount(settledAt: 1) == 1)
  }

  @Test
  func refreshSessionIfNeededSkipsTheRequestWhileHalfTheLifetimeIsLeft() async throws {
    let world = World()
    let client = makeClient(world, autoRefresh: .manual)
    let issued = world.issueSession()
    try await client.seedSession(issued)

    await world.advance(to: Self.lifetime / 2 - 1)
    #expect(try await client.refreshSessionIfNeeded()?.accessToken == issued.accessToken)
    #expect(await world.refreshCount(settledAt: 0) == 0)

    await world.advance(to: Self.lifetime / 2 + 1)
    #expect(try await client.refreshSessionIfNeeded()?.accessToken == "refreshed-1-access")
    #expect(await world.refreshCount(settledAt: 1) == 1)
  }

  @Test
  func refreshSessionIfNeededReturnsNilWhenSignedOut() async throws {
    let world = World()
    let client = makeClient(world, autoRefresh: .manual)

    #expect(try await client.refreshSessionIfNeeded() == nil)
    #expect(await world.refreshCount(settledAt: 0) == 0)
  }

  #if !canImport(Darwin)
    @Test
    func openURLThrowsWhereThePlatformCannotOpenOne() async {
      let error = await #expect(throws: AuthError.self) {
        try await AuthPlatform.live.openURL(URL(string: "https://example.com")!)
      }
      #expect(error?.kind == .oauthFlowFailed)
    }

    @Test
    func eachDefaultStorageKeepsItsOwnValues() throws {
      try AuthClient.Configuration.defaultLocalStorage.store(key: "key", value: Data("a".utf8))
      #expect(try AuthClient.Configuration.defaultLocalStorage.retrieve(key: "key") == nil)
    }
  #endif

  private func makeClient(
    _ world: World,
    autoRefresh: AuthClient.AutoRefreshPolicy = .automatic,
    lifecycle: AsyncStream<AppLifecycleEvent> = AsyncStream {
      $0.yield(.foreground)
      $0.finish()
    }
  ) -> AuthClient {
    var platform = AuthPlatform.live
    platform.hasBackgroundState = true
    platform.lifecycleEvents = { lifecycle }
    return AuthClient(
      configuration: world.configuration(autoRefresh: autoRefresh, observesAppLifecycle: true),
      date: world.now,
      pkce: .live,
      platform: platform
    )
  }
}
