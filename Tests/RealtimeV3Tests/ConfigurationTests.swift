//
//  ConfigurationTests.swift
//  RealtimeV3Tests
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Testing

@testable import RealtimeV3

@Suite struct ConfigurationTests {
  @Test func defaultsMatchSpec() {
    let c = Configuration.default
    #expect(c.heartbeat == .seconds(25))
    #expect(c.joinTimeout == .seconds(10))
    #expect(c.broadcastAckTimeout == .seconds(5))
    #expect(c.protocolVersion == .v2)
  }

  @Test func neverPolicyGivesUpImmediately() {
    #expect(ReconnectionPolicy.never.nextDelay(0, RealtimeError.disconnected) == nil)
  }

  @Test func exponentialBackoffGrowsAndClamps() {
    let p = ReconnectionPolicy.exponentialBackoff(
      initial: .seconds(1), max: .seconds(30), jitter: 0)
    let d0 = p.nextDelay(0, RealtimeError.disconnected)
    let d1 = p.nextDelay(1, RealtimeError.disconnected)
    #expect(d0 == .seconds(1))
    #expect(d1 == .seconds(2))
  }

  @Test func exponentialBackoffClampsToMax() {
    let p = ReconnectionPolicy.exponentialBackoff(
      initial: .seconds(1), max: .seconds(30), jitter: 0)
    // attempt 10 → uncapped 1 * 2^10 = 1024s, must be clamped to 30s
    let d = p.nextDelay(10, RealtimeError.disconnected)
    #expect(d == .seconds(30))
  }

  @Test func fixedReturnsDelayThenNilAfterMaxAttempts() {
    let p = ReconnectionPolicy.fixed(.seconds(2), maxAttempts: 3)
    #expect(p.nextDelay(0, RealtimeError.disconnected) == .seconds(2))
    #expect(p.nextDelay(1, RealtimeError.disconnected) == .seconds(2))
    #expect(p.nextDelay(2, RealtimeError.disconnected) == .seconds(2))
    #expect(p.nextDelay(3, RealtimeError.disconnected) == nil)
  }

  @Test func fixedWithNilMaxAttemptsIsUnlimited() {
    let p = ReconnectionPolicy.fixed(.seconds(2), maxAttempts: nil)
    #expect(p.nextDelay(1000, RealtimeError.disconnected) == .seconds(2))
  }
}
