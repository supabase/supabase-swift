//
//  RealtimeClient.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import Alamofire
import ConcurrencyExtras
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Factory function for returning a new WebSocket connection.
typealias WebSocketTransport = @Sendable (_ url: URL, _ headers: [String: String]) async throws ->
  any WebSocket

protocol RealtimeClientProtocol: AnyObject, Sendable {
  var status: RealtimeClientStatus { get }
  var options: RealtimeClientOptions { get }
  var session: Alamofire.Session { get }
  var broadcastURL: URL { get }

  func connect() async
  func push(_ message: RealtimeMessage)
  func _getAccessToken() async -> String?
  func makeRef() -> String
  func _remove(_ channel: any RealtimeChannelProtocol)
}

public final class RealtimeClient: Sendable, RealtimeClientProtocol {
  struct MutableState {
    var accessToken: String?
    var ref = 0
    var pendingHeartbeatRef: String?

    /// Long-running task that keeps sending heartbeat messages.
    var heartbeatTask: Task<Void, Never>?

    /// Long-running task for listening for incoming messages from WebSocket.
    var messageTask: Task<Void, Never>?

    var connectionTask: Task<Void, Never>?
    var channels: [String: RealtimeChannel] = [:]
    var sendBuffer: [@Sendable () -> Void] = []

    var conn: (any WebSocket)?
  }

  let url: URL
  let options: RealtimeClientOptions
  let wsTransport: WebSocketTransport
  let mutableState = LockIsolated(MutableState())
  let session: Alamofire.Session
  let apikey: String

  var conn: (any WebSocket)? {
    mutableState.conn
  }

  /// All managed channels indexed by their topics.
  public var channels: [String: RealtimeChannel] {
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
    AsyncStream(
      heartbeatSubject.values.compactMap { $0 }
        as AsyncCompactMapSequence<AsyncStream<HeartbeatStatus?>, HeartbeatStatus>
    )
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
      session: options.session ?? .default
    )
  }

  init(
    url: URL,
    options: RealtimeClientOptions,
    wsTransport: @escaping WebSocketTransport,
    session: Alamofire.Session
  ) {
    var options = options
    if options.headers["X-Client-Info"] == nil {
      options.headers["X-Client-Info"] = "realtime-swift/\(version)"
    }

    self.url = url
    self.options = options
    self.wsTransport = wsTransport
    self.session = session.newSession(adapters: [DefaultHeadersRequestAdapter(headers: options.headers)])

    precondition(options.apikey != nil, "API key is required to connect to Realtime")
    apikey = options.apikey!

    mutableState.withValue { [options] in
      if let accessToken = options.headers["Authorization"]?.split(separator: " ").last {
        $0.accessToken = String(accessToken)
      }
    }
  }

  deinit {
    mutableState.withValue {
      $0.heartbeatTask?.cancel()
      $0.messageTask?.cancel()
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
          let conn = try await wsTransport(
            Self.realtimeWebSocketURL(
              baseURL: Self.realtimeBaseURL(url: url),
              apikey: options.apikey,
              logLevel: options.logLevel
            ),
            options.headers.dictionary
          )
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
      "WebSocket closed. Code: \(code?.description ?? "<none>"), Reason: \(reason ?? "<none>")"
    )

    reconnect()
  }

  private func reconnect(disconnectReason: String? = nil) {
    Task {
      disconnect(reason: disconnectReason)
      await connect(reconnect: true)
    }
  }

  /// Creates a new channel and bind it to this client.
  /// - Parameters:
  ///   - topic: Channel's topic.
  ///   - options: Configuration options for the channel.
  /// - Returns: Channel instance.
  ///
  /// - Note: This method doesn't subscribe to the channel, call ``RealtimeChannel/subscribe()`` on the returned channel instance.
  public func channel(
    _ topic: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannel {
    mutableState.withValue {
      let realtimeTopic = "realtime:\(topic)"

      if let channel = $0.channels[realtimeTopic] {
        return channel
      }

      var config = RealtimeChannelConfig(
        broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
        presence: PresenceJoinConfig(key: ""),
        isPrivate: false
      )
      options(&config)

      let channel = RealtimeChannel(
        topic: realtimeTopic,
        config: config,
        socket: self,
        logger: self.options.logger
      )

      $0.channels[realtimeTopic] = channel

      return channel
    }
  }

  @available(
    *,
    deprecated,
    message:
      "Client handles channels automatically, this method will be removed on the next major release."
  )
  public func addChannel(_ channel: RealtimeChannel) {
    mutableState.withValue {
      $0.channels[channel.topic] = channel
    }
  }

  /// Unsubscribe and removes channel.
  ///
  /// If there is no channel left, client is disconnected.
  public func removeChannel(_ channel: RealtimeChannel) async {
    if channel.status == .subscribed {
      await channel.unsubscribe()
    }

    if channels.isEmpty {
      options.logger?.debug("No more subscribed channel in socket")
      disconnect()
    }
  }

  func _remove(_ channel: any RealtimeChannelProtocol) {
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
    if let accessToken = try? await options.accessToken?() {
      return accessToken
    }
    return mutableState.accessToken
  }

  private func rejoinChannels() {
    Task {
      for channel in channels.values {
        try? await channel.subscribeWithError()
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
            let message = try JSONDecoder().decode(RealtimeMessage.self, from: data)
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
        await self?.sendHeartbeat()
      }
    }
    mutableState.withValue {
      $0.heartbeatTask = heartbeatTask
    }
  }

  private func sendHeartbeat() async {
    if status != .connected {
      heartbeatSubject.yield(.disconnected)
      return
    }

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
        RealtimeMessage(
          joinRef: nil,
          ref: pendingHeartbeatRef,
          topic: "phoenix",
          event: "heartbeat",
          payload: [:]
        )
      )
      heartbeatSubject.yield(.sent)
      await setAuth()
    } else {
      options.logger?.debug("Heartbeat timeout")
      heartbeatSubject.yield(.timeout)
      reconnect(disconnectReason: "heartbeat timeout")
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
    var tokenToSend = token

    if tokenToSend == nil {
      tokenToSend = try? await options.accessToken?()
    }

    guard tokenToSend != mutableState.accessToken else {
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

  private func onMessage(_ message: RealtimeMessage) async {
    if message.topic == "phoenix", message.event == "phx_reply" {
      heartbeatSubject.yield(message.status == .ok ? .ok : .error)
    }

    let channel = mutableState.withValue {
      if let ref = message.ref, ref == $0.pendingHeartbeatRef {
        $0.pendingHeartbeatRef = nil
        options.logger?.debug("heartbeat received")
      } else {
        options.logger?
          .debug("Received event \(message.event) for channel \(message.topic)")
      }

      return $0.channels[message.topic]
    }

    if let channel {
      await channel.onMessage(message)
    }
  }

  /// Push out a message if the socket is connected.
  ///
  /// If the socket is not connected, the message gets enqueued within a local buffer, and sent out when a connection is next established.
  public func push(_ message: RealtimeMessage) {
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
          """
        )
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
