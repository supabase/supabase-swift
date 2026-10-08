//
//  RealtimeMessageV2Tests.swift
//
//
//  Created by Guilherme Souza on 26/06/24.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimeMessageV2Tests {
  @Test
  func status() {
    var message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "ok"])
    #expect(message.status == .ok)

    message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "error"])
    #expect(message.status == .error)

    message = RealtimeMessageV2(
      joinRef: nil, ref: nil, topic: "heartbeat", event: "event", payload: ["status": "invalid"])
    #expect(message.status?.rawValue == "invalid")
  }
}
