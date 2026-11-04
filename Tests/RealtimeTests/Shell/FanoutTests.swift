//
//  FanoutTests.swift
//  RealtimeTests
//

import ConcurrencyExtras
import TestHelpers
import Testing

@testable import Realtime

@Suite(.timeLimit(.minutes(1)))
struct FanoutTests {
  func id(_ rawValue: UInt64) -> StreamID {
    StreamID(rawValue: rawValue, channel: nil)
  }

  @Test
  func streamTakenBeforeYieldSeesElements() async {
    let fanout = Fanout<Int>()
    let stream = fanout.subscribe(id(1), onTermination: {})

    fanout.yield(1)
    fanout.yield(2)
    fanout.finish()

    #expect(await stream.collect() == [1, 2])
    #expect(fanout.current == nil)
  }

  @Test
  func retainingFanoutReplaysCurrentToNewSubscribers() async {
    let fanout = Fanout<Int>(retaining: 0)
    fanout.yield(5)
    let stream = fanout.subscribe(id(1), onTermination: {})

    fanout.yield(6)
    fanout.finish()

    #expect(await stream.collect() == [5, 6])
    #expect(fanout.current == 6)
  }

  @Test
  func retainingFanoutReplaysItsInitialElementBeforeTheFirstYield() async {
    let fanout = Fanout<Int>(retaining: 3)
    let stream = fanout.subscribe(id(1), onTermination: {})

    fanout.finish()

    #expect(await stream.collect() == [3])
  }

  @Test
  func retainingFanoutWithNoInitialReplaysNothingUntilTheFirstYield() async {
    let fanout = Fanout<Int>(retaining: nil)
    let early = fanout.subscribe(id(1), onTermination: {})
    #expect(fanout.current == nil)

    fanout.yield(4)
    let late = fanout.subscribe(id(2), onTermination: {})
    fanout.finish()

    #expect(await early.collect() == [4])
    #expect(await late.collect() == [4])
  }

  @Test
  func filteredSubscriberSeesOnlyMatchingElements() async {
    let fanout = Fanout<Int>()
    let evens = fanout.subscribe(id(1), where: { $0.isMultiple(of: 2) }, onTermination: {})
    let all = fanout.subscribe(id(2), onTermination: {})

    for value in 1...4 { fanout.yield(value) }
    fanout.finish()

    #expect(await evens.collect() == [2, 4])
    #expect(await all.collect() == [1, 2, 3, 4])
  }

  @Test
  func filterDoesNotApplyToTheReplayedElement() async {
    let fanout = Fanout<Int>(retaining: 1)
    let stream = fanout.subscribe(id(1), where: { $0.isMultiple(of: 2) }, onTermination: {})

    fanout.yield(2)
    fanout.yield(3)
    fanout.finish()

    #expect(await stream.collect() == [1, 2])
  }

  @Test
  func subscribeAfterFinishReturnsAFinishedStream() async {
    let plain = Fanout<Int>()
    plain.finish()
    let retaining = Fanout<Int>(retaining: 7)
    retaining.finish()

    #expect(await plain.subscribe(id(1), onTermination: {}).collect().isEmpty)
    #expect(await retaining.subscribe(id(1), onTermination: {}).collect() == [7])
    #expect(plain.count == 0)
    #expect(retaining.count == 0)
  }

  @Test
  func yieldAfterFinishIsIgnored() {
    let fanout = Fanout<Int>(retaining: 1)
    fanout.finish()
    fanout.yield(2)

    #expect(fanout.current == 1)
  }

  @Test
  func finishFromTheOwnerDoesNotCallOnTermination() async {
    let fanout = Fanout<Int>()
    let terminations = LockIsolated(0)
    let stream = fanout.subscribe(id(1), onTermination: { terminations.withValue { $0 += 1 } })

    fanout.finish()
    _ = await stream.collect()

    #expect(terminations.value == 0)
  }

  @Test
  func subscribingToAFinishedFanoutDoesNotCallOnTermination() async {
    let fanout = Fanout<Int>()
    fanout.finish()
    let terminations = LockIsolated(0)

    let stream = fanout.subscribe(id(1), onTermination: { terminations.withValue { $0 += 1 } })
    _ = await stream.collect()

    #expect(terminations.value == 0)
  }

  @Test
  func consumerCancelCallsOnTerminationOnce() async {
    let fanout = Fanout<Int>()
    let terminations = LockIsolated(0)
    let stream = fanout.subscribe(id(1), onTermination: { terminations.withValue { $0 += 1 } })
    let started = AsyncStream<Void>.makeStream()

    let consumer = Task {
      started.continuation.yield()
      for await _ in stream {}
    }
    await started.stream.first { _ in true }
    consumer.cancel()
    await consumer.value

    #expect(terminations.value == 1)
  }

  @Test
  func subscribersCountUntilRemovedOrFinished() {
    let fanout = Fanout<Int>()
    let first = fanout.subscribe(id(1), onTermination: {})
    let second = fanout.subscribe(id(2), onTermination: {})
    #expect(fanout.count == 2)

    #expect(fanout.remove(id(1)))
    #expect(!fanout.remove(id(1)))
    #expect(fanout.count == 1)

    fanout.finish()
    #expect(fanout.count == 0)
    withExtendedLifetime((first, second)) {}
  }

  @Test
  func yieldPrunesAStreamTheConsumerEnded() async {
    let fanout = Fanout<Int>()
    let stream = fanout.subscribe(id(1), onTermination: {})
    let started = AsyncStream<Void>.makeStream()
    let consumer = Task {
      started.continuation.yield()
      for await _ in stream {}
    }
    await started.stream.first { _ in true }
    consumer.cancel()
    await consumer.value

    fanout.yield(1)

    #expect(fanout.count == 0)
  }

  @Test
  func releasingTheFanoutEndsItsStreams() async {
    var fanout: Fanout<Int>? = Fanout()
    let stream = fanout!.subscribe(id(1), onTermination: {})
    fanout!.yield(1)

    fanout = nil

    #expect(await stream.collect() == [1])
  }
}
