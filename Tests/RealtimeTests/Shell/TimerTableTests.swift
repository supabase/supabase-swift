//
//  TimerTableTests.swift
//  RealtimeTests
//

import Clocks
import ConcurrencyExtras
import TestHelpers
import Testing

@testable import Realtime

@Suite(.mainSerialExecutorSerialized)
struct TimerTableTests {
  struct Fired: Equatable {
    let id: TimerID
    let token: UInt64
  }

  private let clock = TestClock<Duration>()
  private let fired = AsyncStream.makeStream(of: Fired.self)

  /// The timer reads its deadline here, so ``TestClock/advance(by:)`` right after this call
  /// cannot miss it, even when the timer's task has not started to sleep yet.
  private func schedule(
    _ table: inout TimerTable, _ id: TimerID, after delay: Duration = .seconds(10)
  ) {
    let continuation = fired.continuation
    table.schedule(id, after: delay, clock: clock) { id, token in
      continuation.yield(Fired(id: id, token: token))
    }
  }

  @Test
  func timerFiresWithItsTokenAfterTheDelay() async {
    await withMainSerialExecutor {
      var table = TimerTable()
      schedule(&table, .heartbeat)

      await clock.advance(by: .seconds(10))

      var iterator = fired.stream.makeAsyncIterator()
      let event = await iterator.next()
      #expect(event?.id == .heartbeat)
      #expect(event.map { table.isCurrent($0.id, token: $0.token) } == true)
    }
  }

  @Test
  func timerDoesNotFireBeforeTheDelay() async {
    await withMainSerialExecutor {
      var table = TimerTable()
      schedule(&table, .heartbeat)
      schedule(&table, .tokenRefresh, after: .seconds(5))

      await clock.advance(by: .seconds(5))

      var iterator = fired.stream.makeAsyncIterator()
      #expect(await iterator.next()?.id == .tokenRefresh)
      // The clock stands at 5 s, so the heartbeat's sleep cannot have ended: the sentinel comes
      // next.
      fired.continuation.yield(Fired(id: .rejoin(channel: ChannelID(rawValue: 1)), token: 0))
      #expect(await iterator.next()?.id == .rejoin(channel: ChannelID(rawValue: 1)))
      await clock.advance(by: .seconds(5))
      #expect(await iterator.next()?.id == .heartbeat)
    }
  }

  @Test
  func rescheduleReplacesTokenSoOldFireIsStale() async {
    await withMainSerialExecutor {
      var table = TimerTable()
      schedule(&table, .heartbeat)
      schedule(&table, .heartbeat)

      await clock.advance(by: .seconds(10))

      var iterator = fired.stream.makeAsyncIterator()
      let event = await iterator.next()
      #expect(event?.id == .heartbeat)
      #expect(event.map { table.isCurrent($0.id, token: $0.token) } == true)
      #expect(table.isCurrent(.heartbeat, token: 0) == false)
      #expect(table.isCurrent(.heartbeat, token: (event?.token ?? 0) &- 1) == false)
    }
  }

  @Test
  func rescheduleFiresOnlyTheNewTimer() async {
    await withMainSerialExecutor {
      var table = TimerTable()
      schedule(&table, .heartbeat)
      schedule(&table, .heartbeat)
      schedule(&table, .tokenRefresh, after: .seconds(20))

      await clock.advance(by: .seconds(20))

      var iterator = fired.stream.makeAsyncIterator()
      var ids: [TimerID] = []
      while let event = await iterator.next() {
        ids.append(event.id)
        if ids.count == 2 { break }
      }
      #expect(ids.sorted { "\($0)" < "\($1)" } == [.heartbeat, .tokenRefresh])
    }
  }

  @Test
  func cancelledTimerNeverFires() async {
    await withMainSerialExecutor {
      var table = TimerTable()
      schedule(&table, .heartbeat)
      schedule(&table, .tokenRefresh)
      let tasks = [table.task(for: .heartbeat), table.task(for: .tokenRefresh)].compactMap { $0 }

      table.cancel(.heartbeat)
      await clock.advance(by: .seconds(10))
      for task in tasks { await task.value }

      fired.continuation.finish()
      var iterator = fired.stream.makeAsyncIterator()
      #expect(await iterator.next()?.id == .tokenRefresh)
      #expect(await iterator.next() == nil)
    }
  }

  @Test
  func cancelMakesTheTokenStale() async {
    withMainSerialExecutor {
      var table = TimerTable()
      schedule(&table, .heartbeat)
      table.cancel(.heartbeat)

      #expect(table.isCurrent(.heartbeat, token: 1) == false)
    }
  }

  @Test
  func cancelUnknownIsNoOp() {
    var table = TimerTable()
    table.cancel(.heartbeat)
  }

  @Test
  func cancelAllStopsEveryTimerAndEmptiesTheTable() async {
    await withMainSerialExecutor {
      var table = TimerTable()
      schedule(&table, .heartbeat)
      schedule(&table, .rejoin(channel: ChannelID(rawValue: 1)))
      let tasks = [
        table.task(for: .heartbeat), table.task(for: .rejoin(channel: ChannelID(rawValue: 1))),
      ]
      .compactMap { $0 }

      table.cancelAll()
      await clock.advance(by: .seconds(10))
      for task in tasks { await task.value }

      fired.continuation.finish()
      var iterator = fired.stream.makeAsyncIterator()
      #expect(await iterator.next() == nil)
      for token in 0...3 {
        #expect(table.isCurrent(.heartbeat, token: UInt64(token)) == false)
        #expect(
          table.isCurrent(.rejoin(channel: ChannelID(rawValue: 1)), token: UInt64(token)) == false)
      }
    }
  }

  @Test
  func claimFireAcceptsTheCurrentTokenOnce() async {
    await withMainSerialExecutor {
      var table = TimerTable()
      schedule(&table, .heartbeat)

      await clock.advance(by: .seconds(10))
      var iterator = fired.stream.makeAsyncIterator()
      guard let event = await iterator.next() else {
        Issue.record("The timer did not fire")
        return
      }

      let first = table.claimFire(event.id, token: event.token)
      let second = table.claimFire(event.id, token: event.token)
      #expect(first)
      #expect(!second)
      #expect(!table.isCurrent(event.id, token: event.token))
    }
  }
}
