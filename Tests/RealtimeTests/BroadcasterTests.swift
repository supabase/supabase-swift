import ConcurrencyExtras
import Helpers
import Testing

@testable import Realtime

@Suite
struct BroadcasterTests {
  func collect(_ stream: AsyncStream<Int>) async -> [Int] {
    await stream.reduce(into: []) { $0.append($1) }
  }

  @Test
  func streamTakenBeforeYieldSeesElement() async {
    let broadcaster = Broadcaster<Int>()
    let stream = broadcaster.subscribe()

    broadcaster.yield(1)
    broadcaster.yield(2)
    broadcaster.finish()

    #expect(await collect(stream) == [1, 2])
  }

  @Test
  func retainingBroadcasterReplaysCurrentFirst() async {
    let broadcaster = Broadcaster<Int>(retaining: 0)
    broadcaster.yield(5)
    let stream = broadcaster.subscribe()

    broadcaster.yield(6)
    broadcaster.finish()

    #expect(await collect(stream) == [5, 6])
    #expect(broadcaster.current == 6)
  }

  @Test
  func retainingWithNilInitialReplaysNothingUntilFirstYield() async {
    let broadcaster = Broadcaster<Int>(retaining: nil)
    let stream = broadcaster.subscribe()

    broadcaster.finish()

    #expect(await collect(stream) == [])
    #expect(broadcaster.current == nil)
  }

  @Test
  func filterDropsNonMatching() async {
    let broadcaster = Broadcaster<Int>()
    let stream = broadcaster.subscribe(where: { $0.isMultiple(of: 2) })

    for value in 1...4 { broadcaster.yield(value) }
    broadcaster.finish()

    #expect(await collect(stream) == [2, 4])
  }

  @Test
  func subscribeAfterFinishGetsRetainedThenEnds() async {
    let broadcaster = Broadcaster<Int>(retaining: 7)
    broadcaster.finish()

    #expect(broadcaster.isFinished)
    #expect(await collect(broadcaster.subscribe()) == [7])
    #expect(broadcaster.subscriberCount == 0)
  }

  @Test
  func yieldAfterFinishIsIgnored() async {
    let broadcaster = Broadcaster<Int>(retaining: 1)
    broadcaster.finish()
    broadcaster.yield(2)

    #expect(broadcaster.current == 1)
  }

  @Test
  func subscriberCountTracksActiveStreams() async {
    let broadcaster = Broadcaster<Int>()
    let first = broadcaster.subscribe()
    let second = broadcaster.subscribe()
    #expect(broadcaster.subscriberCount == 2)

    broadcaster.finish()

    #expect(broadcaster.subscriberCount == 0)
    #expect(await collect(first) == [])
    #expect(await collect(second) == [])
  }

  @Test
  func cancellingConsumerRemovesSubscriberAndCallsOnTermination() async {
    let broadcaster = Broadcaster<Int>()
    let terminations = LockIsolated(0)
    let stream = broadcaster.subscribe(onTermination: { terminations.withValue { $0 += 1 } })
    let started = AsyncStream<Void>.makeStream()

    let consumer = Task {
      started.continuation.yield()
      for await _ in stream {}
    }
    await started.stream.first { _ in true }
    consumer.cancel()
    await consumer.value

    #expect(broadcaster.subscriberCount == 0)
    #expect(terminations.value == 1)
  }

  @Test
  func onTerminationRunsOnceWhenBroadcasterFinishes() async {
    let broadcaster = Broadcaster<Int>()
    let terminations = LockIsolated(0)
    let stream = broadcaster.subscribe(onTermination: { terminations.withValue { $0 += 1 } })

    broadcaster.finish()
    _ = await collect(stream)

    #expect(terminations.value == 1)
  }

  @Test
  func terminationDuringYieldDoesNotDeadlock() async throws {
    try await withTimeout(.seconds(5)) {
      for _ in 0..<1_000 {
        let broadcaster = Broadcaster<Int>()
        let consumers = (0..<4).map { _ in
          let stream = broadcaster.subscribe()
          return Task { for await _ in stream {} }
        }
        let writer = Task {
          for value in 0..<50 { broadcaster.yield(value) }
        }
        for consumer in consumers { consumer.cancel() }
        await writer.value
        for consumer in consumers { await consumer.value }
        broadcaster.finish()
        #expect(broadcaster.subscriberCount == 0)
      }
    }
  }
}
