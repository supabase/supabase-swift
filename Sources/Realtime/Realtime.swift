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

  struct MutableState {
    var ref = 0
    var heartbeatRef: Int?
    var heartbeatTask: Task<Void, Never>?
    var messageTask: Task<Void, Never>?
    var subscriptions: [String: RealtimeChannelV2] = [:]
    var ws: WebSocketClientProtocol?

    mutating func makeRef() -> Int {
      ref += 1
      return ref
    }
  }

  let config: Configuration
  let makeWebSocketClient: (URL) -> WebSocketClientProtocol
  let mutableState = LockIsolated(MutableState())
  let _status: CurrentValueSubject<Status, Never> = CurrentValueSubject(.disconnected)
  public var status: Status { _status.value }

  public var subscriptions: [String: RealtimeChannelV2] {
    mutableState.subscriptions
  }

  init(config: Configuration, makeWebSocketClient: @escaping (URL) -> WebSocketClientProtocol) {
    self.config = config
    self.makeWebSocketClient = makeWebSocketClient
  }

  deinit {
    mutableState.withValue {
      $0.heartbeatTask?.cancel()
      $0.messageTask?.cancel()
      $0.subscriptions = [:]
      $0.ws?.cancel()
    }
  }

  public convenience init(config: Configuration) {
    self.init(
      config: config,
      makeWebSocketClient: { WebSocketClient(realtimeURL: $0, configuration: .default) }
    )
  }

  public func connect() async {
    await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async {
    if reconnect {
      try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.reconnectDelay))

      if Task.isCancelled {
        debug("reconnect cancelled, returning")
        return
      }
    }

    if _status.value == .connected {
      debug("Websocket already connected")
      return
    }

    _status.value = .connecting

    let realtimeURL = realtimeWebSocketURL

    let ws = mutableState.withValue {
      $0.ws = makeWebSocketClient(realtimeURL)
      return $0.ws!
    }

    let connectionStatus = try? await ws.connect().first { _ in true }

    if connectionStatus == .open {
      _status.value = .connected
      debug("Connected to realtime websocket")
      listenForMessages()
      startHeartbeating()
      if reconnect {
        await rejoinChannels()
      }
    } else {
      debug(
        "Error while trying to connect to realtime websocket. Trying again in \(config.reconnectDelay) seconds."
      )
      disconnect()
      await connect(reconnect: true)
    }
  }

  public func channel(
    _ topic: String,
    options: (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannelV2 {
    var config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: "")
    )
    options(&config)

    return RealtimeChannelV2(
      topic: "realtime:\(topic)",
      config: config,
      socket: self
    )
  }

  public func addChannel(_ channel: RealtimeChannelV2) {
    mutableState.withValue { $0.subscriptions[channel.topic] = channel }
  }

  public func removeChannel(_ channel: RealtimeChannelV2) async {
    if channel._status.value == .subscribed {
      await channel.unsubscribe()
    }

    mutableState.withValue {
      $0.subscriptions[channel.topic] = nil

      if $0.subscriptions.isEmpty {
        debug("No more subscribed channel in socket")
        disconnect()
      }
    }
  }

  private func rejoinChannels() async {
    // TODO: should we fire all subscribe calls concurrently?
    for channel in subscriptions.values {
      await channel.subscribe()
    }
  }

  private func listenForMessages() {
    mutableState.withValue {
      let ws = $0.ws

      $0.messageTask = Task { [weak self] in
        guard let self, let ws else { return }

        do {
          for try await message in ws.receive() {
            await onMessage(message)
          }
        } catch {
          debug(
            "Error while listening for messages. Trying again in \(config.reconnectDelay) \(error)"
          )
          disconnect()
          await connect(reconnect: true)
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
          await sendHeartbeat()
        }
      }
    }
  }

  private func sendHeartbeat() async {
    let timedOut = mutableState.withValue {
      if $0.heartbeatRef != nil {
        $0.heartbeatRef = nil
        return true
      }
      return false
    }

    if timedOut {
      debug("Heartbeat timeout. Trying to reconnect in \(config.reconnectDelay)")
      disconnect()
      await connect(reconnect: true)
      return
    }

    let heartbeatRef = mutableState.withValue {
      $0.heartbeatRef = $0.makeRef()
      return $0.heartbeatRef
    }

    await send(
      RealtimeMessageV2(
        joinRef: nil,
        ref: heartbeatRef?.description,
        topic: "phoenix",
        event: "heartbeat",
        payload: [:]
      )
    )
  }

  public func disconnect() {
    debug("Closing websocket connection")
    mutableState.withValue {
      $0.ref = 0
      $0.messageTask?.cancel()
      $0.heartbeatTask?.cancel()
      $0.ws?.cancel()
      $0.ws = nil
    }
    _status.value = .disconnected
  }

  private func onMessage(_ message: RealtimeMessageV2) async {
    let forward: () async -> Void = mutableState.withValue {
      let channel = $0.subscriptions[message.topic]

      if Int(message.ref ?? "") == $0.heartbeatRef {
        $0.heartbeatRef = 0
        debug("heartbeat received")
        return {}
      } else {
        debug("Received event \(message.event) for channel \(channel?.topic ?? "null")")
        return {
          await channel?.onMessage(message)
        }
      }
    }

    await forward()
  }

  func send(_ message: RealtimeMessageV2) async {
    do {
      try await mutableState.ws?.send(message)
    } catch {
      debug("""
      Failed to send message:
      \(message)

      Error:
      \(error)
      """)
    }
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

  private var broadcastURL: URL {
    config.url.appendingPathComponent("api/broadcast")
  }
}
