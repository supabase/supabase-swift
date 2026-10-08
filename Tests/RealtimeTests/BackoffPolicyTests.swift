//
//  BackoffPolicyTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 06/10/26.
//

import Testing

@testable import Realtime

@Suite
struct BackoffPolicyTests {
  @Test(arguments: [(1, 1), (2, 2), (3, 5), (4, 10), (5, 10), (50, 10)])
  func stepsClampToTheLastStep(attempt: Int, seconds: Int) {
    let policy = BackoffPolicy.steps([.seconds(1), .seconds(2), .seconds(5), .seconds(10)])

    #expect(policy.delay(forAttempt: attempt) == .seconds(seconds))
  }

  @Test
  func emptyStepsNeverWait() {
    #expect(BackoffPolicy.steps([]).delay(forAttempt: 3) == .zero)
  }

  @Test(arguments: [(1, 1.0), (2, 2.0), (3, 4.0), (5, 16.0), (6, 30.0), (40, 30.0)])
  func fullJitterDrawsFromZeroToTheCappedExponential(attempt: Int, upper: Double) {
    let policy = BackoffPolicy.fullJitter(base: .seconds(1), cap: .seconds(30))

    let max = policy.delay(forAttempt: attempt, random: { $0.upperBound })
    let min = policy.delay(forAttempt: attempt, random: { $0.lowerBound })

    #expect(max == .seconds(upper))
    #expect(min == .zero)
  }

  @Test
  func attemptsBelowOneCountAsTheFirst() {
    let policy = BackoffPolicy.fullJitter(base: .seconds(1), cap: .seconds(30))

    #expect(policy.delay(forAttempt: 0, random: { $0.upperBound }) == .seconds(1))
    #expect(policy.delay(forAttempt: -3, random: { $0.upperBound }) == .seconds(1))
  }
}
