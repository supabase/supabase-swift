//
//  Realtime.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import Combine
import ConcurrencyExtras
import Foundation
@_spi(Internal) import _Helpers

public protocol AuthTokenProvider: Sendable {
  func authToken() async -> String?
}

public final class Realtime: @unchecked Sendable {
  public struct Configuration: Sendable {
    var url: URL
    var apiKey: String
    var authTokenProvider: AuthTokenProvider?
    var heartbeatInterval: TimeInterval
    var reconnectDelay: TimeInterval
    var jwtToken: String?
    var disconnectOnSessionLoss: Bool
    var connectOnSubscribe: Bool

    public init(
      url: URL,
      apiKey: String,
      authTokenProvider: AuthTokenProvider?,
      heartbeatInterval: TimeInterval = 15,
      reconnectDelay: TimeInterval = 7,
      jwtToken: String? = nil,
      disconnectOnSessionLoss: Bool = true,
      connectOnSubscribe: Bool = true
    ) {
      self.url = url
      self.apiKey = apiKey
      self.authTokenProvider = authTokenProvider
      self.heartbeatInterval = heartbeatInterval
      self.reconnectDelay = reconnectDelay
      self.jwtToken = jwtToken
      self.disconnectOnSessionLoss = disconnectOnSessionLoss
      self.connectOnSubscribe = connectOnSubscribe
    }
  }

  public enum Status {
    case disconnected
    case connecting
    case connected
  }

  let config: Configuration
  let makeWebSocketClient: (URL) -> WebSocketClientProtocol

  let _status = CurrentValueSubject<Status, Never>(.disconnected)
  public var status: Status {
    _status.value
  }

  public var subscriptions: [String: RealtimeChannel] {
    mutableState.subscriptions
  }

  struct MutableState {
    var ref = 0
    var heartbeatRef = 0
    var heartbeatTask: Task<Void, Never>?
    var messageTask: Task<Void, Never>?
    var subscriptions: [String: RealtimeChannel] = [:]
    var ws: WebSocketClientProtocol?

    mutating func makeRef() -> Int {
      ref += 1
      return ref
    }
  }

  let mutableState = LockIsolated(MutableState())

  init(config: Configuration, makeWebSocketClient: @escaping (URL) -> WebSocketClientProtocol) {
    self.config = config
    self.makeWebSocketClient = makeWebSocketClient
  }

  deinit {
    mutableState.withValue {
      $0.heartbeatTask?.cancel()
      $0.messageTask?.cancel()
      $0.ws?.cancel()
    }
  }

  public convenience init(config: Configuration) {
    self.init(
      config: config,
      makeWebSocketClient: { WebSocketClient(realtimeURL: $0, configuration: .default) }
    )
  }

  public func connect() async throws {
    try await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async throws {
    if reconnect {
      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.reconnectDelay))

      if Task.isCancelled {
        debug("reconnect cancelled, returning")
        return
      }
    }

    if status == .connected {
      debug("Websocket already connected")
      return
    }

    _status.value = .connecting

    let realtimeURL = realtimeWebSocketURL

    let ws = mutableState.withValue {
      $0.ws = makeWebSocketClient(realtimeURL)
      return $0.ws!
    }

    let connectionStatus = try await ws.connect().first { _ in true }

