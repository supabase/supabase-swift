//
//  RealtimeClientV2.swift
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

/// Factory function for returning a new WebSocket connection.
typealias WebSocketTransport = @Sendable () async throws -> any WebSocket

public final class RealtimeClientV2: Sendable {
  struct MutableState {
    var accessToken: String?
    var ref = 0
    var pendingHeartbeatRef: String?

    /// Long-running task that keeps sending heartbeat messages.
    var heartbeatTask: Task<Void, Never>?

    /// Long-running task for listening for incoming messages from WebSocket.
    var messageTask: Task<Void, Never>?

    var connectionTask: Task<Void, Never>?
    var channels: [RealtimeChannelV2] = []
    var sendBuffer: [@Sendable () -> Void] = []

    var conn: (any WebSocket)?
  }

  let url: URL
  let options: RealtimeClientOptions
  let wsTransport: WebSocketTransport
  let mutableState = LockIsolated(MutableState())
  let http: any HTTPClientType
  let apikey: String?

  var conn: (any WebSocket)? {
    mutableState.conn
  }

  /// All managed channels indexed by their topics.
  public var channels: [String: RealtimeChannelV2] {
    mutableState.channels.reduce(
      into: [:],
      { $0[$1.topic] = $1 }
    )
  }

  private let statusSubject = AsyncValueSubject<RealtimeClientStatus>(.disconnected)

  /// Listen for connection status changes.
  ///
  /// You can also use ``onStatusChange(_:)`` for a closure based method.
  public var statusChange: AsyncStream<RealtimeClientStatus> {
    statusSubject.values
  }

  /// The current connection status.
  public private(set) var status: RealtimeClientStatus {
    get { statusSubject.value }
    set { statusSubject.yield(newValue) }
  }

  /// Listen for connection status changes.
  /// - Parameter listener: Closure that will be called when connection status changes.
  /// - Returns: An observation handle that can be used to stop listening.
  ///
  /// - Note: Use ``statusChange`` if you prefer to use Async/Await.
  public func onStatusChange(
    _ listener: @escaping @Sendable (RealtimeClientStatus) -> Void
  ) -> RealtimeSubscription {
    let task = statusSubject.onChange { listener($0) }
    return RealtimeSubscription { task.cancel() }
  }

