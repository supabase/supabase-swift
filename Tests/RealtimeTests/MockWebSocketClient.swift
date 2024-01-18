//
//  MockWebSocketClient.swift
//
//
//  Created by Guilherme Souza on 29/12/23.
//

import ConcurrencyExtras
import Foundation
@testable import Realtime

final class MockWebSocketClient: WebSocketClientProtocol {
  private let continuation: AsyncStream<WebSocketClient.ConnectionStatus>.Continuation
  let status: AsyncStream<WebSocketClient.ConnectionStatus>

  struct MutableState {
    var sentMessages: [RealtimeMessageV2] = []
    var responsesHandlers: [(RealtimeMessageV2) -> RealtimeMessageV2?] = []
    var receiveContinuation: AsyncThrowingStream<RealtimeMessageV2, Error>.Continuation?
  }

  let mutableState = LockIsolated(MutableState())

  init() {
    (status, continuation) = AsyncStream<WebSocketClient.ConnectionStatus>.makeStream()
  }

  func connect() async {}

  func send(_ message: RealtimeMessageV2) async throws {
    mutableState.withValue {
      $0.sentMessages.append(message)

      if let response = $0.responsesHandlers.lazy.compactMap({ $0(message) }).first {
        $0.receiveContinuation?.yield(response)
      }
    }
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, Error> {
    mutableState.withValue {
      let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, Error>.makeStream()
      $0.receiveContinuation = continuation
      return stream
    }
  }

  func cancel() {
    mutableState.receiveContinuation?.finish()
  }

  func when(_ handler: @escaping (RealtimeMessageV2) -> RealtimeMessageV2?) {
    mutableState.withValue {
      $0.responsesHandlers.append(handler)
    }
  }

  func mockReceive(_ message: RealtimeMessageV2) {
    mutableState.receiveContinuation?.yield(message)
  }
}
