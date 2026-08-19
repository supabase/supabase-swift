//
//  DeferredRequestSnapshots.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/08/26.
//

package import Foundation
package import InlineSnapshotTesting

/// A request snapshot whose comparison has to be deferred until the test's own task.
///
/// Mocker invokes `onRequestHandler` from the URL-loading queue, not from the task running the
/// test. Swift Testing resolves the current test from task-local state, so an issue recorded from
/// that handler has no test to attach to and is silently dropped -- which made every
/// `Mock.snapshotRequest` assertion in the package pass regardless of the request. Capturing the
/// request there and comparing it later, inside ``MockerSerializedTrait``, puts the comparison back
/// in a context where a failure is attributed to the test.
struct PendingRequestSnapshot {
  /// The expected snapshot, already evaluated at the call site. `nil` means no snapshot has been
  /// recorded yet, which `assertInlineSnapshot` treats as a request to record one.
  var expected: String?
  var message: String
  var isRecording: SnapshotTestingConfiguration.Record?
  var timeout: TimeInterval
  var syntaxDescriptor: InlineSnapshotSyntaxDescriptor
  var fileID: StaticString
  var filePath: StaticString
  var function: StaticString
  var line: UInt
  var column: UInt

  /// Filled in by the Mocker request handler. Stays `nil` if the mock is never matched.
  var request: URLRequest?
}

/// Process-global store of snapshots awaiting comparison.
///
/// `@unchecked Sendable` with an explicit lock: `PendingRequestSnapshot` holds non-`Sendable`
/// snapshot-testing values, and every reader and writer is already serialized by
/// ``MockerSerializedTrait``, which holds a process-wide gate for the whole test.
final class PendingRequestSnapshotStore: @unchecked Sendable {
  static let shared = PendingRequestSnapshotStore()

  private let lock = NSLock()
  private var pending: [Int: PendingRequestSnapshot] = [:]
  private var nextToken = 0

  /// Registers a snapshot to compare once the test body has finished.
  ///
  /// Tokens are monotonic and never reused. Mocker's registry is process-global and a stub can
  /// outlive the test that registered it, so a handler may fire after its expectation has been
  /// drained. With a unique token that late arrival finds no entry and is dropped; with array
  /// indices it would have attached its request to whichever expectation had since taken that
  /// index, failing an unrelated test at random.
  func register(_ snapshot: PendingRequestSnapshot) -> Int {
    lock.lock()
    defer { lock.unlock() }
    let token = nextToken
    nextToken += 1
    pending[token] = snapshot
    return token
  }

  /// Attaches the request Mocker saw to a previously registered snapshot. A token that is no
  /// longer pending is ignored.
  func attach(_ request: URLRequest, to token: Int) {
    lock.lock()
    defer { lock.unlock() }
    pending[token]?.request = request
  }

  /// Removes and returns everything registered so far, oldest first.
  func drain() -> [PendingRequestSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    let drained = pending.sorted { $0.key < $1.key }.map(\.value)
    pending = [:]
    return drained
  }
}

/// Compares every deferred snapshot registered during the current test.
///
/// Called from ``MockerSerializedTrait`` after the test body returns, so `assertInlineSnapshot`
/// runs with a current test and a mismatch actually fails.
///
/// Snapshots whose mock was never matched are skipped rather than failed: a suite may legitimately
/// register a mock for a request a given test does not make.
package func assertDeferredRequestSnapshots() {
  for snapshot in PendingRequestSnapshotStore.shared.drain() {
    guard let request = snapshot.request else { continue }
    assertInlineSnapshot(
      of: request,
      as: ._curl,
      message: snapshot.message,
      record: snapshot.isRecording,
      timeout: snapshot.timeout,
      syntaxDescriptor: snapshot.syntaxDescriptor,
      matches: snapshot.expected.map { expected in { expected } },
      fileID: snapshot.fileID,
      file: snapshot.filePath,
      function: snapshot.function,
      line: snapshot.line,
      column: snapshot.column
    )
  }
}
