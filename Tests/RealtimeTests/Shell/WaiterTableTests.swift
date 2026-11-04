//
//  WaiterTableTests.swift
//  RealtimeTests
//

import ConcurrencyExtras
import Testing

@testable import Realtime

@Suite
struct WaiterTableTests {
  static let timedOut = RealtimeError(kind: .timeout, message: "timed out")

  /// Parks a waiter in `table` and returns its id and a task that reports how the wait ended.
  private func park(
    in table: inout WaiterTable
  ) async -> (WaiterID, Task<Result<Void, any Error>, Never>) {
    let id = table.next()
    let parked = AsyncStream.makeStream(of: CheckedContinuation<Void, any Error>.self)
    let waiter = Task {
      await Result<Void, any Error> {
        try await withCheckedThrowingContinuation { parked.continuation.yield($0) }
      }
    }
    for await continuation in parked.stream {
      table.park(id, continuation)
      break
    }
    return (id, waiter)
  }

  @Test
  func nextReturnsDistinctIDs() {
    var table = WaiterTable()
    #expect(table.next() != table.next())
  }

  @Test
  func resumeSuccessReturnsNormally() async {
    var table = WaiterTable()
    let (id, waiter) = await park(in: &table)

    table.resume(id, with: .success)

    #expect(await waiter.value.isSuccess)
  }

  @Test
  func resumeFailureThrowsTheError() async {
    var table = WaiterTable()
    let (id, waiter) = await park(in: &table)

    table.resume(id, with: .failure(Self.timedOut))

    guard case .failure(let error) = await waiter.value else {
      Issue.record("The wait should have thrown")
      return
    }
    #expect((error as? RealtimeError)?.isSameFailure(as: Self.timedOut) == true)
  }

  @Test
  func resumeCancelledThrowsCancellationError() async {
    var table = WaiterTable()
    let (id, waiter) = await park(in: &table)

    table.resume(id, with: .cancelled)

    guard case .failure(let error) = await waiter.value else {
      Issue.record("The wait should have thrown")
      return
    }
    #expect(error is CancellationError)
  }

  @Test
  func resumeTwiceResumesOnce() async {
    var table = WaiterTable()
    let (id, waiter) = await park(in: &table)

    table.resume(id, with: .success)
    table.resume(id, with: .failure(Self.timedOut))

    #expect(await waiter.value.isSuccess)
  }

  @Test
  func resumeUnknownIsNoOp() {
    var table = WaiterTable()
    table.resume(WaiterID(rawValue: 99), with: .success)
    table.resume(table.next(), with: .cancelled)
  }

  @Test
  func failAllThrowsToEveryWaiterAndEmptiesTheTable() async {
    var table = WaiterTable()
    let (first, firstWaiter) = await park(in: &table)
    let (second, secondWaiter) = await park(in: &table)

    table.failAll(with: Self.timedOut)

    for waiter in [firstWaiter, secondWaiter] {
      guard case .failure(let error) = await waiter.value else {
        Issue.record("The wait should have thrown")
        continue
      }
      #expect((error as? RealtimeError)?.isSameFailure(as: Self.timedOut) == true)
    }
    table.resume(first, with: .success)
    table.resume(second, with: .success)
    table.failAll(with: Self.timedOut)
  }
}

extension Result {
  fileprivate var isSuccess: Bool {
    if case .success = self { return true }
    return false
  }
}
