//
//  TaskStorageTests.swift
//  HelpersTests
//
//  Created by Guilherme Souza on 19/10/26.
//

import Testing

@testable import Helpers

@Suite
struct TaskStorageTests {
  enum Location: Hashable {
    case connection, idleDisconnect
  }

  /// A task that only ends when cancelled, so `isCancelled` is the whole observable outcome.
  private func sleeper() -> Task<Void, Never> {
    Task { while !Task.isCancelled { await Task.yield() } }
  }

  @Test
  func replaceCancelsOnlyTheTasksAtThatLocation() {
    let storage = TaskStorage<Location>()
    let oldConnection = sleeper()
    let idle = sleeper()
    storage.replace([oldConnection], at: .connection)
    storage.replace([idle], at: .idleDisconnect)

    let newConnection = sleeper()
    storage.replace([newConnection], at: .connection)

    #expect(oldConnection.isCancelled)
    #expect(!newConnection.isCancelled)
    #expect(!idle.isCancelled)
    #expect(storage.tasks(at: .connection).count == 1)
    storage.cancelAll()
  }

  @Test
  func replaceWithNothingClearsTheLocation() {
    let storage = TaskStorage<Location>()
    let task = sleeper()
    storage.replace([task], at: .connection)
    storage.replace([], at: .connection)
    #expect(task.isCancelled)
    #expect(storage.isEmpty)
  }

  @Test
  func addAppendsWithoutCancelling() {
    let storage = TaskStorage<Location>()
    let first = sleeper()
    let second = sleeper()
    storage.add(first, at: .connection)
    storage.add(second, at: .connection)
    #expect(!first.isCancelled)
    #expect(storage.tasks(at: .connection).count == 2)
    storage.cancel(at: .connection)
    #expect(first.isCancelled && second.isCancelled)
    #expect(storage.isEmpty)
  }

  @Test
  func cancelAllAndDeinitCancelEverything() {
    let tasks = [sleeper(), sleeper(), sleeper()]
    do {
      let storage = TaskStorage<Location>()
      storage.replace([tasks[0]], at: .connection)
      storage.add(tasks[1], at: .idleDisconnect)
      storage.cancelAll()
      #expect(tasks[0].isCancelled && tasks[1].isCancelled)
      #expect(storage.isEmpty)
      storage.add(tasks[2], at: .connection)
    }
    // `storage` left scope: `deinit` cancelled the task added after `cancelAll()`.
    #expect(tasks[2].isCancelled)
  }
}
