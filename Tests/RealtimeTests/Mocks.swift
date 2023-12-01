//
//  Mocks.swift
//
//
//  Created by Guilherme Souza on 01/12/23.
//

import ConcurrencyExtras
import Foundation
@testable import Realtime

final class HeartbeatTimerMock: HeartbeatTimerProtocol {
  let startCallCount = LockIsolated(0)
  func start(_: @escaping @Sendable () -> Void) {
    startCallCount.withValue { $0 += 1 }
  }

  func stop() {}
}

final class TimeoutTimerMock: TimeoutTimerProtocol {
  func setHandler(_: @escaping @Sendable () -> Void) {}

  func setTimerCalculation(_: @escaping @Sendable (Int) -> TimeInterval) {}

  let resetCallCount = LockIsolated(0)
  func reset() {
    resetCallCount.withValue { $0 += 1 }
  }

  func scheduleTimeout() {}
}

final class PhoenixTransportMock: PhoenixTransport {
  var readyState: PhoenixTransportReadyState = .closed
  weak var delegate: PhoenixTransportDelegate?

  private(set) var connectCallCount = 0
  private(set) var disconnectCallCount = 0
  private(set) var sendCallCount = 0

  private(set) var connectHeaders: [String: String]?
  private(set) var disconnectCode: Int?
  private(set) var disconnectReason: String?
  private(set) var sendData: Data?

  func connect(with headers: [String: String]) {
    connectCallCount += 1
    connectHeaders = headers

    delegate?.onOpen(response: nil)
  }

  func disconnect(code: Int, reason: String?) {
    disconnectCallCount += 1
    disconnectCode = code
    disconnectReason = reason

    delegate?.onClose(code: code, reason: reason)
  }

  func send(data: Data) {
    sendCallCount += 1
    sendData = data

    delegate?.onMessage(message: data)
  }
}
