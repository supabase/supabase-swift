//
//  MockWebSocketClient.swift
//
//
//  Created by Guilherme Souza on 29/12/23.
//

import ConcurrencyExtras
import Foundation
@testable import Realtime
import XCTestDynamicOverlay

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class MockWebSocketClient: WebSocketClient {
  struct MutableState {
    var receiveContinuation: AsyncThrowingStream<RealtimeMessageV2, any Error>.Continuation?
    var sentMessages: [RealtimeMessageV2] = []
    var onCallback: ((RealtimeMessageV2) -> RealtimeMessageV2?)?
    var connectContinuation: AsyncStream<ConnectionStatus>.Continuation?

    var sendMessageBuffer: [RealtimeMessageV2] = []
    var connectionStatusBuffer: [ConnectionStatus] = []
  }

  private let mutableState = LockIsolated(MutableState())

  var sentMessages: [RealtimeMessageV2] {
    mutableState.sentMessages
  }

  func send(_ message: RealtimeMessageV2) async throws {
    mutableState.withValue {
      $0.sentMessages.append(message)

      if let callback = $0.onCallback, let response = callback(message) {
        mockReceive(response)
      }
    }
  }

  func mockReceive(_ message: RealtimeMessageV2) {
    mutableState.withValue {
      if let continuation = $0.receiveContinuation {
        continuation.yield(message)
      } else {
        $0.sendMessageBuffer.append(message)
      }
    }
  }

  func on(_ callback: @escaping (RealtimeMessageV2) -> RealtimeMessageV2?) {
    mutableState.withValue {
      $0.onCallback = callback
    }
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, any Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, any Error>.makeStream()
    mutableState.withValue {
      $0.receiveContinuation = continuation

      while !$0.sendMessageBuffer.isEmpty {
        let message = $0.sendMessageBuffer.removeFirst()
        $0.receiveContinuation?.yield(message)
      }
    }
    return stream
  }

  func mockConnect(_ status: ConnectionStatus) {
    mutableState.withValue {
      if let continuation = $0.connectContinuation {
        continuation.yield(status)
      } else {
        $0.connectionStatusBuffer.append(status)
      }
    }
  }

  func connect() -> AsyncStream<ConnectionStatus> {
    let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
    mutableState.withValue {
      $0.connectContinuation = continuation

      while !$0.connectionStatusBuffer.isEmpty {
        let status = $0.connectionStatusBuffer.removeFirst()
        $0.connectContinuation?.yield(status)
      }
    }
    return stream
  }

  func disconnect(code: Int?, reason: String?) {
  }
}
