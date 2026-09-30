//
//  MainSerialExecutorSerialization.swift
//  Supabase
//
//  Created by Guilherme Souza on 04/08/26.
//

package import Testing

/// A process-wide mutual-exclusion queue, used by ``MainSerialExecutorSerializedTrait`` to
/// serialize every test wrapped by `.mainSerialExecutorSerialized` against every other one, even
/// across test *targets*.
private actor MainSerialExecutorGate {
  static let shared = MainSerialExecutorGate()

  private var isBusy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  private func acquire() async {
    guard isBusy else {
      isBusy = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  private func release() {
    guard waiters.isEmpty else {
      waiters.removeFirst().resume()
      return
    }
    isBusy = false
  }

  func withLock<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
    await acquire()
    defer { release() }
    return try await body()
  }
}

/// `withMainSerialExecutor` (ConcurrencyExtras) mutates a process-global flag
/// (`uncheckedUseMainSerialExecutor`) to force deterministic task scheduling within its closure.
/// Swift Testing's built-in `.serialized` suite trait only serializes a suite's own (possibly
/// nested) tests -- it does not prevent that suite from running concurrently with an unrelated
/// suite in a *different* test target that also calls `withMainSerialExecutor`. Without this
/// trait, two such suites can flip the same global out from under each other mid-test, causing
/// nondeterministic scheduling and cascading failures that don't reproduce when either target's
/// tests run alone.
///
/// `isRecursive` is `false`, mirroring `MockerSerializedTrait`: apply directly to every concrete
/// `@Suite` that calls `withMainSerialExecutor`, not to an enclosing namespace enum.
package struct MainSerialExecutorSerializedTrait: SuiteTrait, TestScoping {
  package var isRecursive: Bool { false }

  package func provideScope(
    for test: Test, testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    try await MainSerialExecutorGate.shared.withLock {
      try await function()
    }
  }
}

extension Trait where Self == MainSerialExecutorSerializedTrait {
  /// Apply directly to each `@Suite` that calls `withMainSerialExecutor`, so it can't interleave
  /// with any other suite -- in this or another test target -- that also uses this trait.
  package static var mainSerialExecutorSerialized: Self { MainSerialExecutorSerializedTrait() }
}