    if connectionStatus == .open {
      _status.value = .connected
      debug("Connected to realtime websocket")
      listenForMessages()
      startHeartbeating()
      if reconnect {
        try await rejoinChannels()
      }
    } else {
      debug(
        "Error while trying to connect to realtime websocket. Trying again in \(config.reconnectDelay) seconds."
      )
      disconnect()
      try await connect(reconnect: true)
    }
  }

  public func channel(
    _ topic: String,
    options: (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannel {
    var config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "")
    )
    options(&config)

    return RealtimeChannel(
      topic: "realtime:\(topic)",
      socket: self,
      broadcastJoinConfig: config.broadcast,
      presenceJoinConfig: config.presence
    )
  }

  public func addChannel(_ channel: RealtimeChannel) {
    mutableState.withValue { $0.subscriptions[channel.topic] = channel }
  }

  public func removeChannel(_ channel: RealtimeChannel) async throws {
    if channel.status == .subscribed {
      try await channel.unsubscribe()
    }

    mutableState.withValue {
      $0.subscriptions[channel.topic] = nil
    }
  }

  private func rejoinChannels() async throws {
    // TODO: should we fire all subscribe calls concurrently?
    for channel in subscriptions.values {
      try await channel.subscribe()
    }
  }

  private func listenForMessages() {
    mutableState.withValue {
      let ws = $0.ws

      $0.messageTask = Task { [weak self] in
        guard let self, let ws else { return }

        do {
          for try await message in ws.receive() {
            try await onMessage(message)
          }
        } catch {
          debug(
            "Error while listening for messages. Trying again in \(config.reconnectDelay) \(error)"
          )
          disconnect()
          try? await connect(reconnect: true)
        }
      }
    }
  }

  private func startHeartbeating() {
    mutableState.withValue {
      $0.heartbeatTask = Task { [weak self] in
        guard let self else { return }

        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.heartbeatInterval))
          if Task.isCancelled {
            break
          }
          try? await sendHeartbeat()
        }
      }
    }
  }

  private func sendHeartbeat() async throws {
    let timedOut = mutableState.withValue {
      if $0.heartbeatRef != 0 {
        $0.heartbeatRef = 0
        $0.ref = 0
        return true
      }
      return false
    }

    if timedOut {
      debug("Heartbeat timeout. Trying to reconnect in \(config.reconnectDelay)")
      disconnect()
      try await connect(reconnect: true)
      return
    }

    let heartbeatRef = mutableState.withValue {
      $0.heartbeatRef = $0.makeRef()
      return $0.heartbeatRef
    }

    try await mutableState.ws?.send(_RealtimeMessage(
      joinRef: nil,
      ref: heartbeatRef.description,
      topic: "phoenix",
      event: "heartbeat",
      payload: [:]
    ))
  }

  public func disconnect() {
    debug("Closing websocket connection")
    mutableState.withValue {
      $0.messageTask?.cancel()
      $0.ws?.cancel()
      $0.ws = nil
      $0.heartbeatTask?.cancel()
    }
    _status.value = .disconnected
  }

  private func onMessage(_ message: _RealtimeMessage) async throws {
    guard let channel = subscriptions[message.topic] else {
      return
    }

    let heartbeatReceived = mutableState.withValue {
      if Int(message.ref ?? "") == $0.heartbeatRef {
        $0.heartbeatRef = 0
        return true
      }
      return false
    }

    if heartbeatReceived {
      debug("heartbeat received")
    } else {
      debug("Received event \(message.event) for channel \(channel.topic)")
      try await channel.onMessage(message)
    }
  }

  func send(_ message: _RealtimeMessage) async throws {
    try await mutableState.ws?.send(message)
  }

  func makeRef() -> Int {
    mutableState.withValue { $0.makeRef() }
  }

  private var realtimeBaseURL: URL {
    guard var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false) else {
      return config.url
    }

    if components.scheme == "https" {
      components.scheme = "wss"
    } else if components.scheme == "http" {
      components.scheme = "ws"
    }

    guard let url = components.url else {
      return config.url
    }

    return url
  }

  private var realtimeWebSocketURL: URL {
    guard var components = URLComponents(url: realtimeBaseURL, resolvingAgainstBaseURL: false)
    else {
      return realtimeBaseURL
    }

    components.queryItems = components.queryItems ?? []
    components.queryItems!.append(URLQueryItem(name: "apikey", value: config.apiKey))
    components.queryItems!.append(URLQueryItem(name: "vsn", value: "1.0.0"))

    components.path.append("/websocket")
    components.path = components.path.replacingOccurrences(of: "//", with: "/")

    guard let url = components.url else {
      return realtimeBaseURL
    }

    return url
  }

  var broadcastURL: URL {
    config.url.appendingPathComponent("api/broadcast")
  }
}
