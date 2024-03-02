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
  var status: AsyncStream<Realtime.ConnectionStatus> = .never

  func send(_ message: Realtime.RealtimeMessageV2) async throws {

  }
  
  func receive() -> AsyncThrowingStream<Realtime.RealtimeMessageV2, Error> {
    .never
  }
  
  func connect() {

  }
  
  func cancel() {

  }
}
