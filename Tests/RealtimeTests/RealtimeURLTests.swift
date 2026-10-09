//
//  RealtimeURLTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimeURLTests {
  @Test
  func webSocketSwitchesSchemeAndAppendsQuery() {
    let url = RealtimeURL.webSocket(
      baseURL: URL(string: "https://project.supabase.co/realtime/v1")!,
      apikey: "key", logLevel: "info")
    #expect(
      url.absoluteString
        == "wss://project.supabase.co/realtime/v1/websocket?apikey=key&vsn=2.0.0&log_level=info")
  }

  @Test
  func webSocketWithoutOptionalValues() {
    let url = RealtimeURL.webSocket(
      baseURL: URL(string: "http://localhost:54321/realtime/v1/")!, apikey: nil, logLevel: nil)
    #expect(url.absoluteString == "ws://localhost:54321/realtime/v1/websocket?vsn=2.0.0")
  }

  @Test
  func broadcastEncodesSegmentsAndPrivateFlag() {
    let url = RealtimeURL.broadcast(
      baseURL: URL(string: "https://project.supabase.co/realtime/v1/")!,
      topic: "room/1", event: "a b", isPrivate: true)
    #expect(
      url.absoluteString
        == "https://project.supabase.co/realtime/v1/api/broadcast/room%2F1/events/a%20b?private=true"
    )
  }
}
