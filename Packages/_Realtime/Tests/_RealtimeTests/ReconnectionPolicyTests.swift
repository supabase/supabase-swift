import Foundation
import Testing
@testable import _Realtime

@Suite struct ReconnectionPolicyTests {
  @Test func neverPolicyReturnsNilImmediately() {
    let policy = ReconnectionPolicy.never
    let delay = policy.nextDelay(1, URLError(.notConnectedToInternet))
    #expect(delay == nil)
  }

  @Test func fixedPolicyReturnsDelayUntilMax() {
    let policy = ReconnectionPolicy.fixed(.seconds(2), maxAttempts: 3)
    #expect(policy.nextDelay(1, URLError(.notConnectedToInternet)) == .seconds(2))
    #expect(policy.nextDelay(3, URLError(.notConnectedToInternet)) == .seconds(2))
    #expect(policy.nextDelay(4, URLError(.notConnectedToInternet)) == nil)
  }

  @Test func exponentialBackoffGrowsWithAttempts() {
    let policy = ReconnectionPolicy.exponentialBackoff(
      initial: .seconds(1), max: .seconds(16), jitter: 0
    )
    let d1 = policy.nextDelay(1, URLError(.notConnectedToInternet))!
    let d2 = policy.nextDelay(2, URLError(.notConnectedToInternet))!
    let d3 = policy.nextDelay(3, URLError(.notConnectedToInternet))!
    #expect(d1.components.seconds == 1)
    #expect(d2.components.seconds == 2)
    #expect(d3.components.seconds == 4)
  }

  @Test func exponentialBackoffCapsAtMax() {
    let policy = ReconnectionPolicy.exponentialBackoff(
      initial: .seconds(1), max: .seconds(5), jitter: 0
    )
    let d10 = policy.nextDelay(10, URLError(.notConnectedToInternet))!
    #expect(d10.components.seconds <= 5)
  }

  @Test func exponentialBackoffHandlesSubSecondInitial() {
    let policy = ReconnectionPolicy.exponentialBackoff(
      initial: .milliseconds(500), max: .seconds(16), jitter: 0
    )
    let d1 = policy.nextDelay(1, URLError(.notConnectedToInternet))!
    // Should be ~0.5 seconds, not zero
    #expect(d1 >= .milliseconds(400) && d1 <= .milliseconds(600))
  }

  @Test func fixedPolicyWithNoMaxAttemptsRetriresForever() {
    let policy = ReconnectionPolicy.fixed(.seconds(1))
    #expect(policy.nextDelay(1000, URLError(.notConnectedToInternet)) == .seconds(1))
  }
}
