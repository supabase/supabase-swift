//
//  RealtimeMessageTests.swift
//
//
//  Created by Guilherme Souza on 26/06/24.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimeMessageTests {
  @Test
  func status() {
    var message = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "ok"])
    #expect(message.status == .ok)

    message = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "error"])
    #expect(message.status == .error)

    message = RealtimeMessage(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "invalid"])
    #expect(message.status?.rawValue == "invalid")
  }
}
