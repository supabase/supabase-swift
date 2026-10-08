//
//  RealtimeClientOptionsTests.swift
//  Realtime
//
//  Created by Guilherme Souza on 08/10/26.
//

import Foundation
import Testing

@testable import Realtime

@Suite
struct RealtimeClientOptionsTests {
  @Test
  func defaults() {
    let options = RealtimeClientOptions()

    #expect(options.headers.isEmpty)
    #expect(options.heartbeatInterval == .seconds(25))
    #expect(options.heartbeatTimeout == .seconds(10))
    #expect(options.timeout == .seconds(15))
    #expect(options.reconnect == .fullJitter(base: .seconds(1), cap: .seconds(30)))
    #expect(options.rejoin == .steps([.seconds(1), .seconds(2), .seconds(5), .seconds(10)]))
    #expect(options.connectOnSubscribe)
    #expect(options.disconnectOnEmptyChannelsAfter == .seconds(50))
    #expect(options.handleAppLifecycle)
    #expect(options.maximumMessageSize == 5_000_000)
    #expect(options.serverLogLevel == nil)
    #expect(options.webSocketTransport == nil)
    #expect(options.accessToken == nil)
  }

  @Test
  func serverLogLevelsMatchTheServerValues() {
    #expect(RealtimeServerLogLevel.info.rawValue == "info")
    #expect(RealtimeServerLogLevel.warning.rawValue == "warning")
    #expect(RealtimeServerLogLevel.error.rawValue == "error")
    #expect(RealtimeServerLogLevel(rawValue: "debug").rawValue == "debug")
  }

  @Test
  func engineConfigurationCarriesTheOptions() {
    var options = RealtimeClientOptions()
    options.headers[.apikey] = "key"
    options.heartbeatInterval = .seconds(5)
    options.heartbeatTimeout = .seconds(3)
    options.timeout = .seconds(7)
    options.reconnect = .steps([.seconds(2)])
    options.rejoin = .steps([.seconds(4)])
    options.connectOnSubscribe = false
    options.disconnectOnEmptyChannelsAfter = .seconds(9)
    options.serverLogLevel = .error

    let configuration = RealtimeClient.engineConfiguration(
      url: URL(string: "https://example.supabase.co/realtime/v1")!, options: options)

    #expect(
      configuration.url.absoluteString
        == "wss://example.supabase.co/realtime/v1/websocket?apikey=key&vsn=2.0.0&log_level=error")
    #expect(configuration.headers[.apikey] == "key")
    #expect(configuration.headers[.xClientInfo]?.hasPrefix("realtime-swift/") == true)
    #expect(configuration.heartbeatInterval == .seconds(5))
    #expect(configuration.heartbeatTimeout == .seconds(3))
    #expect(configuration.timeout == .seconds(7))
    #expect(configuration.connection.reconnect == .steps([.seconds(2)]))
    #expect(configuration.connection.idleDisconnectAfter == .seconds(9))
    #expect(configuration.channel.rejoin == .steps([.seconds(4)]))
    #expect(!configuration.connectOnSubscribe)
  }
}
