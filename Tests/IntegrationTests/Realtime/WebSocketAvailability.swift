//
//  WebSocketAvailability.swift
//  IntegrationTests
//
//  Created by Guilherme Souza on 08/10/26.
//

// libcurl has no WebSocket support, so `URLSessionWebSocketTask` never connects on Linux and Android.
enum WebSocketAvailability {
  #if os(Linux) || os(Android)
    static let isMissing = true
  #else
    static let isMissing = false
  #endif
}
