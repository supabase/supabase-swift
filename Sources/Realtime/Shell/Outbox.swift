//
//  Outbox.swift
//  Realtime
//

import ConcurrencyExtras
import Foundation
import Logging

/// Sends messages over a connection in the order they were enqueued.
///
/// ``enqueue(_:)`` never waits: a writer task drains the queue one frame at a time, so a slow or
/// stalled send delays the frames behind it but never the caller.
final class Outbox: Sendable {
  private enum Item {
    case message(RealtimeMessage)
    case frame(WebSocketFrame)
  }

  private let continuation: AsyncStream<Item>.Continuation
  private let writer: Task<Void, Never>

  init(connection: any WebSocketConnection, serializer: RealtimeSerializer, logger: Logger) {
    let (items, continuation) = AsyncStream.makeStream(of: Item.self)
    self.continuation = continuation
    writer = Task {
      for await item in items {
        let frame: WebSocketFrame
        switch item {
        case .frame(let encoded):
          frame = encoded
        case .message(let message):
          do {
            frame = .text(try serializer.encodeText(message))
          } catch {
            logger.error("Failed to encode message \(message): \(error)")
            continue
          }
        }
        do {
          try await connection.send(frame)
        } catch {
          guard !Task.isCancelled else { return }
          logger.error("Failed to send frame: \(error)")
        }
      }
    }
  }

  deinit {
    close()
  }

  func enqueue(_ message: RealtimeMessage) {
    continuation.yield(.message(message))
  }

  /// Queues a frame that is already encoded, such as a binary broadcast.
  func enqueue(_ frame: WebSocketFrame) {
    continuation.yield(.frame(frame))
  }

  /// Ends the writer task. Frames still queued, and any send in flight, are dropped, and later
  /// calls to ``enqueue(_:)`` do nothing.
  func close() {
    continuation.finish()
    writer.cancel()
  }

  /// Ends the queue and lets the writer send the frames still queued. Returns once they are
  /// sent, or once `deadline` ends, whichever comes first: then the frames left are dropped as
  /// with ``close()``. Later calls to ``enqueue(_:)`` do nothing.
  ///
  /// A send that never returns cannot hold the caller past `deadline`.
  func drain(until deadline: Task<Void, Never>) async {
    continuation.finish()
    let pending = LockIsolated<CheckedContinuation<Void, Never>?>(nil)
    let finish: @Sendable () -> Void = {
      pending.withValue { continuation in
        continuation?.resume()
        continuation = nil
      }
    }
    await withCheckedContinuation { continuation in
      pending.setValue(continuation)
      for task in [writer, deadline] {
        Task {
          await task.value
          finish()
        }
      }
    }
    writer.cancel()
  }
}
