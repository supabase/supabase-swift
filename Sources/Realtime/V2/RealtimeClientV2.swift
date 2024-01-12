//
//  RealtimeClientV2.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
import Foundation
@_spi(Internal) import _Helpers

public actor RealtimeClientV2 {
  public struct Configuration: Sendable {
    var url: URL
    var apiKey: String
    var headers: [String: String]
    var heartbeatInterval: TimeInterval
    var reconnectDelay: TimeInterval
    var disconnectOnSessionLoss: Bool
    var connectOnSubscribe: Bool

    public init(
      url: URL,
      apiKey: String,
      headers: [String: String],
      heartbeatInterval: TimeInterval = 15,
      reconnectDelay: TimeInterval = 7,
      disconnectOnSessionLoss: Bool = true,
      connectOnSubscribe: Bool = true
    ) {
      self.url = url
      self.apiKey = apiKey
      self.headers = headers
      self.heartbeatInterval = heartbeatInterval
      self.reconnectDelay = reconnectDelay
      self.disconnectOnSessionLoss = disconnectOnSessionLoss
      self.connectOnSubscribe = connectOnSubscribe
    }
  }

  public enum Status {
    case disconnected
    case connecting
    case connected
  }

  var accessToken: String?
  var ref = 0
  var pendingHeartbeatRef: Int?
  var heartbeatTask: Task<Void, Never>?
  var messageTask: Task<Void, Never>?
  var inFlightConnectionTask: Task<Void, Never>?

  public private(set) var subscriptions: [String: RealtimeChannelV2] = [:]
  var ws: WebSocketClientProtocol?

  let config: Configuration
  let makeWebSocketClient: (_ url: URL, _ headers: [String: String]) -> WebSocketClientProtocol

  let statusStreamManager = AsyncStreamManager<Status>()

  public var status: AsyncStream<Status> {
    statusStreamManager.makeStream()
  }

  init(
    config: Configuration,
    makeWebSocketClient: @escaping (_ url: URL, _ headers: [String: String])
      -> WebSocketClientProtocol
  ) {
    self.config = config
    self.makeWebSocketClient = makeWebSocketClient

    if let customJWT = config.headers["Authorization"]?.split(separator: " ").last {
      accessToken = String(customJWT)
    } else {
      accessToken = config.apiKey
    }
  }

  deinit {
    heartbeatTask?.cancel()
    messageTask?.cancel()
    subscriptions = [:]
    ws?.cancel()
  }

  public init(config: Configuration) {
    self.init(
      config: config,
      makeWebSocketClient: { url, headers in
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = headers
        return WebSocketClient(realtimeURL: url, configuration: configuration)
      }
    )
  }

  public func connect() async {
    await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async {
    if let inFlightConnectionTask {
      return await inFlightConnectionTask.value
    }

    inFlightConnectionTask = Task {
      defer { inFlightConnectionTask = nil }
      if reconnect {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.reconnectDelay))

        if Task.isCancelled {
          debug("reconnect cancelled, returning")
          return
        }
      }

      if statusStreamManager.value == .connected {
        debug("Websocket already connected")
        return
      }

      statusStreamManager.yield(.connecting)

      let realtimeURL = realtimeWebSocketURL

      let ws = makeWebSocketClient(realtimeURL, config.headers)
      self.ws = ws

      await ws.connect()

      let connectionStatus = await ws.status.first { _ in true }

      switch connectionStatus {
      case .open:
        statusStreamManager.yield(.connected)
        debug("Connected to realtime websocket")
        listenForMessages()
        startHeartbeating()
        if reconnect {
          await rejoinChannels()
        }

      case .close, .error, nil:
        debug(
          "Error while trying to connect to realtime websocket. Trying again in \(config.reconnectDelay) seconds."
        )
        disconnect()
        await connect(reconnect: true)
      }
    }

    await inFlightConnectionTask?.value
  }

  public func channel(
    _ topic: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
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
    subscriptions[channel.topic] = channel
  }

  public func removeChannel(_ channel: RealtimeChannelV2) async {
    if channel.statusStreamManager.value == .subscribed {
      await channel.unsubscribe()
    }

    subscriptions[channel.topic] = nil

    if subscriptions.isEmpty {
      debug("No more subscribed channel in socket")
      disconnect()
    }
  }

  private func rejoinChannels() async {
    // TODO: should we fire all subscribe calls concurrently?
    for channel in subscriptions.values {
      await channel.subscribe()
    }
  }

  private func listenForMessages() {
    messageTask = Task { [weak self] in
      guard let self, let ws = await ws else { return }

      do {
        for try await message in ws.receive() {
          await onMessage(message)
        }
      } catch {
        debug(
          "Error while listening for messages. Trying again in \(config.reconnectDelay) \(error)"
        )
        await disconnect()
        await connect(reconnect: true)
      }
    }
  }

  private func startHeartbeating() {
    heartbeatTask = Task { [weak self] in
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

  private func sendHeartbeat() async {
    if pendingHeartbeatRef != nil {
      pendingHeartbeatRef = nil
      debug("Heartbeat timeout. Trying to reconnect in \(config.reconnectDelay)")
      disconnect()
      await connect(reconnect: true)
      return
    }

    pendingHeartbeatRef = makeRef()

    await send(
      RealtimeMessageV2(
        joinRef: nil,
        ref: pendingHeartbeatRef?.description,
        topic: "phoenix",
        event: "heartbeat",
        payload: [:]
      )
    )
  }

  public func disconnect() {
    debug("Closing websocket connection")
    ref = 0
    messageTask?.cancel()
    heartbeatTask?.cancel()
    ws?.cancel()
    ws = nil
    statusStreamManager.yield(.disconnected)
  }

  public func setAuth(_ token: String?) async {
    accessToken = token

    for channel in subscriptions.values {
      if let token {
        await channel.updateAuth(jwt: token)
      }
    }
  }

  private func onMessage(_ message: RealtimeMessageV2) async {
    let channel = subscriptions[message.topic]

    if let ref = message.ref, Int(ref) == pendingHeartbeatRef {
      pendingHeartbeatRef = nil
      debug("heartbeat received")
    } else {
      debug("Received event \(message.event) for channel \(channel?.topic ?? "null")")
      await channel?.onMessage(message)
    }
  }

  func send(_ message: RealtimeMessageV2) async {
    do {
      try await ws?.send(message)
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
    ref += 1
    return ref
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
