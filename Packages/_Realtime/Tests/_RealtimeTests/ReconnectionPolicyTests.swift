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
}
