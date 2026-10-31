import ConcurrencyExtras
import Foundation
import TestHelpers
import Testing

@testable import Auth

@Suite
struct RedirectDeduplicatorTests {
  private struct E: Error, Equatable {}

  @Test
  func concurrentCallsForOneKeyRunTheOperationOnce() async throws {
    let deduplicator = RedirectDeduplicator<Int>()
    let gate = Gate()
    let runs = LockIsolated(0)
    let operation: @Sendable () async throws -> Int = {
      runs.withValue { $0 += 1 }
      await gate.pass()
      return 7
    }

    async let first = deduplicator.value(for: "code", operation)
    async let second = deduplicator.value(for: "code", operation)
    await gate.arrivals(1)
    gate.open()

    let values = try await [first, second]
    #expect(values == [7, 7])
    #expect(runs.value == 1)
  }

  @Test
  func aLaterCallReturnsTheCachedValue() async throws {
    let deduplicator = RedirectDeduplicator<Int>()
    let runs = LockIsolated(0)
    let operation: @Sendable () async throws -> Int = {
      runs.withValue { $0 += 1 }
      return 1
    }

    let first = try await deduplicator.value(for: "code", operation)
    let second = try await deduplicator.value(for: "code", operation)

    #expect(first == 1)
    #expect(second == 1)
    #expect(runs.value == 1)
  }

  @Test
  func aFailureIsReplayed() async throws {
    let deduplicator = RedirectDeduplicator<Int>()
    let runs = LockIsolated(0)
    let operation: @Sendable () async throws -> Int = {
      runs.withValue { $0 += 1 }
      throw E()
    }

    await #expect(throws: E.self) { try await deduplicator.value(for: "code", operation) }
    await #expect(throws: E.self) { try await deduplicator.value(for: "code", operation) }
    #expect(runs.value == 1)
  }

  @Test
  func theOldestKeyIsDroppedBeyondCapacity() async throws {
    let deduplicator = RedirectDeduplicator<Int>(capacity: 2)
    let runs = LockIsolated<[String]>([])
    func run(_ key: String) async throws {
      _ = try await deduplicator.value(for: key) {
        runs.withValue { $0.append(key) }
        return 0
      }
    }

    for key in ["a", "b", "c", "a"] { try await run(key) }

    #expect(runs.value == ["a", "b", "c", "a"])
  }

  @Test
  func removeAllForgetsTheCachedValues() async throws {
    let deduplicator = RedirectDeduplicator<Int>()
    let runs = LockIsolated(0)
    let operation: @Sendable () async throws -> Int = {
      runs.withValue {
        $0 += 1
        return $0
      }
    }

    let first = try await deduplicator.value(for: "code", operation)
    await deduplicator.removeAll()
    let second = try await deduplicator.value(for: "code", operation)

    #expect(first == 1)
    #expect(second == 2)
  }
}
