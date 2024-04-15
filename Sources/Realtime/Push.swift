//
//  Push.swift
//
//
//  Created by Guilherme Souza on 02/01/24.
//

import _Helpers
import Foundation

/// Represents the different status of a push
enum PushStatus: String, Sendable {
  case ok
  case error
  case timeout
}

actor Push {
  private weak var channel: RealtimeChannel?
  let message: RealtimeMessage

  private var receivedContinuation: CheckedContinuation<PushStatus, Never>?

  init(channel: RealtimeChannel?, message: RealtimeMessage) {
    self.channel = channel
    self.message = message
  }

  func send() async -> PushStatus {
    do {
      try await channel?.socket?.ws.send(message)

      if channel?.config.broadcast.acknowledgeBroadcasts == true {
        return await withCheckedContinuation {
          receivedContinuation = $0
        }
      }

      return .ok
    } catch {
      await channel?.socket?.config.logger?.debug(
        """
        Failed to send message:
        \(message)

        Error:
        \(error)
        """
      )
      return .error
    }
  }

  func didReceive(status: PushStatus) {
    receivedContinuation?.resume(returning: status)
    receivedContinuation = nil
  }
}
