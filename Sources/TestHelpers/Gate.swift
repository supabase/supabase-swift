//
//  Gate.swift
//  TestHelpers
//

import ConcurrencyExtras
import Foundation

/// Holds every caller of ``pass()`` until ``open()``, and lets a test wait for arrivals.
///
/// A waiting task that is cancelled stops waiting, so a gate that never opens, or that gets fewer
/// arrivals than a test waits for, fails the test at its time limit instead of hanging the run.
package final class Gate: Sendable {
  private struct State {
    var arrivals = 0
    var isOpen: Bool
    var held: [UUID: CheckedContinuation<Void, Never>] = [:]
    var watchers: [UUID: (count: Int, continuation: CheckedContinuation<Void, Never>)] = [:]
  }

  private let state: LockIsolated<State>

  package init(isOpen: Bool = false) {
    state = LockIsolated(State(isOpen: isOpen))
  }

  /// Counts an arrival and returns once the gate is open.
  package func pass() async {
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { request in
        let resumed = state.withValue { state in
          state.arrivals += 1
          let arrived = state.arrivals
          var resumed = state.watchers.values.filter { $0.count <= arrived }.map(\.continuation)
          state.watchers = state.watchers.filter { $0.value.count > arrived }
          // A cancel that lands before this point finds nothing to resume.
          if state.isOpen || Task.isCancelled {
            resumed.append(request)
          } else {
            state.held[id] = request
          }
          return resumed
        }
        for continuation in resumed { continuation.resume() }
      }
    } onCancel: {
      state.withValue { $0.held.removeValue(forKey: id) }?.resume()
    }
  }

  /// Returns once `count` callers in total reached the gate.
  package func arrivals(_ count: Int) async {
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { watcher in
        let isWaiting = state.withValue { state in
          // A cancel that lands before this point finds nothing to resume.
          guard state.arrivals < count, !Task.isCancelled else { return false }
          state.watchers[id] = (count, watcher)
          return true
        }
        if !isWaiting { watcher.resume() }
      }
    } onCancel: {
      state.withValue { $0.watchers.removeValue(forKey: id) }?.continuation.resume()
    }
  }

  /// Lets every held caller and every later caller through.
  package func open() {
    let held = state.withValue { state in
      state.isOpen = true
      defer { state.held = [:] }
      return Array(state.held.values)
    }
    for request in held { request.resume() }
  }
}
