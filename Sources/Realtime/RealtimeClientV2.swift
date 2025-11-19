//
//  RealtimeClientV2.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Factory function for returning a new WebSocket connection.
typealias WebSocketTransport =
  @Sendable (_ url: URL, _ headers: [String: String]) async throws ->
  any WebSocket

protocol RealtimeClientProtocol: AnyObject, Sendable {
  var status: RealtimeClientStatus { get }
  var options: RealtimeClientOptions { get }
  var http: any HTTPClientType { get }
  var broadcastURL: URL { get }

  func connect() async
  func push(_ message: RealtimeMessageV2)
  func _getAccessToken() async -> String?
  func makeRef() -> String
  func _remove(_ channel: any RealtimeChannelProtocol)
}

public final class RealtimeClientV2: Sendable, RealtimeClientProtocol {
  struct MutableState {
    var ref = 0
    var channels: [String: RealtimeChannelV2] = [:]
    var sendBuffer: [@Sendable (_ client: RealtimeClientV2) async -> Void] = []
    var messageTask: Task<Void, Never>?
    var heartbeatMonitor: HeartbeatMonitor?
  }

  let url: URL
  let options: RealtimeClientOptions
  let http: any HTTPClientType
  let apikey: String

  // MARK: - New Actor-Based Components

  private let connectionMgr: ConnectionStateMachine
  private let authMgr: AuthTokenManager
  private let messageRouter: MessageRouter

  private var heartbeatMonitor: HeartbeatMonitor {
    mutableState.withValue {
      if $0.heartbeatMonitor == nil {
        $0.heartbeatMonitor = HeartbeatMonitor(
          interval: options.heartbeatInterval,
          refGenerator: { [weak self] in
            self?.makeRef() ?? UUID().uuidString
          },
          sendHeartbeat: { [weak self] ref in
            await self?.sendHeartbeatMessage(ref: ref)
          },
          onTimeout: { [weak self] in
            await self?.handleHeartbeatTimeout()
          },
          logger: options.logger
        )
      }
      return $0.heartbeatMonitor!
    }
  }

  let mutableState = LockIsolated(MutableState())

  var conn: (any WebSocket)? {
    get async {
      await connectionMgr.connection
    }
  }

  /// All managed channels indexed by their topics.
  public var channels: [String: RealtimeChannelV2] {
    mutableState.channels
  }

  private let statusSubject = AsyncValueSubject<RealtimeClientStatus>(.disconnected)
  private let heartbeatSubject = AsyncValueSubject<HeartbeatStatus?>(nil)

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

