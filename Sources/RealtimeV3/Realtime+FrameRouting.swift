//
//  Realtime+FrameRouting.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import Foundation
import IssueReporting

extension Realtime {
  // MARK: - Internal routing entry point

  /// Starts consuming frames from `connection` and routes them to the appropriate
  /// handler. Spawns a detached `Task` so it does not block `connect()`.
  ///
  /// Call this once, immediately after the connection is established.
  func startFrameRouting(connection: any RealtimeConnection) {
    routingTask = Task {
      await routeFrames(from: connection)
    }
  }

  /// Drains the `connection.frames` stream, decodes each frame, and dispatches
  /// to `inflightPushRegistry` (for phx_reply) or the matching channel.
  ///
  /// A single malformed frame is logged and skipped; it does not kill the loop.
  private func routeFrames(from connection: any RealtimeConnection) async {
    do {
      for try await frame in connection.frames {
        await handleFrame(frame)
      }
    } catch {
      // Stream ended with an error (e.g. network loss). Log and fall through.
      // Reconnection logic is Task 13.
      reportIssue("Realtime frame stream ended with error: \(error)")
    }
    // Stream finished (normal or error). Transition to idle so callers know
    // the connection is gone. Reconnection is Task 13.
    transition(to: .idle)
  }

  /// Decodes and dispatches one `TransportFrame`.
  private func handleFrame(_ frame: TransportFrame) async {
    let message: PhoenixMessage
    do {
      let now = Date()
      switch frame {
      case .text(let text):
        message = try serializer.decodeText(text, receivedAt: now)
      case .binary(let data):
        message = try serializer.decodeBinary(data, receivedAt: now)
      }
    } catch {
      // Malformed frame: swallow and continue. A bad frame must never kill routing.
      return
    }

    if message.event == .reply {
      // phx_reply: resolve the pending push registered for this ref.
      guard let ref = message.ref else { return }
      // Extract status and response from the payload JSON object.
      // Shape: {"status": "...", "response": {...}}
      guard
        case .json(let json) = message.payload,
        let obj = json.objectValue,
        let status = obj["status"]?.stringValue,
        let response = obj["response"]
      else {
        // Malformed reply payload: skip.
        return
      }
      inflightPushRegistry.resolve(ref: ref, status: status, response: response)
      return
    }

    // Route to the matching channel (if registered).
    if let channel = channels[message.topic] {
      await channel.receive(message)
    }
  }
}
