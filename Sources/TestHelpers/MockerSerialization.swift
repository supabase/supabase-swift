//
//  MockerSerialization.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/07/26.
//

package import Testing

/// A process-wide mutual-exclusion queue, used by ``MockerSerializedTrait`` to serialize every
/// test wrapped by `.mockerSerialized` against every other one, even across test *targets*.
private actor MockerGate {
  static let shared = MockerGate()

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

/// Mocker's mock registry is process-global, and Swift Testing's built-in `.serialized` suite
/// trait only serializes a suite's own (possibly nested) tests -- it does not prevent that suite
/// from running concurrently with an unrelated suite in a *different* test target that also
/// happens to use Mocker. Without this trait, two Mocker-backed Swift Testing suites from
/// different targets (e.g. StorageTests and PostgRESTTests) can register and look up stubs on the
/// shared registry at the same time, causing spurious "no matching stub" failures that don't
/// reproduce when either target's tests run alone.
///
/// `isRecursive` is `false`: apply `.mockerSerialized` directly to every concrete Mocker-backed
/// `@Suite`, not to an enclosing namespace enum (unlike `.serialized`, marking this trait
/// recursive on an otherwise test-less namespace containing only cross-file `extension`-declared
/// nested suites triggers a stack overflow in Swift Testing's trait-application graph).
package struct MockerSerializedTrait: SuiteTrait, TestScoping {
  package var isRecursive: Bool { false }

  package func provideScope(
    for test: Test, testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    try await MockerGate.shared.withLock {
      try await function()
    }
  }
}

extension Trait where Self == MockerSerializedTrait {
  /// Apply directly to each `@Suite` that registers Mocker stubs (alongside `.serialized` on its
  /// enclosing namespace, if any), so it can't interleave with any other suite -- in this or
  /// another test target -- that also uses this trait.
  package static var mockerSerialized: Self { MockerSerializedTrait() }
}
