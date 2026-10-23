//
//  ReconnectPolicy.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import Foundation
import Phoenix

/// A server that accepts and then drops every connection resets `attempt`, so the status and
/// close-code rules, not the cap, stop that case.
///
/// - Parameters:
///   - attempt: The failures since the last successful open, this one included.
///   - random: The jitter source. Tests pin it to make the wait exact.
func reconnectDecision(
  httpStatus: Int?,
  closeCode: Int?,
  attempt: Int,
  maxAttempts: Int,
  base: Duration,
  random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
) -> ReconnectDecision {
  if let httpStatus, [401, 403, 404].contains(httpStatus) { return .stop }
  if let closeCode, closeCode >= 4000 { return .stop }
  if attempt >= maxAttempts { return .stop }
  let backoff = BackoffPolicy.fullJitter(base: max(base, .zero), cap: .seconds(30))
  return .retry(after: backoff.delay(forAttempt: attempt, random: random))
}
