//
//  WithTimeoutTests.swift
//
//
//  Created by Guilherme Souza on 19/04/24.
//

import Clocks
import Foundation
import ConcurrencyExtras
import Testing

@testable import Helpers

@Suite
struct WithTimeoutTests {
  @Test
  func throwsTimeoutErrorWhenOperationOutlivesDuration() async {
    await #expect(throws: TimeoutError.self) {
      try await withTimeout(.milliseconds(50)) {
        try await Task.sleep(for: .seconds(10))
      }
    }
  }

  @Test
  func returnsResultWhenOperationFinishesInTime() async throws {
    let answer = try await withTimeout(.seconds(10)) { 42 }
    #expect(answer == 42)
  }

  @Test
  func propagatesTheBodyError() async {
    struct Failure: Error {}
    await #expect(throws: Failure.self) {
      try await withTimeout(.seconds(10)) { throw Failure() }
    }
  }

  @Test
  func runsTheBodyOnTheCallersActor() async throws {
    // A body that touches actor state must run as one of that actor's jobs; a plain task-group
    // child would run on the global executor while the actor sits suspended.
    let probe = ExecutorProbe()
    #expect(try await probe.bodyRanOnMyExecutor())
  }

  @Test
  func acceptsANonSendableBodyAndResult() async throws {
    final class Box { var value = 0 }
    let box = Box()
    let returned = try await withTimeout(.seconds(10)) {
      box.value = 7
      return box
    }
    #expect(returned === box)
    #expect(box.value == 7)
  }

  @Test
  func cancelsTheBodyWhenTheDeadlinePasses() async {
    // The loop can only end through cancellation, so the flag records that the body saw it,
    // whether cancellation landed while the body was spinning or before it even started.
    let bodyWasCancelled = LockIsolated(false)
    await #expect(throws: TimeoutError.self) {
      try await withTimeout(.milliseconds(50)) {
        while !Task.isCancelled { await Task.yield() }
        bodyWasCancelled.setValue(true)
      }
    }
    #expect(bodyWasCancelled.value)
  }

  @Test
  func registersTheTimerBeforeTheBodyStarts() async throws {
    // Without immediate child tasks the timer is enqueued and may register after the body.
    guard #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
    let clock = TestClock()
    try await withTimeout(.seconds(5), clock: clock) {
      // `checkSuspension()` throws when a sleep is pending: the timer is already on the clock.
      await #expect(throws: SuspensionError.self) { try await clock.checkSuspension() }
    }
  }

  @Test
  func doesNotFireBeforeTheDeadline() async throws {
    // Advancing from inside the body cannot race the body's own sleep registration, which is
    // what made the Task-plus-advance version hang when `advance` won the race.
    let clock = TestClock()
    let answer = try await withTimeout(.seconds(5), clock: clock) {
      await clock.advance(by: .seconds(2))
      return "done"
    }
    #expect(answer == "done")
  }
}

/// An actor whose executor records whether it is in the middle of running one of its jobs.
private actor ExecutorProbe {
  private let executor = RecordingExecutor()

  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

  func bodyRanOnMyExecutor() async throws -> Bool {
    try await withTimeout(.seconds(10)) { executor.isRunningJob.value }
  }
}

private final class RecordingExecutor: SerialExecutor {
  let isRunningJob = LockIsolated(false)
  private let queue = DispatchQueue(label: "RecordingExecutor")

  // The default implementation needs iOS 17 / macOS 14; the package supports iOS 16.
  func asUnownedSerialExecutor() -> UnownedSerialExecutor { UnownedSerialExecutor(ordinary: self) }

  func enqueue(_ job: UnownedJob) {
    queue.async {
      self.isRunningJob.setValue(true)
      job.runSynchronously(on: self.asUnownedSerialExecutor())
      self.isRunningJob.setValue(false)
    }
  }
}
