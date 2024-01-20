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

extension WebSocketClient {
  static let mock = WebSocketClient(
    status: .never,
    send: unimplemented("WebSocketClient.send"),
    receive: unimplemented("WebSocketClient.receive"),
    connect: unimplemented("WebSocketClient.connect"),
    cancel: unimplemented("WebSocketClient.cancel")
  )
}
