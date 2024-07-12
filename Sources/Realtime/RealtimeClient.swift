//
//  RealtimeClient.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public typealias JSONObject = Helpers.JSONObject

@available(*, deprecated, renamed: "RealtimeClient")
public typealias RealtimeClientV2 = RealtimeClient

public final class RealtimeClient: Sendable {
  @available(*, deprecated, renamed: "RealtimeClientOptions")
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

  struct MutableState {
    var accessToken: String?
    var ref = 0
    var pendingHeartbeatRef: Int?
    var heartbeatTask: Task<Void, Never>?
    var messageTask: Task<Void, Never>?
    var connectionTask: Task<Void, Never>?
    var subscriptions: [String: RealtimeChannel] = [:]
  }

  let url: URL
  let options: RealtimeClientOptions
  let ws: any WebSocketClient
  let mutableState = LockIsolated(MutableState())
  let apikey: String?

  public var subscriptions: [String: RealtimeChannel] {
    mutableState.subscriptions
  }

  private let statusEventEmitter = EventEmitter<Status>(initialEvent: .disconnected)

  /// AsyncStream that emits when connection status change.
  ///
  /// You can also use ``onStatusChange(_:)`` for a closure based method.
  public var statusChange: AsyncStream<Status> {
    statusEventEmitter.stream()
  }

  /// The current connection status.
  public private(set) var status: Status {
    get { statusEventEmitter.lastEvent }
    set { statusEventEmitter.emit(newValue) }
  }

  /// Listen for connection status changes.
  /// - Parameter listener: Closure that will be called when connection status changes.
  /// - Returns: An observation handle that can be used to stop listening.
  ///
  /// - Note: Use ``statusChange`` if you prefer to use Async/Await.
  public func onStatusChange(
    _ listener: @escaping @Sendable (Status) -> Void
  ) -> ObservationToken {
    statusEventEmitter.attach(listener)
  }

  @available(*, deprecated, renamed: "RealtimeClient.init(url:options:)")
  public convenience init(config: Configuration) {
    self.init(
      url: config.url,
      options: RealtimeClientOptions(
        headers: config.headers,
        heartbeatInterval: config.heartbeatInterval,
        reconnectDelay: config.reconnectDelay,
        timeoutInterval: config.timeoutInterval,
        disconnectOnSessionLoss: config.disconnectOnSessionLoss,
        connectOnSubscribe: config.connectOnSubscribe,
        logger: config.logger
      )
    )
  }

  public convenience init(url: URL, options: RealtimeClientOptions) {
    self.init(
      url: url,
      options: options,
      ws: WebSocket(
        realtimeURL: Self.realtimeWebSocketURL(
          baseURL: Self.realtimeBaseURL(url: url),
          apikey: options.apikey
        ),
        options: options
      )
    )
  }

  init(url: URL, options: RealtimeClientOptions, ws: any WebSocketClient) {
    self.url = url
    self.options = options
    self.ws = ws
    apikey = options.apikey

    mutableState.withValue {
      $0.accessToken = options.accessToken ?? options.apikey
    }
  }

  deinit {
    mutableState.withValue {
      $0.heartbeatTask?.cancel()
      $0.messageTask?.cancel()
      $0.subscriptions = [:]
    }
  }

  /// Connects the socket.
  ///
  /// Suspends until connected.
  public func connect() async {
    await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async {
    if status == .disconnected {
      let connectionTask = Task {
        if reconnect {
          try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(options.reconnectDelay))

          if Task.isCancelled {
            options.logger?.debug("Reconnect cancelled, returning")
            return
          }
        }

        if status == .connected {
          options.logger?.debug("WebsSocket already connected")
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

      mutableState.withValue {
        $0.connectionTask = connectionTask
      }
    }

    _ = await statusChange.first { @Sendable in $0 == .connected }
  }

  private func onConnected(reconnect: Bool) async {
    status = .connected
    options.logger?.debug("Connected to realtime WebSocket")
    listenForMessages()
    startHeartbeating()
    if reconnect {
      await rejoinChannels()
    }
  }

  private func onDisconnected() async {
    options.logger?
      .debug(
        "WebSocket disconnected. Trying again in \(options.reconnectDelay)"
      )
    await reconnect()
  }

  private func onError(_ error: (any Error)?) async {
    options.logger?
      .debug(
        "WebSocket error \(error?.localizedDescription ?? "<none>"). Trying again in \(options.reconnectDelay)"
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
  ) -> RealtimeChannel {
    var config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: ""),
      isPrivate: false
    )
    options(&config)

    return RealtimeChannel(
      topic: "realtime:\(topic)",
      config: config,
      socket: Socket(client: self),
      logger: self.options.logger
    )
  }

  public func addChannel(_ channel: RealtimeChannel) {
    mutableState.withValue {
      $0.subscriptions[channel.topic] = channel
    }
  }

  public func removeChannel(_ channel: RealtimeChannel) async {
    if channel.status == .subscribed {
      await channel.unsubscribe()
    }

    mutableState.withValue {
      $0.subscriptions[channel.topic] = nil
    }

    if subscriptions.isEmpty {
      options.logger?.debug("No more subscribed channel in socket")
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
    let messageTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await message in ws.receive() {
          if Task.isCancelled {
            return
          }

          await onMessage(message)
        }
      } catch {
        options.logger?.debug(
          "Error while listening for messages. Trying again in \(options.reconnectDelay) \(error)"
        )
        await reconnect()
      }
    }
    mutableState.withValue {
      $0.messageTask = messageTask
    }
  }

