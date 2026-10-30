//
//  OutboxTests.swift
//  RealtimeTests
//

import Clocks
import ConcurrencyExtras
import Foundation
import Testing

@testable import Realtime

@Suite
struct OutboxTests {
  private let serializer = RealtimeSerializer()

  private func message(_ index: Int) -> RealtimeMessage {
    RealtimeMessage(joinRef: nil, ref: "\(index)", topic: "realtime:t", event: "test", payload: [:])
  }

  private func refs(of fake: FakeWebSocket) throws -> [String] {
    try fake.sentEvents.compactMap { event in
      guard case .frame(.text(let text)) = event else { return nil }
      return try serializer.decodeText(text).ref
    }
  }

  @Test
  func outboxSendsInEnqueueOrder() async throws {
    let (fake, _) = FakeWebSocket.fakes()
    let clock = TestClock<Duration>()
    let serializer = serializer
    fake.onSend { frame in
      guard case .text(let text) = frame,
        let index = try? serializer.decodeText(text).ref.flatMap(Int.init)
      else { return }
      let steps = index % 3
      for _ in 0..<steps {
        try? await clock.sleep(for: .seconds(1))
      }
    }
    let outbox = Outbox(connection: fake, serializer: serializer, logger: .silent)
    defer { outbox.close() }

    for index in 0..<100 {
      outbox.enqueue(message(index))
    }

    var iterations = 0
    while fake.sentEvents.count < 100, iterations < 100_000 {
      await Task.megaYield()
      await clock.advance(by: .seconds(1))
      iterations += 1
    }

    #expect(try refs(of: fake) == (0..<100).map(String.init))
  }

  @Test
  func stalledSendDoesNotBlockEnqueue() async throws {
    let (fake, _) = FakeWebSocket.fakes()
    let started = AsyncStream.makeStream(of: Void.self)
    fake.onSend { _ in
      started.continuation.yield()
      try? await Task.sleep(for: .seconds(1_000_000))
    }
    let outbox = Outbox(connection: fake, serializer: serializer, logger: .silent)
    defer { outbox.close() }

    outbox.enqueue(message(0))
    var iterator = started.stream.makeAsyncIterator()
    await iterator.next()

    for index in 1...10 {
      outbox.enqueue(message(index))
    }

    #expect(try refs(of: fake) == ["0"])
  }

  @Test
  func failedSendDoesNotStopLaterFrames() async throws {
    struct SendFailed: Error {}
    let connection = FailingOnceConnection(error: SendFailed())
    let outbox = Outbox(connection: connection, serializer: serializer, logger: .silent)
    defer { outbox.close() }

    outbox.enqueue(message(0))
    outbox.enqueue(message(1))

    var iterator = connection.delivered.stream.makeAsyncIterator()
    #expect(await iterator.next() == .text(try serializer.encodeText(message(1))))
  }

  @Test
  func closeEndsTheWriterSoLaterFramesAreDropped() async throws {
    let (fake, _) = FakeWebSocket.fakes()
    let outbox = Outbox(connection: fake, serializer: serializer, logger: .silent)

    outbox.enqueue(message(0))
    outbox.close()
    outbox.enqueue(message(1))
    await Task.megaYield()

    #expect(try !refs(of: fake).contains("1"))
  }
}

/// A connection whose first `send` throws and whose later sends are delivered.
private final class FailingOnceConnection: WebSocketConnection {
  let events = AsyncStream<WebSocketEvent>.makeStream().stream
  let delivered = AsyncStream.makeStream(of: WebSocketFrame.self)
  private let error: any Error
  private let hasFailed = LockIsolated(false)

  init(error: any Error) {
    self.error = error
  }

  func send(_ frame: WebSocketFrame) async throws {
    let shouldFail = hasFailed.withValue { hasFailed in
      defer { hasFailed = true }
      return !hasFailed
    }
    if shouldFail { throw error }
    delivered.continuation.yield(frame)
  }

  func close(code: WebSocketCloseCode, reason: String?) {}
}
