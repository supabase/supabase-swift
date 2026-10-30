//
//  Outbox.swift
//  Realtime
//

import Foundation
import Logging

/// Sends messages over a connection in the order they were enqueued.
///
/// ``enqueue(_:)`` never waits: a writer task drains the queue one frame at a time, so a slow or
/// stalled send delays the frames behind it but never the caller.
final class Outbox: Sendable {
  private let continuation: AsyncStream<RealtimeMessage>.Continuation
  private let writer: Task<Void, Never>

  init(connection: any WebSocketConnection, serializer: RealtimeSerializer, logger: Logger) {
    let (messages, continuation) = AsyncStream.makeStream(of: RealtimeMessage.self)
    self.continuation = continuation
    writer = Task {
      for await message in messages {
        let frame: WebSocketFrame
        do {
          frame = .text(try serializer.encodeText(message))
        } catch {
          logger.error("Failed to encode message \(message): \(error)")
          continue
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

  func enqueue(_ message: RealtimeMessage) {
    continuation.yield(message)
  }

  /// Ends the writer task. Frames still queued, and any send in flight, are dropped, and later
  /// calls to ``enqueue(_:)`` do nothing.
  func close() {
    continuation.finish()
    writer.cancel()
  }
}