  private func startHeartbeating() {
    let heartbeatTask = Task { [weak self, options] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(options.heartbeatInterval))
        if Task.isCancelled {
          break
        }
        await self?.sendHeartbeat()
      }
    }
    mutableState.withValue {
      $0.heartbeatTask = heartbeatTask
    }
  }

  private func sendHeartbeat() async {
    let pendingHeartbeatRef: Int? = mutableState.withValue {
      if $0.pendingHeartbeatRef != nil {
        $0.pendingHeartbeatRef = nil
        return nil
      }

      let ref = makeRef()
      $0.pendingHeartbeatRef = ref
      return ref
    }

    if let pendingHeartbeatRef {
      await push(
        RealtimeMessage(
          joinRef: nil,
          ref: pendingHeartbeatRef.description,
          topic: "phoenix",
          event: "heartbeat",
          payload: [:]
        )
      )
    } else {
      options.logger?.debug("Heartbeat timeout")
      await reconnect()
    }
  }

  public func disconnect() {
    options.logger?.debug("Closing WebSocket connection")
    mutableState.withValue {
      $0.ref = 0
      $0.messageTask?.cancel()
      $0.heartbeatTask?.cancel()
      $0.connectionTask?.cancel()
    }
    ws.disconnect()
    status = .disconnected
  }

  /// Sets the JWT access token used for channel subscription authorization and Realtime RLS.
  /// - Parameter token: A JWT string.
  public func setAuth(_ token: String?) async {
    mutableState.withValue {
      $0.accessToken = token
    }

    for channel in subscriptions.values {
      if let token, channel.status == .subscribed {
        await channel.updateAuth(jwt: token)
      }
    }
  }

  private func onMessage(_ message: RealtimeMessage) async {
    mutableState.withValue {
      let channel = $0.subscriptions[message.topic]

      if let ref = message.ref, Int(ref) == $0.pendingHeartbeatRef {
        $0.pendingHeartbeatRef = nil
        options.logger?.debug("heartbeat received")
      } else {
        options.logger?
          .debug("Received event \(message.event) for channel \(channel?.topic ?? "null")")
        channel?.onMessage(message)
      }
    }
  }

  /// Push out a message if the socket is connected.
  /// - Parameter message: The message to push through the socket.
  public func push(_ message: RealtimeMessage) async {
    guard status == .connected else {
      options.logger?.warning("Trying to push a message while socket is not connected. This is not supported yet.")
      return
    }

    do {
      try await ws.send(message)
    } catch {
      options.logger?.debug("""
      Failed to send message:
      \(message)

      Error:
      \(error)
      """)
    }
  }

  func makeRef() -> Int {
    mutableState.withValue {
      $0.ref += 1
      return $0.ref
    }
  }

  static func realtimeBaseURL(url: URL) -> URL {
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

  static func realtimeWebSocketURL(baseURL: URL, apikey: String?) -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    else {
      return baseURL
    }

    components.queryItems = components.queryItems ?? []
    if let apikey {
      components.queryItems!.append(URLQueryItem(name: "apikey", value: apikey))
    }
    components.queryItems!.append(URLQueryItem(name: "vsn", value: "1.0.0"))

    components.path.append("/websocket")
    components.path = components.path.replacingOccurrences(of: "//", with: "/")

    guard let url = components.url else {
      return baseURL
    }

    return url
  }

  private var broadcastURL: URL {
    url.appendingPathComponent("api/broadcast")
  }
}
