//
//  RetryPolicyTests.swift
//  Helpers
//
//  Created by Guilherme Souza on 14/09/26.
//

import Foundation
import Testing

@testable import Helpers

@Suite
struct RetryPolicyTests {
  let now = Date(timeIntervalSince1970: 1_445_412_480)  // Wed, 21 Oct 2015 07:28:00 GMT

  @Test
  func defaultsMatchTheAgreedShape() {
    let policy = RetryPolicy.default
    #expect(policy.maxAttempts == 3)
    #expect(policy.baseDelay == .milliseconds(500))
    #expect(policy.maxDelay == .seconds(20))
    #expect(
      policy.retryableStatuses == [408, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524, 530])
    #expect(policy.retryableMethods == [.get, .head, .options])
  }

  @Test
  func disabledMakesExactlyOneAttempt() {
    #expect(RetryPolicy.disabled.maxAttempts == 1)
  }

  @Test
  func backoffIsEqualJitterBetweenHalfTheCapAndTheCap() {
    let policy = RetryPolicy(baseDelay: .seconds(1), maxDelay: .seconds(60))
    for _ in 0..<50 {
      #expect((Duration.milliseconds(500)...(.seconds(1))).contains(policy.backoffDelay(retry: 1)))
      #expect((Duration.seconds(2)...(.seconds(4))).contains(policy.backoffDelay(retry: 3)))
    }
  }

  @Test
  func backoffNeverExceedsMaxDelayEvenForHugeAttemptNumbers() {
    let policy = RetryPolicy(baseDelay: .seconds(1), maxDelay: .seconds(5))
    for _ in 0..<50 {
      #expect(policy.backoffDelay(retry: 10) <= .seconds(5))
      #expect(policy.backoffDelay(retry: 500) <= .seconds(5))
    }
  }

  @Test
  func backoffDoesNotOverflowForAHugeBaseDelay() {
    // `baseDelay * 2^30` would overflow `Duration`; the cap must be applied before multiplying.
    let policy = RetryPolicy(baseDelay: .seconds(Int.max), maxDelay: .seconds(5))
    #expect(policy.backoffDelay(retry: 40) <= .seconds(5))
  }

  @Test
  func zeroBaseDelayYieldsZeroBackoff() {
    let policy = RetryPolicy(baseDelay: .zero)
    #expect(policy.backoffDelay(retry: 3) == .zero)
  }

  @Test
  func retryAfterDeltaSeconds() {
    #expect(RetryPolicy.retryAfterDelay("3", now: now) == .seconds(3))
  }

  @Test
  func retryAfterHTTPDate() {
    #expect(
      RetryPolicy.retryAfterDelay("Wed, 21 Oct 2015 07:28:10 GMT", now: now) == .seconds(10))
  }

  @Test
  func retryAfterHTTPDateNotInTheFutureFallsBackToBackoff() {
    // A stale date carries no timing information; a zero wait would make every client that saw
    // it replay at the same instant, which is what the jittered backoff exists to prevent.
    let past = "Wed, 21 Oct 2015 07:27:00 GMT"
    let exactlyNow = "Wed, 21 Oct 2015 07:28:00 GMT"
    #expect(RetryPolicy.retryAfterDelay(past, now: now) == nil)
    #expect(RetryPolicy.retryAfterDelay(exactlyNow, now: now) == nil)

    let policy = RetryPolicy(baseDelay: .seconds(1), maxDelay: .seconds(20))
    let backoff = Duration.milliseconds(500)...(.seconds(1))
    #expect(backoff.contains(policy.delay(retry: 1, retryAfter: past, now: now)))
  }

  @Test
  func retryAfterGarbageIsIgnored() {
    #expect(RetryPolicy.retryAfterDelay("soon", now: now) == nil)
    #expect(RetryPolicy.retryAfterDelay("-5", now: now) == nil)
  }

  @Test
  func retryAfterIsHonouredUpToMaxDelay() {
    let policy = RetryPolicy(baseDelay: .seconds(1), maxDelay: .seconds(20))
    #expect(policy.delay(retry: 1, retryAfter: "7", now: now) == .seconds(7))
    #expect(policy.delay(retry: 1, retryAfter: "3600", now: now) == .seconds(20))
  }

  @Test
  func missingOrInvalidRetryAfterFallsBackToBackoff() {
    let policy = RetryPolicy(baseDelay: .seconds(1), maxDelay: .seconds(20))
    let backoff = Duration.milliseconds(500)...(.seconds(1))
    #expect(backoff.contains(policy.delay(retry: 1, retryAfter: nil, now: now)))
    #expect(backoff.contains(policy.delay(retry: 1, retryAfter: "soon", now: now)))
  }
}