  /// Listen for heartbeat status.
  ///
  /// You can also use ``onHeartbeat(_:)`` for a closure based method.
  public var heartbeat: AsyncStream<HeartbeatStatus> {
    AsyncStream(heartbeatSubject.values.compactMap { $0 })
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

  /// Listen for heatbeat checks.
  /// - Parameter listener: Closure that will be called when heartbeat status changes.
  /// - Returns: An observation handle that can be used to stop listening.
  ///
  /// - Note: Use ``heartbeat`` if you prefer to use Async/Await.
  public func onHeartbeat(
    _ listener: @escaping @Sendable (HeartbeatStatus) -> Void
  ) -> RealtimeSubscription {
    let task = heartbeatSubject.onChange { message in
      guard let message else { return }
      listener(message)
    }
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
      wsTransport: { url, headers in
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = headers
        return try await URLSessionWebSocket.connect(
          to: url,
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
    var options = options
    if options.headers[.xClientInfo] == nil {
      options.headers[.xClientInfo] = "realtime-swift/\(version)"
    }

    self.url = url
    self.options = options
    self.http = http

    precondition(options.apikey != nil, "API key is required to connect to Realtime")
    apikey = options.apikey!

    // Extract initial access token from headers
    let initialToken = options.headers[.authorization]?.split(separator: " ").last.map(String.init)

    // Initialize new actor-based components
    self.connectionMgr = ConnectionStateMachine(
      transport: wsTransport,
      url: Self.realtimeWebSocketURL(
        baseURL: Self.realtimeBaseURL(url: url),
        apikey: options.apikey,
        logLevel: options.logLevel
      ),
      headers: options.headers.dictionary,
      reconnectDelay: options.reconnectDelay,
      logger: options.logger
    )

    self.authMgr = AuthTokenManager(
      initialToken: initialToken,
      tokenProvider: options.accessToken
    )

    // Initialize MessageRouter and HeartbeatMonitor with non-capturing closures
    self.messageRouter = MessageRouter(logger: options.logger)
  }

  deinit {
    // Clean up local state
    mutableState.withValue {
      $0.messageTask?.cancel()
      $0.channels = [:]
    }
  }

  // MARK: - Heartbeat Helper Methods

  /// Sends a heartbeat message with the given ref.
  private func sendHeartbeatMessage(ref: String) async {
    let message = RealtimeMessageV2(
      joinRef: nil,
      ref: ref,
      topic: "phoenix",
      event: "heartbeat",
      payload: [:]
    )

    push(message)
    options.logger?.debug("Heartbeat sent with ref: \(ref)")
  }

  /// Called when a heartbeat times out (no response received).
  private func handleHeartbeatTimeout() async {
    options.logger?.warning("Heartbeat timeout - triggering reconnection")
    await connectionMgr.handleError(
      NSError(
        domain: "RealtimeClient",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Heartbeat timeout"]
      )
    )
  }

  // MARK: - Connection Management

  /// Connects the socket.
  ///
  /// Suspends until connected.
  public func connect() async {
    await connect(reconnect: false)
  }

  func connect(reconnect: Bool) async {
    options.logger?.debug(reconnect ? "Reconnecting..." : "Connecting...")

    do {
      // Delegate to ConnectionStateMachine
      _ = try await connectionMgr.connect()

      // Connection successful - start services
      options.logger?.debug("Connected to realtime WebSocket")

      // Start message listener and heartbeat
      listenForMessages()
      await heartbeatMonitor.start()

      // Update status
      status = .connected

      // Rejoin channels if reconnecting
      if reconnect {
        rejoinChannels()
      }

      // Flush any pending messages
      await flushSendBuffer()
    } catch {
      options.logger?.error("Connection failed: \(error)")
      status = .disconnected
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
    mutableState.withValue {
      let realtimeTopic = "realtime:\(topic)"

      if let channel = $0.channels[realtimeTopic] {
        self.options.logger?.debug("Reusing existing channel for topic: \(realtimeTopic)")
        return channel
      }

      var config = RealtimeChannelConfig(
        broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
        presence: PresenceJoinConfig(key: ""),
        isPrivate: false
      )
      options(&config)

      let channel = RealtimeChannelV2(
        topic: realtimeTopic,
        config: config,
        socket: self,
        logger: self.options.logger
      )

      $0.channels[realtimeTopic] = channel

      // Register channel with message router
      Task {
        await messageRouter.registerChannel(topic: channel.topic) { [weak channel] message in
          await channel?.onMessage(message)
        }
      }

      return channel
    }
  }

  @available(
    *,
    deprecated,
    message:
      "Client handles channels automatically, this method will be removed on the next major release."
  )
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

    // Unregister from message router
    await messageRouter.unregisterChannel(topic: channel.topic)

    // Atomically remove channel and check if we should disconnect
    let shouldDisconnect = mutableState.withValue { state -> Bool in
      state.channels[channel.topic] = nil
      return state.channels.isEmpty
    }

    if shouldDisconnect {
      options.logger?.debug("No more subscribed channel in socket")
      disconnect()
    }
  }

  func _remove(_ channel: any RealtimeChannelProtocol) {
    // Unregister from message router
    Task {
      await messageRouter.unregisterChannel(topic: channel.topic)
    }

    mutableState.withValue {
      $0.channels[channel.topic] = nil
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
    return await authMgr.getCurrentToken()
  }

  private func rejoinChannels() {
    Task {
      for channel in channels.values {
        try? await channel.subscribeWithError()
      }
    }
  }

  private func listenForMessages() {
    // Cancel existing message task
    mutableState.withValue { state in
      state.messageTask?.cancel()
    }

    let messageTask = Task {
      // Get connection from ConnectionStateMachine
      guard let conn = await connectionMgr.connection else {
        options.logger?.warning("No connection available for message listening")
        return
      }

      do {
        for await event in conn.events {
          if Task.isCancelled { return }

          switch event {
          case .binary:
            options.logger?.error("Unsupported binary event received.")

          case .text(let text):
            let data = Data(text.utf8)
            let message = try JSONDecoder().decode(RealtimeMessageV2.self, from: data)
            await onMessage(message)

            if Task.isCancelled {
              return
            }

          case .close(let code, let reason):
            options.logger?.debug(
              "WebSocket closed. Code: \(code?.description ?? "<none>"), Reason: \(reason)"
            )
            await connectionMgr.handleClose(code: code, reason: reason)
          }
        }
      } catch {
        options.logger?.debug("WebSocket error: \(error.localizedDescription)")
        await connectionMgr.handleError(error)
      }
    }

    mutableState.withValue {
      $0.messageTask = messageTask
    }
  }

  /// Disconnects client.
  /// - Parameters:
  ///   - code: A numeric status code to send on disconnect.
  ///   - reason: A custom reason for the disconnect.
  public func disconnect(code: Int? = nil, reason: String? = nil) {
    options.logger?.debug("Closing WebSocket connection")

    // Stop heartbeat monitor
    Task {
      await heartbeatMonitor.stop()

      // Disconnect via ConnectionStateMachine
      let reasonStr = reason ?? "Client disconnect"

      await connectionMgr.disconnect(reason: reasonStr)
    }

    // Clean up local state
    mutableState.withValue {
      $0.ref = 0
      $0.messageTask?.cancel()
      $0.messageTask = nil
      $0.sendBuffer = []
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
    // Get the token to use (either provided or from provider)
    let tokenToSend: String?
    if let token = token {
      tokenToSend = token
    } else {
      tokenToSend = await authMgr.refreshToken()
    }

    // Update token in AuthTokenManager and check if it changed
    let changed = await authMgr.updateToken(tokenToSend)

    guard changed else {
      return
    }

    // Push updated token to all subscribed channels
    for channel in channels.values {
      if channel.status == .subscribed {
        options.logger?.debug("Updating auth token for channel \(channel.topic)")
        await channel.push(
          ChannelEvent.accessToken,
          payload: ["access_token": tokenToSend.map { .string($0) } ?? .null]
        )
      }
    }
  }

  private func onMessage(_ message: RealtimeMessageV2) async {
    // Handle heartbeat responses
    if message.topic == "phoenix", message.event == "phx_reply" {
      heartbeatSubject.yield(message.status == .ok ? .ok : .error)

      // Acknowledge heartbeat if this is a response to one
      if let ref = message.ref {
        await heartbeatMonitor.onHeartbeatResponse(ref: ref)
        options.logger?.debug("Heartbeat acknowledged: \(ref)")
      }
      return
    }

    // Log received message
    options.logger?.debug("Received event \(message.event) for channel \(message.topic)")

    // Route message via MessageRouter
    await messageRouter.route(message)
  }

  /// Push out a message if the socket is connected.
  ///
  /// If the socket is not connected, the message gets enqueued within a local buffer, and sent out when a connection is next established.
  public func push(_ message: RealtimeMessageV2) {
    let callback = { @Sendable (_ client: RealtimeClientV2) in
      do {
        // Check cancellation before sending
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(message)

        // Get connection and send
        if let conn = await client.conn {
          conn.send(String(decoding: data, as: UTF8.self))
        }
      } catch {
        client.options.logger?.error(
          """
          Failed to send message:
          \(message)

          Error:
          \(error)
          """
        )
      }
    }

    if status == .connected {
      Task {
        await callback(self)
      }
    } else {
      mutableState.withValue {
        $0.sendBuffer.append(callback)
      }
    }
  }

  private func flushSendBuffer() async {
    let tasks = mutableState.withValue {
      let tasks = $0.sendBuffer
      $0.sendBuffer = []
      return tasks
    }

    for task in tasks {
      await task(self)
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

  static func realtimeWebSocketURL(baseURL: URL, apikey: String?, logLevel: LogLevel?) -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    else {
      return baseURL
    }

    components.queryItems = components.queryItems ?? []
    if let apikey {
      components.queryItems!.append(URLQueryItem(name: "apikey", value: apikey))
    }
    components.queryItems!.append(URLQueryItem(name: "vsn", value: "1.0.0"))

    if let logLevel {
      components.queryItems!.append(URLQueryItem(name: "log_level", value: logLevel.rawValue))
    }

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
