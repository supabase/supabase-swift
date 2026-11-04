import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Auth

/// Records the name of the task that sleeps on it, then sleeps on `base`.
private struct NameCapturingClock<Base: Clock<Duration>>: Clock {
  typealias Instant = Base.Instant

  let base: Base
  let names: LockIsolated<[String?]>

  var now: Instant { base.now }
  var minimumResolution: Duration { base.minimumResolution }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
      names.withValue { $0.append(Task.name) }
    }
    try await base.sleep(until: deadline, tolerance: tolerance)
  }
}

@Suite(.timeLimit(.minutes(1)))
struct TaskNamingTests {
  @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
  @Test
  func theAutoRefreshTaskIsNamedTheRefresher() async throws {
    let race = Race()
    let names = LockIsolated<[String?]>([])
    race.answerSignIn { [race] _ in race.issue("named") }
    let client = race.makeClient(
      autoRefresh: .automatic, clock: NameCapturingClock(base: race.clock, names: names))

    try await client.signIn(email: "user@example.com", password: "secret")
    await race.waitForTheScheduledRefresh()

    #expect(names.value.contains("supabase.auth.refresher"))
  }

  @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
  @Test
  func theLifecycleObserverIsNamedTheLifecycle() async throws {
    let race = Race()
    let name = LockIsolated<String??>(nil)
    _ = race.makeClient(lifecycleEvents: {
      name.setValue(.some(Task.name))
      return AsyncStream { $0.finish() }
    })

    #expect(await waitUntil { name.value != nil })
    #expect(name.value == .some("supabase.auth.lifecycle"))
  }
}
