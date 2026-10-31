import Foundation

/// Caches one project's JWKS for `ttl` seconds and shares one fetch between concurrent callers.
///
/// A lookup for a `kid` that the fresh cache lacks forces a refetch, so rotated keys resolve. Each
/// unresolved fetch doubles the wait before the next forced refetch, from 1 second up to 16 seconds.
actor JWKSCache {
  private let ttl: TimeInterval
  private let fetch: @Sendable () async throws -> JWKS
  private let now: @Sendable () -> Date

  private var cached: (jwks: JWKS, fetchedAt: Date)?
  private var inFlight: Task<JWKS, any Error>?
  private var backoff: TimeInterval = 0
  private var forcedFetchAllowedAt: Date?

  init(
    ttl: TimeInterval = 600,
    fetch: @escaping @Sendable () async throws -> JWKS,
    now: @escaping @Sendable () -> Date
  ) {
    self.ttl = ttl
    self.fetch = fetch
    self.now = now
  }

  func key(for kid: String) async throws -> JWK? {
    guard let cached, now() < cached.fetchedAt.addingTimeInterval(ttl) else {
      return try await fetchKey(for: kid, forced: false)
    }
    if let key = cached.jwks.key(for: kid) {
      return key
    }
    if let forcedFetchAllowedAt, forcedFetchAllowedAt > now() {
      return nil
    }
    return try await fetchKey(for: kid, forced: true)
  }

  private func fetchKey(for kid: String, forced: Bool) async throws -> JWK? {
    if let inFlight {
      return try await inFlight.value.key(for: kid)
    }

    let task = Task { [fetch] in try await fetch() }
    inFlight = task
    defer { inFlight = nil }

    let jwks: JWKS
    do {
      jwks = try await task.value
    } catch {
      if forced {
        applyBackoff()
      }
      throw error
    }

    cached = (jwks, now())
    guard let key = jwks.key(for: kid) else {
      applyBackoff()
      return nil
    }
    backoff = 0
    forcedFetchAllowedAt = nil
    return key
  }

  private func applyBackoff() {
    backoff = backoff == 0 ? 1 : min(backoff * 2, 16)
    forcedFetchAllowedAt = now().addingTimeInterval(backoff)
  }
}

extension JWKS {
  fileprivate func key(for kid: String) -> JWK? {
    keys.first { $0.kid == kid }
  }
}
