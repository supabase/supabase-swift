//
//  RealtimeClientV2.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import _Helpers
import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking

  let NSEC_PER_SEC: UInt64 = 1000000000
#endif

public typealias JSONObject = _Helpers.JSONObject

public actor RealtimeClientV2 {
  public struct Configuration: Sendable {
    var url: URL
    var apiKey: String
    var headers: [String: String]
    var heartbeatInterval: TimeInterval
    var reconnectDelay: TimeInterval
    var timeoutInterval: TimeInterval
    var disconnectOnSessionLoss: Bool
    var connectOnSubscribe: Bool
    var logger: (any SupabaseLogger)?

    public init(
      url: URL,
      apiKey: String,
      headers: [String: String] = [:],
      heartbeatInterval: TimeInterval = 15,
      reconnectDelay: TimeInterval = 7,
      timeoutInterval: TimeInterval = 10,
      disconnectOnSessionLoss: Bool = true,
      connectOnSubscribe: Bool = true,
      logger: (any SupabaseLogger)? = nil
    ) {
      self.url = url
      self.apiKey = apiKey
      self.headers = headers
      self.heartbeatInterval = heartbeatInterval
      self.reconnectDelay = reconnectDelay
      self.timeoutInterval = timeoutInterval
      self.disconnectOnSessionLoss = disconnectOnSessionLoss
      self.connectOnSubscribe = connectOnSubscribe
      self.logger = logger
    }
  }

  public enum Status: Sendable, CustomStringConvertible {
    case disconnected
    case connecting
    case connected

    public var description: String {
      switch self {
      case .disconnected: "Disconnected"
      case .connecting: "Connecting"
      case .connected: "Connected"
      }
    }
  }

  let config: Configuration
  let ws: any WebSocketClient

  var accessToken: String?
  var ref = 0
  var pendingHeartbeatRef: Int?

  var heartbeatTask: Task<Void, Never>?
  var messageTask: Task<Void, Never>?
  var connectionTask: Task<Void, Never>?

  public private(set) var subscriptions: [String: RealtimeChannelV2] = [:]

  private let statusEventEmitter = EventEmitter<Status>(initialEvent: .disconnected)

  public var statusChange: AsyncStream<Status> {
    statusEventEmitter.stream()
  }

  public private(set) var status: Status {
    get { statusEventEmitter.lastEvent.value }
    set { statusEventEmitter.emit(newValue) }
  }

  public func onStatusChange(
    _ listener: @escaping @Sendable (Status) -> Void
  ) -> ObservationToken {
    statusEventEmitter.attach(listener)
  }

  public init(config: Configuration) {
    self.init(config: config, ws: WebSocket(config: config))
  }

  init(config: Configuration, ws: any WebSocketClient) {
    self.config = config
    self.ws = ws

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
  }

  /// Connects the socket.
  ///
  /// Suspends until connected.
  public func connect() async {
    await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async {
    if status == .disconnected {
      connectionTask = Task {
        if reconnect {
          try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.reconnectDelay))

          if Task.isCancelled {
            config.logger?.debug("Reconnect cancelled, returning")
            return
          }
        }

        if status == .connected {
          config.logger?.debug("WebsSocket already connected")
          return
        }

        status = .connecting

        for await connectionStatus in ws.connect() {
          if Task.isCancelled {
            break
          }

          switch connectionStatus {
          case .connected:
            await onConnected(reconnect: reconnect)

          case .disconnected:
            await onDisconnected()

          case let .error(error):
            await onError(error)
          }
        }
      }
    }

    _ = await statusChange.first { @Sendable in $0 == .connected }
  }

  private func onConnected(reconnect: Bool) async {
    status = .connected
    config.logger?.debug("Connected to realtime WebSocket")
    listenForMessages()
    startHeartbeating()
    if reconnect {
      await rejoinChannels()
    }
  }

  private func onDisconnected() async {
    config.logger?
      .debug(
        "WebSocket disconnected. Trying again in \(config.reconnectDelay)"
      )
    await reconnect()
  }

  private func onError(_ error: (any Error)?) async {
    config.logger?
      .debug(
        "WebSocket error \(error?.localizedDescription ?? "<none>"). Trying again in \(config.reconnectDelay)"
      )
    await reconnect()
  }

  private func reconnect() async {
    disconnect()
    await connect(reconnect: true)
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
      socket: self,
      logger: self.config.logger
    )
  }

  public func addChannel(_ channel: RealtimeChannelV2) {
    subscriptions[channel.topic] = channel
  }

  public func removeChannel(_ channel: RealtimeChannelV2) async {
    if await channel.status == .subscribed {
      await channel.unsubscribe()
    }

    subscriptions[channel.topic] = nil

    if subscriptions.isEmpty {
      config.logger?.debug("No more subscribed channel in socket")
      disconnect()
    }
  }

  public func removeAllChannels() async {
    for channel in subscriptions.values {
      await removeChannel(channel)
    }
  }

  private func rejoinChannels() async {
    for channel in subscriptions.values {
      await channel.subscribe()
    }
  }

  private func listenForMessages() {
    messageTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await message in ws.receive() {
          if Task.isCancelled {
            return
          }

          await onMessage(message)
        }
      } catch {
        config.logger?.debug(
          "Error while listening for messages. Trying again in \(config.reconnectDelay) \(error)"
        )
        await reconnect()
      }
    }
  }

  private func startHeartbeating() {
    heartbeatTask = Task { [weak self, config] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(config.heartbeatInterval))
        if Task.isCancelled {
          break
        }
        await self?.sendHeartbeat()
      }
    }
  }

  private func sendHeartbeat() async {
    if pendingHeartbeatRef != nil {
      pendingHeartbeatRef = nil
      config.logger?.debug("Heartbeat timeout")

      await reconnect()
      return
    }

    pendingHeartbeatRef = makeRef()

    await push(
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
    config.logger?.debug("Closing WebSocket connection")
    ref = 0
    messageTask?.cancel()
    heartbeatTask?.cancel()
    connectionTask?.cancel()
    ws.disconnect()
    status = .disconnected
  }

  /// Sets the JWT access token used for channel subscription authorization and Realtime RLS.
  /// - Parameter token: A JWT string.
  public func setAuth(_ token: String?) async {
    accessToken = token

    for channel in subscriptions.values {
      if let token, await channel.status == .subscribed {
        await channel.updateAuth(jwt: token)
      }
    }
  }

  private func onMessage(_ message: RealtimeMessageV2) async {
    let channel = subscriptions[message.topic]

    if let ref = message.ref, Int(ref) == pendingHeartbeatRef {
      pendingHeartbeatRef = nil
      config.logger?.debug("heartbeat received")
    } else {
      config.logger?
        .debug("Received event \(message.event) for channel \(channel?.topic ?? "null")")
      await channel?.onMessage(message)
    }
  }

  /// Push out a message if the socket is connected.
  /// - Parameter message: The message to push through the socket.
  public func push(_ message: RealtimeMessageV2) async {
    guard status == .connected else {
      config.logger?.warning("Trying to push a message while socket is not connected. This is not supported yet.")
      return
    }

    do {
      try await ws.send(message)
    } catch {
      config.logger?.debug("""
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
}

extension RealtimeClientV2.Configuration {
  var realtimeBaseURL: URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }

    if components.scheme == "https" {
      components.scheme = "wss"
    } else if components.scheme == "http" {
      components.scheme = "ws"
    }

    guard let url = components.url else {
      return url
    }

    return url
  }

  var realtimeWebSocketURL: URL {
    guard var components = URLComponents(url: realtimeBaseURL, resolvingAgainstBaseURL: false)
    else {
      return realtimeBaseURL
    }

    components.queryItems = components.queryItems ?? []
    components.queryItems!.append(URLQueryItem(name: "apikey", value: apiKey))
    components.queryItems!.append(URLQueryItem(name: "vsn", value: "1.0.0"))

    components.path.append("/websocket")
    components.path = components.path.replacingOccurrences(of: "//", with: "/")

    guard let url = components.url else {
      return realtimeBaseURL
    }

    return url
  }

  private var broadcastURL: URL {
    url.appendingPathComponent("api/broadcast")
  }
}
