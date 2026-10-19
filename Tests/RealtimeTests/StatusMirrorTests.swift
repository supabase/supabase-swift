import Testing

@testable import Realtime

@Suite
struct StatusMirrorTests {
  @Test
  func currentReflectsLatestUpdate() {
    let mirror = StatusMirror(0)
    #expect(mirror.current == 0)

    mirror.update(1)
    mirror.update(2)

    #expect(mirror.current == 2)
  }

  @Test
  func streamReplaysCurrentThenEveryUpdate() async {
    let mirror = StatusMirror(0)
    mirror.update(1)

    var values = mirror.stream().makeAsyncIterator()
    mirror.update(2)
    mirror.update(3)

    #expect(await values.next() == 1)
    #expect(await values.next() == 2)
    #expect(await values.next() == 3)
  }

  @Test
  func streamWithoutReplayStartsAtNextUpdate() async {
    let mirror = StatusMirror(0)

    var values = mirror.stream(replayingCurrent: false).makeAsyncIterator()
    mirror.update(1)

    #expect(await values.next() == 1)
  }

  @Test
  func everyStreamReceivesEachUpdate() async {
    let mirror = StatusMirror(0)

    var first = mirror.stream(replayingCurrent: false).makeAsyncIterator()
    var second = mirror.stream(replayingCurrent: false).makeAsyncIterator()
    mirror.update(1)

    #expect(await first.next() == 1)
    #expect(await second.next() == 1)
  }

  @Test
  func cancelledConsumerEndsItsStreamOnly() async {
    let mirror = StatusMirror(0)

    let cancelled = Task {
      for await _ in mirror.stream(replayingCurrent: false) {}
    }
    cancelled.cancel()
    await cancelled.value

    var other = mirror.stream(replayingCurrent: false).makeAsyncIterator()
    mirror.update(1)

    #expect(await other.next() == 1)
  }

  @Test
  func finishEndsEveryStream() async {
    let mirror = StatusMirror(0)

    var first = mirror.stream(replayingCurrent: false).makeAsyncIterator()
    var second = mirror.stream(replayingCurrent: false).makeAsyncIterator()
    mirror.finish()

    #expect(await first.next() == nil)
    #expect(await second.next() == nil)
  }
}
