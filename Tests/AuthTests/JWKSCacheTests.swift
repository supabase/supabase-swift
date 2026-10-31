import ConcurrencyExtras
import Foundation
import Testing

@testable import Auth

@Suite
struct JWKSCacheTests {
  private struct FetchError: Error {}

  private static let k1 = jwk(kid: "k1")
  private static let k2 = jwk(kid: "k2")

  private static func jwk(kid: String) -> JWK {
    JWK(
      kty: "RSA",
      keyOps: nil,
      alg: "RS256",
      kid: kid,
      n: "AQAB",
      e: "AQAB",
      crv: nil,
      x: nil,
      y: nil,
      k: nil
    )
  }

  private final class Fixture: Sendable {
    let clock: LockIsolated<Date>
    let fetchCount: LockIsolated<Int>
    let keys: LockIsolated<[JWK]>
    let cache: JWKSCache

    init(
      keys: [JWK] = [JWKSCacheTests.k1],
      gate: (@Sendable (Int) async -> Void)? = nil,
      failure: (@Sendable (Int) -> Bool)? = nil
    ) {
      let clock = LockIsolated(Date(timeIntervalSince1970: 0))
      let fetchCount = LockIsolated(0)
      let keys = LockIsolated(keys)
      self.clock = clock
      self.fetchCount = fetchCount
      self.keys = keys
      cache = JWKSCache(
        fetch: {
          let count = fetchCount.withValue {
            $0 += 1
            return $0
          }
          await gate?(count)
          if failure?(count) == true {
            throw FetchError()
          }
          return JWKS(keys: keys.value)
        },
        now: { clock.value }
      )
    }

    func advance(to seconds: TimeInterval) {
      clock.setValue(Date(timeIntervalSince1970: seconds))
    }
  }

  private struct Gate: Sendable {
    private let isOpen = LockIsolated(false)

    func open() {
      isOpen.setValue(true)
    }

    func wait() async {
      while !isOpen.value {
        await Task.yield()
      }
    }
  }

  private static func waitUntil(_ condition: @Sendable () -> Bool) async {
    while !condition() {
      await Task.yield()
    }
    await Task.megaYield()
  }

  @Test
  func freshCacheHitDoesNotFetch() async throws {
    let fixture = Fixture()

    #expect(try await fixture.cache.key(for: "k1") == Self.k1)
    #expect(try await fixture.cache.key(for: "k1") == Self.k1)
    #expect(fixture.fetchCount.value == 1)
  }

  @Test
  func staleCacheRefetches() async throws {
    let fixture = Fixture()

    _ = try await fixture.cache.key(for: "k1")
    fixture.advance(to: 599)
    _ = try await fixture.cache.key(for: "k1")
    #expect(fixture.fetchCount.value == 1)

    fixture.advance(to: 600)
    #expect(try await fixture.cache.key(for: "k1") == Self.k1)
    #expect(fixture.fetchCount.value == 2)
  }

  @Test
  func concurrentMissesShareOneFetch() async throws {
    let gate = Gate()
    let fixture = Fixture(gate: { _ in await gate.wait() })
    let started = LockIsolated(0)

    try await withThrowingTaskGroup(of: JWK?.self) { group in
      for _ in 0..<20 {
        group.addTask {
          started.withValue { $0 += 1 }
          return try await fixture.cache.key(for: "k1")
        }
      }
      await Self.waitUntil { started.value == 20 && fixture.fetchCount.value >= 1 }
      gate.open()

      for try await key in group {
        #expect(key == Self.k1)
      }
    }
    #expect(fixture.fetchCount.value == 1)
  }

  @Test
  func concurrentUnknownKidFetchesOnce() async throws {
    let gate = Gate()
    let fixture = Fixture(gate: { count in
      if count >= 2 {
        await gate.wait()
      }
    })
    _ = try await fixture.cache.key(for: "k1")
    let started = LockIsolated(0)

    try await withThrowingTaskGroup(of: JWK?.self) { group in
      for _ in 0..<20 {
        group.addTask {
          started.withValue { $0 += 1 }
          return try await fixture.cache.key(for: "unknown")
        }
      }
      await Self.waitUntil { started.value == 20 && fixture.fetchCount.value >= 2 }
      gate.open()

      for try await key in group {
        #expect(key == nil)
      }
    }
    #expect(fixture.fetchCount.value == 2)
  }

  @Test
  func unknownKidRefetchResolvesRotatedKey() async throws {
    let fixture = Fixture()
    _ = try await fixture.cache.key(for: "k1")

    fixture.keys.setValue([Self.k1, Self.k2])
    #expect(try await fixture.cache.key(for: "k2") == Self.k2)
    #expect(fixture.fetchCount.value == 2)
  }

  @Test
  func backoffDoublesAndCaps() async throws {
    let fixture = Fixture()
    _ = try await fixture.cache.key(for: "k1")
    #expect(try await fixture.cache.key(for: "unknown") == nil)
    var expectedFetches = 2
    #expect(fixture.fetchCount.value == expectedFetches)

    var lastForcedFetch: TimeInterval = 0
    for wait: TimeInterval in [1, 2, 4, 8, 16, 16] {
      let nextForcedFetch = lastForcedFetch + wait
      for blockedTime in [lastForcedFetch + wait / 2, nextForcedFetch - 0.25] {
        fixture.advance(to: blockedTime)
        #expect(try await fixture.cache.key(for: "unknown") == nil)
        #expect(fixture.fetchCount.value == expectedFetches)
      }

      fixture.advance(to: nextForcedFetch)
      #expect(try await fixture.cache.key(for: "unknown") == nil)
      expectedFetches += 1
      #expect(fixture.fetchCount.value == expectedFetches)
      lastForcedFetch = nextForcedFetch
    }
    #expect(lastForcedFetch == 47)
  }

  @Test
  func backoffResetsOnResolve() async throws {
    let fixture = Fixture()
    _ = try await fixture.cache.key(for: "k1")
    #expect(try await fixture.cache.key(for: "unknown") == nil)
    #expect(fixture.fetchCount.value == 2)

    fixture.advance(to: 1)
    fixture.keys.setValue([Self.k1, Self.k2])
    #expect(try await fixture.cache.key(for: "k2") == Self.k2)
    #expect(fixture.fetchCount.value == 3)

    #expect(try await fixture.cache.key(for: "unknown") == nil)
    #expect(fixture.fetchCount.value == 4)
  }

  @Test
  func emptyKeySetReturnsNil() async throws {
    let fixture = Fixture(keys: [])

    #expect(try await fixture.cache.key(for: "k1") == nil)
    #expect(fixture.fetchCount.value == 1)
  }

  @Test
  func failedFetchIsNotCached() async throws {
    let gate = Gate()
    let failing = LockIsolated(true)
    let fixture = Fixture(
      gate: { _ in await gate.wait() },
      failure: { _ in failing.value }
    )
    let started = LockIsolated(0)

    await withTaskGroup(of: Bool.self) { group in
      for _ in 0..<5 {
        group.addTask {
          started.withValue { $0 += 1 }
          do {
            _ = try await fixture.cache.key(for: "k1")
            return false
          } catch {
            return error is FetchError
          }
        }
      }
      await Self.waitUntil { started.value == 5 && fixture.fetchCount.value >= 1 }
      gate.open()

      for await threw in group {
        #expect(threw)
      }
    }
    let failedFetches = fixture.fetchCount.value

    failing.setValue(false)
    #expect(try await fixture.cache.key(for: "k1") == Self.k1)
    #expect(fixture.fetchCount.value == failedFetches + 1)
  }
}