  public convenience init(url: URL, options: RealtimeClientOptions) {
    var interceptors: [any HTTPClientInterceptor] = []

    if let logger = options.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    self.init(
      url: url,
      options: options,
      wsTransport: {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = options.headers.dictionary
        return try await URLSessionWebSocket.connect(
          to: Self.realtimeWebSocketURL(
            baseURL: Self.realtimeBaseURL(url: url),
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
    wsTransport: @escaping WebSocketTransport,
    http: any HTTPClientType
  ) {
    self.url = url
    self.options = options
    self.wsTransport = wsTransport
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
      $0.messageTask?.cancel()
      $0.channels = []
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
          try? await _clock.sleep(for: options.reconnectDelay)

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

        do {
          let conn = try await wsTransport()
          mutableState.withValue { $0.conn = conn }
          onConnected(reconnect: reconnect)
        } catch {
          onError(error)
        }
      }

      mutableState.withValue {
        $0.connectionTask = connectionTask
      }
    }

    _ = await statusChange.first { @Sendable in $0 == .connected }
  }

  private func onConnected(reconnect: Bool) {
    status = .connected
    options.logger?.debug("Connected to realtime WebSocket")
    listenForMessages()
    startHeartbeating()
    if reconnect {
      rejoinChannels()
    }

    flushSendBuffer()
  }

  private func onDisconnected() {
    options.logger?
      .debug(
        "WebSocket disconnected. Trying again in \(options.reconnectDelay)"
      )
    reconnect()
  }

  private func onError(_ error: (any Error)?) {
    options.logger?
      .debug(
        "WebSocket error \(error?.localizedDescription ?? "<none>"). Trying again in \(options.reconnectDelay)"
      )
    reconnect()
  }

  private func onClose(code: Int?, reason: String?) {
    options.logger?.debug(
      "WebSocket closed. Code: \(code?.description ?? "<none>"), Reason: \(reason ?? "<none>")")

    reconnect()
  }

  private func reconnect() {
    Task {
      disconnect()
      await connect(reconnect: true)
    }
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

    let channel = RealtimeChannelV2(
      topic: "realtime:\(topic)",
      config: config,
      socket: self,
      logger: self.options.logger
    )

    mutableState.withValue {
      $0.channels.append(channel)
    }

    return channel
  }

  @available(
    *, deprecated,
    message:
      "Client handles channels automatically, this method will be removed on the next major release."
  )
  public func addChannel(_ channel: RealtimeChannelV2) {
    mutableState.withValue {
      $0.channels.append(channel)
    }
  }

  /// Unsubscribe and removes channel.
  ///
  /// If there is no channel left, client is disconnected.
  public func removeChannel(_ channel: RealtimeChannelV2) async {
    if channel.status == .subscribed {
      await channel.unsubscribe()
    }

    if channels.isEmpty {
      options.logger?.debug("No more subscribed channel in socket")
      disconnect()
    }
  }

  func _remove(_ channel: RealtimeChannelV2) {
    mutableState.withValue {
      $0.channels.removeAll {
        $0.joinRef == channel.joinRef
      }
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

  func _getAccessToken() async -> String? {
    if let accessToken = try? await options.accessToken?() {
      return accessToken
    }
    return mutableState.accessToken
  }

  private func rejoinChannels() {
    Task {
      for channel in channels.values {
        await channel.subscribe()
      }
    }
  }

  private func listenForMessages() {
    let messageTask = Task { [weak self] in
      guard let self, let conn = self.conn else { return }

      do {
        for await event in conn.events {
          if Task.isCancelled { return }

          switch event {
          case .binary:
            self.options.logger?.error("Unsupported binary event received.")
            break
          case .text(let text):
            let data = Data(text.utf8)
            let message = try JSONDecoder().decode(RealtimeMessageV2.self, from: data)
            await onMessage(message)

          case let .close(code, reason):
            onClose(code: code, reason: reason)
          }
        }
      } catch {
        onError(error)
      }
    }
    mutableState.withValue {
      $0.messageTask = messageTask
    }
  }

  private func startHeartbeating() {
    let heartbeatTask = Task { [weak self, options] in
      while !Task.isCancelled {
        try? await _clock.sleep(for: options.heartbeatInterval)
        if Task.isCancelled {
          break
        }
        self?.sendHeartbeat()
      }
    }
    mutableState.withValue {
      $0.heartbeatTask = heartbeatTask
    }
  }

  private func sendHeartbeat() {
    let pendingHeartbeatRef: String? = mutableState.withValue {
      if $0.pendingHeartbeatRef != nil {
        $0.pendingHeartbeatRef = nil
        return nil
      }

      let ref = makeRef()
      $0.pendingHeartbeatRef = ref
      return ref
    }

    if let pendingHeartbeatRef {
      push(
        RealtimeMessageV2(
          joinRef: nil,
          ref: pendingHeartbeatRef,
          topic: "phoenix",
          event: "heartbeat",
          payload: [:]
        )
      )
    } else {
      options.logger?.debug("Heartbeat timeout")
      reconnect()
    }
  }

  /// Disconnects client.
  /// - Parameters:
  ///   - code: A numeric status code to send on disconnect.
  ///   - reason: A custom reason for the disconnect.
  public func disconnect(code: Int? = nil, reason: String? = nil) {
    options.logger?.debug("Closing WebSocket connection")

    conn?.close(code: code, reason: reason)

    mutableState.withValue {
      $0.ref = 0
      $0.messageTask?.cancel()
      $0.heartbeatTask?.cancel()
      $0.connectionTask?.cancel()
      $0.conn = nil
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

  private func onMessage(_ message: RealtimeMessageV2) async {
    let channels = mutableState.withValue {
      if let ref = message.ref, ref == $0.pendingHeartbeatRef {
        $0.pendingHeartbeatRef = nil
        options.logger?.debug("heartbeat received")
      } else {
        options.logger?
          .debug("Received event \(message.event) for channel \(message.topic)")
      }

      return $0.channels.filter { $0.topic == message.topic }
    }

    for channel in channels {
      await channel.onMessage(message)
    }
  }

  /// Push out a message if the socket is connected.
  ///
  /// If the socket is not connected, the message gets enqueued within a local buffer, and sent out when a connection is next established.
  public func push(_ message: RealtimeMessageV2) {
    let callback = { @Sendable [weak self] in
      do {
        // Check cancellation before sending, because this push may have been cancelled before a connection was established.
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(message)
        self?.conn?.send(String(decoding: data, as: UTF8.self))
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

  func makeRef() -> String {
    mutableState.withValue {
      $0.ref += 1
      return $0.ref.description
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
