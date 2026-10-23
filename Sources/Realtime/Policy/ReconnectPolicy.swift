//
//  ReconnectPolicy.swift
//  Realtime
//
//  Created by Guilherme Souza on 23/10/26.
//

import Foundation
import Helpers
import Phoenix

/// A server that accepts and then drops every connection resets `attempt`, so the status and
/// close-code rules, not the cap, stop that case.
///
/// - Parameter attempt: The failures since the last successful open, this one included.
func reconnectDecision(
  httpStatus: Int?,
  closeCode: Int?,
  attempt: Int,
  maxAttempts: Int,
  base: Duration
) -> ReconnectDecision {
  if let httpStatus, [401, 403, 404].contains(httpStatus) { return .stop }
  if let closeCode, closeCode >= 4000 { return .stop }
  if attempt >= maxAttempts { return .stop }
  let cap = Duration.seconds(30)
  let backoff = RetryPolicy(baseDelay: min(max(base, .zero), cap), maxDelay: cap)
  return .retry(after: backoff.backoffDelay(retry: attempt))
}
