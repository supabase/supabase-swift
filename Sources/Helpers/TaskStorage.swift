//
//  TaskStorage.swift
//  Helpers
//
//  Created by Guilherme Souza on 19/10/26.
//

/// Owns unstructured tasks by the reason they exist, so starting a new run of some work cancels
/// the previous run in one call and nothing outlives its owner.
///
/// Not `Sendable` on purpose: an instance lives inside one isolation domain (an actor's stored
/// property) and is only touched from there.
package final class TaskStorage<Location: Hashable> {
  private var tasks: [Location: [Task<Void, Never>]] = [:]

  package init() {}

  /// The tasks currently stored at `location`, in insertion order.
  package func tasks(at location: Location) -> [Task<Void, Never>] {
    tasks[location] ?? []
  }

  package var isEmpty: Bool { tasks.isEmpty }

  /// Cancels whatever was at `location` and stores `newTasks` there instead.
  package func replace(_ newTasks: [Task<Void, Never>], at location: Location) {
    cancel(at: location)
    if !newTasks.isEmpty {
      tasks[location] = newTasks
    }
  }

  /// Stores `task` at `location` next to the tasks already there.
  package func add(_ task: Task<Void, Never>, at location: Location) {
    tasks[location, default: []].append(task)
  }

  /// Cancels and forgets the tasks at `location`. Other locations are untouched.
  package func cancel(at location: Location) {
    tasks.removeValue(forKey: location)?.forEach { $0.cancel() }
  }

  /// Cancels and forgets every task.
  package func cancelAll() {
    let all = tasks.values
    tasks.removeAll()
    for group in all {
      for task in group {
        task.cancel()
      }
    }
  }

  deinit {
    cancelAll()
  }
}
