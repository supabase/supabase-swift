//
//  WaiterTable.swift
//  Realtime
//

import Foundation

/// The callers the shell has parked until the core resolves them with
/// ``RealtimeCore/Effect/resume(_:_:)``. The actor owns the table, so it needs no lock.
struct WaiterTable {
  private var lastID: UInt64 = 0
  private var continuations: [WaiterID: CheckedContinuation<Void, any Error>] = [:]

  mutating func next() -> WaiterID {
    lastID += 1
    return WaiterID(rawValue: lastID)
  }

  mutating func park(_ id: WaiterID, _ continuation: CheckedContinuation<Void, any Error>) {
    assert(continuations[id] == nil, "Waiter \(id.rawValue) is already parked")
    continuations[id] = continuation
  }

  /// Ends the wait for `id`. A `.cancelled` outcome throws `CancellationError`. An id that is not
  /// parked, because it already resumed, is ignored.
  mutating func resume(_ id: WaiterID, with outcome: WaiterOutcome) {
    guard let continuation = continuations.removeValue(forKey: id) else { return }
    switch outcome {
    case .success:
      continuation.resume()
    case .failure(let error):
      continuation.resume(throwing: error)
    case .cancelled:
      continuation.resume(throwing: CancellationError())
    }
  }

  /// Throws `error` to every parked caller and leaves the table empty.
  mutating func failAll(with error: any Error) {
    let parked = continuations
    continuations.removeAll()
    for continuation in parked.values {
      continuation.resume(throwing: error)
    }
  }
}
