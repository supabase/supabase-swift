//
//  WithTimeoutTests.swift
//
//
//  Created by Guilherme Souza on 19/04/24.
//

import Clocks
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
  func propagatesTheBodysOwnError() async {
    struct Failure: Error {}
    await #expect(throws: Failure.self) {
      try await withTimeout(.seconds(10)) { throw Failure() }
    }
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
  func cancelsTheBodyWhenTheClockPassesTheDeadline() async throws {
    let clock = TestClock()
    let bodyWasCancelled = LockIsolated(false)
    let bodyStarted = AsyncStream<Void>.makeStream()

    let task = Task {
      try await withTimeout(.seconds(5), clock: clock) {
        bodyStarted.continuation.yield()
        await withTaskCancellationHandler {
          while !Task.isCancelled { await Task.yield() }
        } onCancel: {
          bodyWasCancelled.setValue(true)
        }
      }
    }

    // The body has registered its cancellation handler, so the timer can fire.
    _ = await bodyStarted.stream.first { _ in true }
    await clock.advance(by: .seconds(5))

    await #expect(throws: TimeoutError.self) { try await task.value }
    #expect(bodyWasCancelled.value)
  }

  @Test
  func doesNotFireBeforeTheDeadline() async throws {
    let clock = TestClock()
    let task = Task {
      try await withTimeout(.seconds(5), clock: clock) {
        try await clock.sleep(for: .seconds(2))
        return "done"
      }
    }
    await clock.advance(by: .seconds(2))
    #expect(try await task.value == "done")
  }
}
