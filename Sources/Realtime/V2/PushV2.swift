//
//  PushV2.swift
//
//
//  Created by Guilherme Souza on 02/01/24.
//

import Foundation
import Helpers

/// Represents the different status of a push
public enum PushStatus: String, Sendable {
  case ok
  case error
  case timeout
}

actor PushV2 {
  private weak var channel: RealtimeChannelV2?
  let message: RealtimeMessageV2

  private var receivedContinuation: CheckedContinuation<PushStatus, Never>?

  init(channel: RealtimeChannelV2?, message: RealtimeMessageV2) {
    self.channel = channel
    self.message = message
  }

  func send() async -> PushStatus {
    await channel?.socket.push(message)

    if channel?.config.broadcast.acknowledgeBroadcasts == true {
      do {
        return try await withTimeout(interval: channel?.socket.options().timeoutInterval ?? 10) {
          await withCheckedContinuation {
            self.receivedContinuation = $0
          }
        }
      } catch is TimeoutError {
        channel?.logger?.debug("Push timed out.")
        return .timeout
      } catch {
        channel?.logger?.error("Error sending push: \(error)")
        return .error
      }
    }

    return .ok
  }

  func didReceive(status: PushStatus) {
    receivedContinuation?.resume(returning: status)
    receivedContinuation = nil
  }
}
