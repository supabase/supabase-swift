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

typealias WebSocketFactory = @Sendable (
  _ url: URL,
  _ headers: [String: String]
) async throws -> any WebSocket

public typealias JSONObject = Helpers.JSONObject

public final class RealtimeClientV2: Sendable {
  struct MutableState {
    var accessToken: String?
    var ref = 0
    var pendingHeartbeatRef: Int?

    /// Long-running task that keeps sending heartbeat messages.
    var heartbeatTask: Task<Void, Never>?

    var connectionTask: Task<Void, Never>?
    var channels: [String: RealtimeChannelV2] = [:]
    var sendBuffer: [@Sendable () -> Void] = []

    var ws: (any WebSocket)?
  }

  let url: URL
  let options: RealtimeClientOptions
  let wsFactory: WebSocketFactory
  let mutableState = LockIsolated(MutableState())
  let http: any HTTPClientType
  let apikey: String?

  /// All managed channels indexed by their topics.
  public var channels: [String: RealtimeChannelV2] {
    mutableState.channels
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

  public convenience init(url: URL, options: RealtimeClientOptions) {
    var interceptors: [any HTTPClientInterceptor] = []

    if let logger = options.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    self.init(
      url: url,
      options: options,
      wsFactory: { url, headers in
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = headers
        return try await URLSessionWebSocket.connect(to: url, configuration: configuration)
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

    mutableState.withValue {
      if let accessToken = options.headers[.authorization]?.split(separator: " ").last {
        $0.accessToken = String(accessToken)
      } else {
        $0.accessToken = options.apikey
      }
    }
  }

  deinit {
    mutableState.withValue {
      $0.heartbeatTask?.cancel()
      $0.channels = [:]
    }
  }

  /// Connects the socket.
  ///
  /// Suspends until connected.
  public func connect() async {
    await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async {
    let connectionTask = Task {
      if reconnect {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(options.reconnectDelay))

        if Task.isCancelled {
          options.logger?.debug("Reconnect cancelled, returning")
          return
        }
      }

      if status == .connected {
        // websocket connected while it was waiting for a reconnection.
        options.logger?.debug("WebsSocket already connected")
        return
      }

      status = .connecting

      do {
        let ws = try await wsFactory(
          Self.realtimeWebSocketURL(
            baseURL: Self.realtimeBaseURL(url: url),
            apikey: options.apikey
          ),
          options.headers.dictionary
        )
        mutableState.withValue { $0.ws = ws }
        status = .connected
        startHeartbeating()
        if reconnect {
          rejoinChannels()
        }
        flushSendBuffer()

        for await event in ws.events {
          if Task.isCancelled { break }

          switch event {
          case let .text(text):
            await onMessage(Data(text.utf8))
          case let .binary(data):
            await onMessage(data)
          case let .close(code, reason):
            options.logger?.verbose("connection closed code \(code ?? 0), reason \(reason)")
          }
        }
      } catch {
        options.logger?
          .debug(
            "WebSocket error \(error.localizedDescription). Trying again in \(options.reconnectDelay)"
          )
        Task {
          self.disconnect()
          await self.connect(reconnect: true)
        }
      }
    }

    mutableState.withValue {
      $0.connectionTask = connectionTask
    }

    _ = await statusChange.first { @Sendable in $0 == .connected }
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
      topic: "realtime:\(topic)",
      config: config,
      socket: Socket(client: self),
      logger: self.options.logger
    )
  }

  public func addChannel(_ channel: RealtimeChannelV2) {
    mutableState.withValue {
      $0.channels[channel.topic] = channel
    }
  }

  /// Unsubscribe and removes channel.
  ///
  /// If there is no channel left, client is disconnected.
  public func removeChannel(_ channel: RealtimeChannelV2) async {
    if channel.status == .subscribed {
      await channel.unsubscribe()
    }

    mutableState.withValue {
      $0.channels[channel.topic] = nil
    }

    if channels.isEmpty {
      options.logger?.debug("No more subscribed channel in socket")
      disconnect()
    }
  }

  /// Unsubscribes and removes all channels.
  public func removeAllChannels() async {
    await withTaskGroup(of: Void.self) { group in
      for channel in channels.values {
        group.addTask { await self.removeChannel(channel) }
      }

      await group.waitForAll()
    }
  }

  private func rejoinChannels() {
    for channel in channels.values {
      Task {
        await channel.subscribe()
      }
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
        RealtimeMessageV2(
          joinRef: nil,
          ref: pendingHeartbeatRef.description,
          topic: "phoenix",
          event: "heartbeat",
          payload: [:]
        )
      )
    } else {
      options.logger?.debug("Heartbeat timeout, trying to reconnect in \(options.reconnectDelay)s")
      Task {
        disconnect()
        await connect(reconnect: true)
      }
    }
  }

  /// Disconnects client.
  /// - Parameters:
  ///   - code: A numeric status code to send on disconnect.
  ///   - reason: A custom reason for the disconnect.
  public func disconnect(code: Int? = nil, reason: String? = nil) {
    options.logger?.debug("Closing WebSocket connection")
    mutableState.withValue {
      $0.ref = 0
      $0.heartbeatTask?.cancel()
      $0.connectionTask?.cancel()
      $0.ws?.close(code: code, reason: reason)
    }

    status = .disconnected
  }

  /// Sets the JWT access token used for channel subscription authorization and Realtime RLS.
  ///
  /// If `token` is nil it will use the ``RealtimeClientOptions/accessToken`` callback function or the token set on the client.
  ///
  /// On callback used, it will set the value of the token internal to the client.
  /// - Parameter token: A JWT string to override the token set on the client.
  public func setAuth(_ token: String? = nil) async {
    var token = token

    if token == nil {
      token = try? await options.accessToken?()
    }

    if token == nil {
      token = mutableState.accessToken
    }

    if let token, let payload = JWT.decodePayload(token),
      let exp = payload["exp"] as? TimeInterval, exp < Date().timeIntervalSince1970
    {
      options.logger?.warning(
        "InvalidJWTToken: Invalid value for JWT claim \"exp\" with value \(exp)")
      return
    }

    mutableState.withValue { [token] in
      $0.accessToken = token
    }

    for channel in channels.values {
      if channel.status == .subscribed {
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
      return
    }

    await onMessage(message)
  }

  private func onMessage(_ message: RealtimeMessageV2) async {
    let channel = mutableState.withValue {
      let channel = $0.channels[message.topic]

      if let ref = message.ref, Int(ref) == $0.pendingHeartbeatRef {
        $0.pendingHeartbeatRef = nil
        options.logger?.debug("heartbeat received")
      } else {
        options.logger?
          .debug("Received event \(message.event) for channel \(channel?.topic ?? "null")")
      }
      return channel
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
    let callback = { @Sendable [weak self] in
      do {
        // Check cancellation before sending, because this push may have been cancelled before a connection was established.
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(message)
        self?.mutableState.ws?.send(String(decoding: data, as: UTF8.self))
      } catch {
        self?.options.logger?.error(
          """
          Failed to send message:
          \(message)

          Error:
          \(error)
          """)
      }
    }

    if status == .connected {
      callback()
    } else {
      mutableState.withValue {
        $0.sendBuffer.append(callback)
      }
    }
  }

  private func flushSendBuffer() {
    mutableState.withValue {
      $0.sendBuffer.forEach { $0() }
      $0.sendBuffer = []
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

  var broadcastURL: URL {
    url.appendingPathComponent("api/broadcast")
  }
}
