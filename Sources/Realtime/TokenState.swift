//
//  TokenState.swift
//  Realtime
//
//  Created by Guilherme Souza on 06/10/26.
//

import Foundation
import Helpers

/// The access token channels join with, and the bookkeeping that keeps refreshes in order.
struct TokenState: Sendable {
  private(set) var token: String?
  /// The `exp` claim of ``token`` when it is a JWT.
  private(set) var expiresAt: Date?
  private(set) var generation = 0

  init() {}

  /// Marks the start of a refresh. Only a result applied with this generation counts.
  mutating func beginRefresh() -> Int {
    generation += 1
    return generation
  }

  /// Stores `token` and returns whether it changed. A `nil`, an unchanged token, or a result
  /// from an older refresh leaves the state as it was.
  mutating func apply(_ token: String?, generation: Int) -> Bool {
    guard generation == self.generation, let token, token != self.token else { return false }
    self.token = token
    expiresAt = (JWT.decodePayload(token)?["exp"] as? TimeInterval).map(
      Date.init(timeIntervalSince1970:))
    return true
  }

  /// How long until the token should be refreshed: `leeway` before `exp`, never negative.
  /// `nil` when the token has no expiry to plan around.
  func refreshDelay(now: Date, leeway: Duration) -> Duration? {
    guard let expiresAt else { return nil }
    let remaining = Duration.seconds(Int(expiresAt.timeIntervalSince(now).rounded()))
    return max(remaining - leeway, .zero)
  }
}
