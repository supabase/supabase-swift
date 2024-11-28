//
//  RealtimeClientV2.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
import Foundation
import Helpers
import WebSocket
import WebSocketFoundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public typealias JSONObject = Helpers.JSONObject

public typealias WebSocketFactory = (_ url: URL, _ headers: [String: String]) async throws -> (
  any WebSocket
)

public actor RealtimeClientV2 {
  var accessToken: String?
  var ref: UInt64 = 0
  var pendingHeartbeatRef: String?

  /// Long-running task that keeps sending heartbeat messages.
  var heartbeatTask: Task<Void, Never>?

  /// Long-running task for listening for incoming messages from WebSocket.
  var messageTask: Task<Void, Never>?

  var connectionTask: Task<Void, Never>?
  var _channels: [String: RealtimeChannelV2] = [:]
  var sendBuffer: [@Sendable () -> Void] = []
  var ws: (any WebSocket)?

  let url: URL
  let options: RealtimeClientOptions
  let wsFactory: WebSocketFactory
  let http: any HTTPClientType
  let apikey: String?

  /// All managed channels indexed by their topics.
  public var channels: [String: RealtimeChannelV2] {
    _channels
  }

  private let statusEventEmitter = EventEmitter<RealtimeClientStatus>(initialEvent: .disconnected)

  /// Listen for connection status changes.
  ///
  /// You can also use ``onStatusChange(_:)`` for a closure based method.
  public var statusChange: AsyncStream<RealtimeClientStatus> {
    statusEventEmitter.stream()
  }

  /// The current connection status.
  public private(set) var status: RealtimeClientStatus {
    get { statusEventEmitter.lastEvent }
    set { statusEventEmitter.emit(newValue) }
  }

  /// Listen for connection status changes.
  /// - Parameter listener: Closure that will be called when connection status changes.
  /// - Returns: An observation handle that can be used to stop listening.
  ///
  /// - Note: Use ``statusChange`` if you prefer to use Async/Await.
  public func onStatusChange(
    _ listener: @escaping @Sendable (RealtimeClientStatus) -> Void
  ) -> RealtimeSubscription {
    statusEventEmitter.attach(listener)
  }

  public init(url: URL, options: RealtimeClientOptions) {
    var interceptors: [any HTTPClientInterceptor] = []

    if let logger = options.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    self.init(
      url: url,
      options: options,
      wsFactory: {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = $1
        return try await URLSessionWebSocket.connect(
          to: Self.realtimeWebSocketURL(
            baseURL: Self.realtimeBaseURL(url: $0),
            apikey: options.apikey
          ),
          configuration: configuration
        )
      },
      http: HTTPClient(
        fetch: options.fetch ?? { try await URLSession.shared.data(for: $0) },
        interceptors: interceptors
      )
    )
  }

  init(
    url: URL,
    options: RealtimeClientOptions,
    wsFactory: @escaping WebSocketFactory,
    http: any HTTPClientType
  ) {
    self.url = url
    self.options = options
    self.wsFactory = wsFactory
    self.http = http
    apikey = options.apikey

    accessToken = options.accessToken ?? options.apikey
  }

  deinit {
    heartbeatTask?.cancel()
    messageTask?.cancel()
    _channels = [:]
  }

  /// Connects the socket.
  ///
  /// Suspends until connected.
  public func connect() async {
    await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async {
    if let connectionTask { await connectionTask.value; return }

    connectionTask = Task {
      guard ws == nil else {
        return
      }

      if reconnect {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(options.reconnectDelay))

        if Task.isCancelled {
          options.logger?.debug("Reconnect cancelled, returning")
          return
        }
      }

      if status == .connected || status == .connecting {
        options.logger?.debug("WebsSocket already connected or in the process of connecting.")
        return
      }

      status = .connecting

      do {
        self.ws = try await wsFactory(url, options.headers.dictionary)

        status = .connected

        options.logger?.verbose("connected to \(url)")
        listenForMessages()
        startHeartbeating()

        if reconnect {
          await rejoinChannels()
        }

        flushSendBuffer()
      } catch {
        options.logger?.verbose("error \(error.localizedDescription)")
        disconnect()
        await connect(reconnect: true)
      }
    }

    await connectionTask?.value
  }

  private func reconnect() async {
    disconnect()
    await connect(reconnect: true)
  }

  /// Creates a new channel and bind it to this client.
  /// - Parameters:
  ///   - topic: Channel's topic.
  ///   - options: Configuration options for the channel.
  /// - Returns: Channel instance.
  ///
  /// - Note: This method doesn't subscribe to the channel, call ``RealtimeChannelV2/subscribe()`` on the returned channel instance.
  public func channel(
    _ topic: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannelV2 {
    var config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: ""),
      isPrivate: false
    )
    options(&config)

    return RealtimeChannelV2(
      self,
      topic: "realtime:\(topic)",
      config: config,
      logger: self.options.logger
    )
  }

  public func addChannel(_ channel: RealtimeChannelV2) {
    _channels[channel.topic] = channel
  }

  /// Unsubscribe and removes channel.
  ///
  /// If there is no channel left, client is disconnected.
  public func removeChannel(_ channel: RealtimeChannelV2) async {
    if await channel.status == .subscribed {
      await channel.unsubscribe()
    }

    if channels.isEmpty {
      disconnect()
    }
  }

  func _remove(_ channel: RealtimeChannelV2) {
    _channels[channel.topic] = nil
  }

  /// Unsubscribes and removes all channels.
  public func removeAllChannels() async {
    await withTaskGroup(of: Void.self) { group in
      for channel in channels.values {
        group.addTask { await self.removeChannel(channel) }
      }

      await group.waitForAll()
    }

    disconnect()
  }

  private func rejoinChannels() async {
    await withTaskGroup(of: Void.self) { group in
      for channel in channels.values {
        group.addTask {
          await channel.subscribe()
        }
      }

      await group.waitForAll()
    }
  }

  private func listenForMessages() {
    messageTask?.cancel()
    messageTask = Task { [weak self] in
      guard let self, let ws = await self.ws else { return }

      for await event in ws.events {
        if Task.isCancelled {
          return
        }

        switch event {
        case .binary(let data):
          await onMessage(data)
        case .text(let text):
          await onMessage(Data(text.utf8))
        case let .close(code, reason):
          options.logger?.verbose(
            "close \(code.map(String.init) ?? "no code") - \(reason)")
        }
      }
    }
  }

  private func startHeartbeating() {
    heartbeatTask?.cancel()
    heartbeatTask = Task { [weak self, options] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(options.heartbeatInterval))
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
      options.logger?.verbose("heartbeat timeout")
      await reconnect()
    }

    let ref = makeRef()
    pendingHeartbeatRef = ref
    await push(
      RealtimeMessageV2(
        joinRef: nil,
        ref: pendingHeartbeatRef!,
        topic: "phoenix",
        event: "heartbeat",
        payload: [:]
      )
    )
  }

  /// Disconnects client.
  /// - Parameters:
  ///   - code: A numeric status code to send on disconnect.
  ///   - reason: A custom reason for the disconnect.
  public func disconnect(code: Int? = nil, reason: String? = nil) {
    options.logger?.debug("Closing WebSocket connection")
    messageTask?.cancel()
    heartbeatTask?.cancel()
    connectionTask?.cancel()
    ws?.close(code: code, reason: reason)
    ws = nil
    status = .disconnected
  }

  /// Sets the JWT access token used for channel subscription authorization and Realtime RLS.
  /// - Parameter token: A JWT string.
  public func setAuth(_ token: String?) async {
    accessToken = token

    for channel in channels.values {
      if await channel.status == .subscribed {
        options.logger?.debug("Updating auth token for channel \(channel.topic)")
        await channel.push(
          ChannelEvent.accessToken,
          payload: ["access_token": token.map { .string($0) } ?? .null]
        )
      }
    }
  }

  private func onMessage(_ data: Data) async {
    guard let message = try? JSONDecoder().decode(RealtimeMessageV2.self, from: data) else {
      options.logger?.error("Failed to decode message")
      return
    }

    options.logger?.verbose(
      "receive \(message.status?.rawValue ?? "<no status>") \(message.topic) \(message.event) \(message.ref ?? "<no ref>") \(message.payload)"
    )

    let channel = channels[message.topic]

    if let ref = message.ref, ref == pendingHeartbeatRef {
      pendingHeartbeatRef = nil
      options.logger?.debug("heartbeat received")
    } else {
      options.logger?
        .debug("Received event \(message.event) for channel \(channel?.topic ?? "null")")
    }

    if let channel {
      await channel.onMessage(message)
    } else {
      options.logger?.warning("No channel subscribed to \(message.topic). Ignoring message.")
    }
  }

  /// Push out a message if the socket is connected.
  ///
  /// If the socket is not connected, the message gets enqueued within a local buffer, and sent out when a connection is next established.
  public func push(_ message: RealtimeMessageV2) async {
    let callback = { @Sendable [options, ws] in
      do {
        // Check cancellation before sending, because this push may have been cancelled before a connection was established.
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(message)
        ws?.send(binary: data)
      } catch {
        options.logger?.error(
          """
          Failed to send message:
          \(message)

          Error:
          \(error)
          """)
      }
    }

    options.logger?.verbose(
      "push \(message.topic) \(message.event) \(message.ref ?? "<no ref>") \(message.payload)")

    if status == .connected {
      callback()
    } else {
      sendBuffer.append(callback)
    }
  }

  private func flushSendBuffer() {
    sendBuffer.forEach { $0() }
    sendBuffer = []
  }

  func makeRef() -> String {
    ref += 1
    return ref.description
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

  var broadcastURL: URL {
    url.appendingPathComponent("api/broadcast")
  }
}
