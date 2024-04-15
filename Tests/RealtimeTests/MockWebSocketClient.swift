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
  let sentMessages = LockIsolated<[RealtimeMessage]>([])
  func send(_ message: RealtimeMessage) async throws {
    sentMessages.withValue {
      $0.append(message)
    }

    if let callback = onCallback.value, let response = callback(message) {
      mockReceive(response)
    }
  }

  private let receiveContinuation =
    LockIsolated<AsyncThrowingStream<RealtimeMessage, any Error>.Continuation?>(nil)
  func mockReceive(_ message: RealtimeMessage) {
    receiveContinuation.value?.yield(message)
  }

  private let onCallback = LockIsolated<((RealtimeMessage) -> RealtimeMessage?)?>(nil)
  func on(_ callback: @escaping (RealtimeMessage) -> RealtimeMessage?) {
    onCallback.setValue(callback)
  }

  func receive() -> AsyncThrowingStream<RealtimeMessage, any Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessage, any Error>.makeStream()
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
