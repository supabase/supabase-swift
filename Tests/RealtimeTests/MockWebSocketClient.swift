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

final class MockWebSocketClient: WebSocketClient {
  let sentMessages = LockIsolated<[RealtimeMessageV2]>([])
  func send(_ message: RealtimeMessageV2) async throws {
    sentMessages.withValue {
      $0.append(message)
    }

    if let callback = onCallback.value, let response = callback(message) {
      mockReceive(response)
    }
  }

  private let receiveContinuation =
    LockIsolated<AsyncThrowingStream<RealtimeMessageV2, any Error>.Continuation?>(nil)
  func mockReceive(_ message: RealtimeMessageV2) {
    receiveContinuation.value?.yield(message)
  }

  private let onCallback = LockIsolated<((RealtimeMessageV2) -> RealtimeMessageV2?)?>(nil)
  func on(_ callback: @escaping (RealtimeMessageV2) -> RealtimeMessageV2?) {
    onCallback.setValue(callback)
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, any Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, any Error>.makeStream()
    receiveContinuation.setValue(continuation)
    return stream
  }

  private let connectContinuation = LockIsolated<AsyncStream<ConnectionStatus>.Continuation?>(nil)
  func mockConnect(_ status: ConnectionStatus) {
    connectContinuation.value?.yield(status)
  }

  func connect() -> AsyncStream<ConnectionStatus> {
    let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
    connectContinuation.setValue(continuation)
    return stream
  }

  func disconnect(closeCode _: URLSessionWebSocketTask.CloseCode) {}
}
