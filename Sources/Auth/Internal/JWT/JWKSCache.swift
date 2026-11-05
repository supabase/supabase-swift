import Foundation

/// Caches one project's JWKS for `ttl` and shares one fetch between concurrent callers.
///
/// A lookup for a `kid` that the fresh cache lacks forces a refetch, so rotated keys resolve. Each
/// unresolved fetch doubles the wait before the next forced refetch, from 1 second up to 16 seconds.
/// A cancelled caller stops waiting at once; the shared fetch keeps running for the other callers.
actor JWKSCache {
  private let ttl: Duration
  private let fetch: @Sendable () async throws -> JWKS
  private let now: @Sendable () -> Date

  private var cached: (jwks: JWKS, fetchedAt: Date)?
  private var inFlight: Task<JWKS, any Error>?
  private var backoff: Duration = .zero
  private var forcedFetchAllowedAt: Date?

  /// The number of callers that have started or joined a fetch. Tests read it to know that
  /// concurrent callers share one fetch before they let it finish.
  private(set) var joinedFetchCount = 0

  init(
    ttl: Duration = .seconds(600),
    fetch: @escaping @Sendable () async throws -> JWKS,
    now: @escaping @Sendable () -> Date
  ) {
    self.ttl = ttl
    self.fetch = fetch
    self.now = now
  }

  func key(for kid: String) async throws -> JWK? {
    guard let cached, now() < cached.fetchedAt.adding(ttl) else {
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
    let task = inFlight ?? startFetch(for: kid, forced: forced)
    joinedFetchCount += 1
    return try await cancellableValue(of: task).key(for: kid)
  }

  // The task, not the first caller, records the result, so a cancelled caller cannot skip it.
  private func startFetch(for kid: String, forced: Bool) -> Task<JWKS, any Error> {
    let task = Task { [fetch] in
      let result: Result<JWKS, any Error>
      do {
        result = .success(try await fetch())
      } catch {
        result = .failure(error)
      }
      finishFetch(result, kid: kid, forced: forced)
      return try result.get()
    }
    inFlight = task
    return task
  }

  private func finishFetch(_ result: Result<JWKS, any Error>, kid: String, forced: Bool) {
    inFlight = nil
    switch result {
    case .success(let jwks):
      cached = (jwks, now())
      if jwks.key(for: kid) == nil {
        applyBackoff()
      } else {
        backoff = .zero
        forcedFetchAllowedAt = nil
      }
    case .failure:
      if forced {
        applyBackoff()
      }
    }
  }

  private func applyBackoff() {
    backoff = backoff == .zero ? .seconds(1) : min(backoff * 2, .seconds(16))
    forcedFetchAllowedAt = now().adding(backoff)
  }
}

extension JWKS {
  func key(for kid: String) -> JWK? {
    keys.first { $0.kid == kid }
  }
}
