//
//  RealtimeClientV2.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
public import Foundation
import Helpers
import HTTPTypes

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
  func pushBroadcast(
    joinRef: String?, ref: String?, topic: String, event: String, jsonPayload: JSONObject
  )
  func pushBroadcast(
    joinRef: String?, ref: String?, topic: String, event: String, binaryPayload: Data
  )
  func _getAccessToken() async -> String?
  func makeRef() -> String
  func _remove(_ channel: any RealtimeChannelProtocol)
}

/// The entry point for Supabase Realtime subscriptions.
///
/// `RealtimeClientV2` manages the underlying WebSocket connection and routes
/// incoming events to the appropriate ``RealtimeChannelV2`` instances. Create
/// one client per Supabase project and reuse it across your app.
///
/// ```swift
/// let client = RealtimeClientV2(
///   url: URL(string: "https://<project>.supabase.co/realtime/v1")!,
///   options: RealtimeClientOptions(accessToken: { session.accessToken })
/// )
///
/// await client.connect()
///
/// let channel = client.channel("room:lobby")
/// try await channel.subscribe()
/// ```
///
/// ## Topics
/// ### Channels
/// - ``channels``
/// - ``channel(_:options:)``
/// - ``addChannel(_:)``
/// - ``removeChannel(_:)``
/// - ``removeAllChannels()``
/// ### Connection Status
/// - ``status``
/// - ``statusChange``
/// - ``onStatusChange(_:)``
/// - ``connect()``
/// - ``disconnect(code:reason:)``
/// ### Heartbeat
/// - ``heartbeat``
/// - ``onHeartbeat(_:)``
/// ### Authentication
/// - ``setAuth(_:)``
/// ### Sending Messages
/// - ``push(_:)``
public final class RealtimeClientV2: Sendable, RealtimeClientProtocol {
  struct MutableState {
    var accessToken: String?
    var ref = 0
    var pendingHeartbeatRef: String?

    /// Long-running task that keeps sending heartbeat messages.
    var heartbeatTask: Task<Void, Never>?

    /// Long-running task for listening for incoming messages from WebSocket.
    var messageTask: Task<Void, Never>?

    var stateObserverTask: Task<Void, Never>?

    /// Cached connection to avoid actor hops when sending messages
    var connection: (any WebSocket)?

    var channels: [String: RealtimeChannelV2] = [:]
    var sendBuffer: [@Sendable (RealtimeClientV2) -> Void] = []

    /// Pending task that will call `disconnect()` after `disconnectOnEmptyChannelsAfter` elapses.
    /// Cancelled when a new channel is created or `disconnect()` is called directly.
    var pendingDisconnectTask: Task<Void, Never>?

    /// Retains the optional app-lifecycle observer for the client's lifetime.
    /// Stored as `AnyObject?` so this type remains available on platforms where
    /// the concrete `RealtimeLifecycleManager` is not compiled.
    var lifecycleManager: (any Sendable & AnyObject)?

    /// Whether the socket was `.connected` the last time the app entered the
    /// background. `handleAppForeground` only attempts recovery when this is
    /// `true` — otherwise foregrounding a client that was intentionally idle
    /// would spuriously open a connection.
    var wasConnectedBeforeBackground: Bool = false
  }

  let url: URL
  let options: RealtimeClientOptions
  let wsTransport: WebSocketTransport
  let mutableState = LockIsolated(MutableState())
  let http: any HTTPClientType
  let apikey: String
  let serializer = RealtimeSerializer()
  // Captured at init time so parallel test classes that swap _clock cannot
  // change the timing of an already-running client.
  let clock: any Clock<Duration>

  let connectionManager: ConnectionManager

  /// All managed channels indexed by their topics.
  ///
  /// The dictionary key is the fully-qualified topic string (e.g. `"realtime:room:lobby"`).
  /// Channels are added by ``channel(_:options:)`` and removed by ``removeChannel(_:)``
  /// or ``removeAllChannels()``.
  public var channels: [String: RealtimeChannelV2] {
    mutableState.channels
  }

  private let statusSubject = AsyncValueSubject<RealtimeClientStatus>(.disconnected)
  private let heartbeatSubject = AsyncValueSubject<HeartbeatStatus?>(nil)

  /// An async stream that emits connection status changes.
  ///
  /// The stream emits the current status immediately upon iteration and then each
  /// subsequent change. Use ``onStatusChange(_:)`` for a closure-based alternative.
  ///
  /// ```swift
  /// for await status in client.statusChange {
  ///   print("Status changed to \(status)")
  /// }
  /// ```
  public var statusChange: AsyncStream<RealtimeClientStatus> {
    statusSubject.values
  }

  /// The current WebSocket connection status.
  ///
  /// Reflects the last value emitted by ``statusChange``.
  public var status: RealtimeClientStatus {
    statusSubject.value
  }

  /// An async stream that emits heartbeat status updates.
  ///
  /// The client sends a heartbeat at each ``RealtimeClientOptions/defaultHeartbeatInterval``
  /// interval to keep the connection alive. Use ``onHeartbeat(_:)`` for a closure-based alternative.
  ///
  /// ```swift
  /// for await beat in client.heartbeat {
  ///   print("Heartbeat: \(beat)")
  /// }
  /// ```
  public var heartbeat: AsyncStream<HeartbeatStatus> {
    AsyncStream(heartbeatSubject.values.compactMap { $0 })
  }

  /// Registers a closure to be called whenever the connection status changes.
  ///
  /// - Parameter listener: A `@Sendable` closure called with the new ``RealtimeClientStatus`` on every change.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  ///
  /// > Note: Use ``statusChange`` if you prefer async iteration over closures.
  public func onStatusChange(
    _ listener: @escaping @Sendable (RealtimeClientStatus) -> Void
  ) -> RealtimeSubscription {
    let task = statusSubject.onChange { listener($0) }
    return RealtimeSubscription { task.cancel() }
  }

  /// Registers a closure to be called on every heartbeat cycle.
  ///
  /// - Parameter listener: A `@Sendable` closure called with the latest ``HeartbeatStatus``.
  /// - Returns: A ``RealtimeSubscription`` token. Retain it — the subscription is cancelled when the token is deallocated.
  ///
  /// > Note: Use ``heartbeat`` if you prefer async iteration over closures.
  public func onHeartbeat(
    _ listener: @escaping @Sendable (HeartbeatStatus) -> Void
  ) -> RealtimeSubscription {
    let task = heartbeatSubject.onChange { message in
      guard let message else { return }
      listener(message)
    }
    return RealtimeSubscription { task.cancel() }
  }

  /// Creates a new ``RealtimeClientV2`` using the default URLSession WebSocket transport.
  ///
  /// - Parameters:
  ///   - url: The Realtime server URL (e.g. `https://<project>.supabase.co/realtime/v1`).
  ///   - options: Configuration options for the client.
  public convenience init(url: URL, options: RealtimeClientOptions) {
    var interceptors: [any HTTPClientInterceptor] = []

    if let logger = options.logger {
      interceptors.append(LoggerInterceptor(logger: logger))
    }

    self.init(
      url: url,
      options: options,
      wsTransport: { url, headers in
        return try await URLSessionWebSocket.connect(
          to: url,
          headers: headers
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
    http: any HTTPClientType,
    clock: any Clock<Duration> = _clock
  ) {
    var options = options
    if options.headers[.xClientInfo] == nil {
      options.headers[.xClientInfo] = "realtime-swift/\(version)"
    }

    self.url = url
    self.options = options
    self.wsTransport = wsTransport
    self.http = http
    self.clock = clock

    precondition(options.apikey != nil, "API key is required to connect to Realtime")
    apikey = options.apikey!

    mutableState.withValue { [options] in
      if let accessToken = options.headers[.authorization]?.split(separator: " ").last {
        $0.accessToken = String(accessToken)
      }
    }

    self.connectionManager = ConnectionManager(
      transport: wsTransport,
      url: Self.realtimeWebSocketURL(
        baseURL: Self.realtimeBaseURL(url: url),
        apikey: options.apikey,
        vsn: options.vsn,
        logLevel: options.logLevel
      ),
      headers: options.headers.dictionary,
      reconnectDelay: options.reconnectDelay,
      logger: options.logger,
      clock: clock
    )

    let stateObserverTask = Task { [weak self, connectionManager, statusSubject] in
      var sawReconnecting = false
      for await state in connectionManager.stateChanges {
        guard let self else { return }
        switch state {
        case .connected(let conn):
          // Only drive the restart from here when this .connected came from
          // an automatic reconnect (.reconnecting → .connected). Connects
          // triggered by `connect()` set things up synchronously there.
          if sawReconnecting {
            self.handleConnected(conn: conn, isReconnect: true)
            sawReconnecting = false
            Self.yieldStatusIfChanged(statusSubject, .connected)
          }
        case .disconnected:
          Self.yieldStatusIfChanged(statusSubject, .disconnected)
        case .connecting:
          // Skip — `connect()` yields .connecting/.connected synchronously
          // before returning, so the observer would otherwise double-emit.
          break
        case .reconnecting:
          sawReconnecting = true
          Self.yieldStatusIfChanged(statusSubject, .connecting)
        }
      }
    }

    mutableState.withValue {
      $0.stateObserverTask = stateObserverTask
    }

    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      if options.handleAppLifecycle {
        let manager = RealtimeLifecycleManager(client: self)
        mutableState.withValue { $0.lifecycleManager = manager }
      }
    #endif
  }

  private static func yieldStatusIfChanged(
    _ subject: AsyncValueSubject<RealtimeClientStatus>,
    _ status: RealtimeClientStatus
  ) {
    if subject.value != status {
      subject.yield(status)
    }
  }

  private func handleConnected(conn: any WebSocket, isReconnect: Bool) {
    // Set up the per-connection machinery exactly once. `handleConnected` can
    // run multiple times for the same physical connection (concurrent subscribes,
    // subscribe retries racing an auto-reconnect). Guarding on connection identity
    // prevents launching duplicate `listenForMessages` / `startHeartbeating` tasks,
    // which would cancel-and-restart the stream consumer (potentially losing
    // in-flight frames) and create a second heartbeat timer.
    let isNewConnection = mutableState.withValue { state -> Bool in
      if state.connection === conn { return false }
      state.connection = conn
      // A heartbeat awaiting an ack on the previous connection can never be
      // acknowledged on this one. Clearing the pending ref prevents the new
      // connection's first heartbeat from misreading it as a timeout and
      // tearing down a healthy socket.
      state.pendingHeartbeatRef = nil
      return true
    }

    if isNewConnection {
      listenForMessages(conn: conn)
      startHeartbeating()
      flushSendBuffer()
    }

    if isReconnect {
      Task { await rejoinChannels() }
    }
  }

  deinit {
    mutableState.withValue {
      $0.heartbeatTask?.cancel()
      $0.messageTask?.cancel()
      $0.stateObserverTask?.cancel()
      $0.pendingDisconnectTask?.cancel()
      $0.channels = [:]
    }
  }

  /// Opens the WebSocket connection and suspends until it is established.
  ///
  /// Calling this method when already connected is a no-op. If ``RealtimeClientOptions/connectOnSubscribe``
  /// is `true` (the default), this is called automatically when a channel is subscribed to.
  ///
  /// ```swift
  /// await client.connect()
  /// ```
  public func connect() async {
    options.logger?.debug("Connecting...")
    Self.yieldStatusIfChanged(statusSubject, .connecting)

    do {
      let conn = try await connectionManager.connect()
      options.logger?.debug("Connected to realtime WebSocket")

      // Set up message listening, heartbeating, and connection caching
      // synchronously so callers can rely on state being ready after connect()
      // returns, even if the state observer task hasn't caught up yet.
      handleConnected(conn: conn, isReconnect: false)
      Self.yieldStatusIfChanged(statusSubject, .connected)
    } catch {
      options.logger?.error("Connection failed: \(error)")
      Self.yieldStatusIfChanged(statusSubject, .disconnected)
    }
  }

  /// Returns an existing channel for the given topic or creates a new one.
  ///
  /// The fully-qualified topic sent to the server is `"realtime:<topic>"`. If a channel
  /// with the same topic already exists, it is returned without modification.
  ///
  /// > Note: This method does not subscribe to the channel. Call ``RealtimeChannelV2/subscribeWithError()``
  /// > on the returned instance to join the topic.
  ///
  /// - Parameters:
  ///   - topic: The channel topic name (without the `realtime:` prefix).
  ///   - options: A builder closure to configure ``RealtimeChannelConfig`` options such as
  ///     broadcast, presence, and privacy settings.
  /// - Returns: A ``RealtimeChannelV2`` bound to this client.
  public func channel(
    _ topic: String,
    options: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannelV2 {
    mutableState.withValue {
      // Cancel any pending deferred disconnect — a new channel is being added.
      $0.pendingDisconnectTask?.cancel()
      $0.pendingDisconnectTask = nil

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

      let channel = RealtimeChannelV2(
        topic: realtimeTopic,
        config: config,
        socket: self,
        logger: self.options.logger
      )

      $0.channels[realtimeTopic] = channel

      return channel
    }
  }

  /// Registers an externally-created channel with this client.
  ///
  /// > Warning: The client now manages channels automatically via ``channel(_:options:)``.
  /// > This method will be removed in the next major release.
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

  /// Unsubscribes from and removes a channel.
  ///
  /// If the channel is currently subscribed, it is unsubscribed first. After removal,
  /// if no channels remain, the client disconnects (or schedules a deferred disconnect
  /// based on ``RealtimeClientOptions/defaultDisconnectOnEmptyChannelsAfter``).
  ///
  /// - Parameter channel: The channel to remove.
  public func removeChannel(_ channel: RealtimeChannelV2) async {
    if channel.status == .subscribed {
      await channel.unsubscribe()
    }

    // Atomically remove channel and check if we should disconnect
    let shouldDisconnect = mutableState.withValue { state -> Bool in
      state.channels[channel.topic] = nil
      return state.channels.isEmpty
    }

    if shouldDisconnect {
      options.logger?.debug("No more subscribed channel in socket")
      let delay = options.disconnectOnEmptyChannelsAfter
      if delay <= 0 {
        disconnect()
      } else {
        schedulePendingDisconnect()
      }
    }
  }

  private func schedulePendingDisconnect() {
    let delay = options.disconnectOnEmptyChannelsAfter
    mutableState.withValue { state in
      state.pendingDisconnectTask?.cancel()
      state.pendingDisconnectTask = Task { [weak self, clock] in
        do {
          try await clock.sleep(for: .seconds(delay))
          self?.disconnect()
        } catch {
          // Cancelled: a new channel was added or disconnect() was called directly.
        }
      }
    }
  }

  func _remove(_ channel: any RealtimeChannelProtocol) {
    mutableState.withValue {
      $0.channels[channel.topic] = nil
    }
  }

  /// Unsubscribes from and removes all channels, then disconnects immediately.
  ///
  /// Unlike ``removeChannel(_:)``, this method ignores
  /// ``RealtimeClientOptions/defaultDisconnectOnEmptyChannelsAfter`` and
  /// disconnects the WebSocket right away.
  public func removeAllChannels() async {
    await withTaskGroup(of: Void.self) { group in
      for channel in channels.values {
        group.addTask { await self.removeChannel(channel) }
      }

      await group.waitForAll()
    }

    // Cancel any pending deferred disconnect and disconnect immediately.
    mutableState.withValue {
      $0.pendingDisconnectTask?.cancel()
      $0.pendingDisconnectTask = nil
    }
    disconnect()
  }

  func _getAccessToken() async -> String? {
    if let accessToken = try? await options.accessToken?() {
      return accessToken
    }
    return mutableState.accessToken
  }

  private func rejoinChannels() async {
    for channel in channels.values {
      await channel.resetForReconnect()
      try? await channel.subscribeWithError()
    }
  }

  private func listenForMessages(conn: any WebSocket) {
    let stream = conn.events
    mutableState.withValue {
      $0.messageTask?.cancel()
      $0.messageTask = Task { [weak self] in
        guard let self else { return }

        do {
          for await event in stream {
            if Task.isCancelled { return }

            switch event {
            case .binary(let data):
              switch self.options.vsn {
              case .v1:
                options.logger?.warning(
                  "Received binary frame but vsn is 1.0.0; binary frames are only supported in 2.0.0"
                )
              case .v2:
                do {
                  let broadcast = try serializer.decodeBinary(data)
                  await onBroadcast(broadcast)
                } catch {
                  options.logger?.error("Failed to decode binary frame: \(error)")
                }
              }

            case .text(let text):
              let message: RealtimeMessageV2
              switch self.options.vsn {
              case .v1:
                message = try JSONDecoder().decode(RealtimeMessageV2.self, from: Data(text.utf8))
              case .v2:
                message = try serializer.decodeText(text)
              }
              await onMessage(message)

            case .close(let code, let reason):
              options.logger?.debug(
                "WebSocket closed. Code: \(code?.description ?? "<none>"), Reason: \(reason)"
              )

              await connectionManager.handleClose(code: code, reason: reason, from: conn)
            }
          }
        } catch is CancellationError {
          return
        } catch {
          if Task.isCancelled { return }
          options.logger?
            .debug(
              "WebSocket error \(error.localizedDescription). Trying again in \(options.reconnectDelay)"
            )
          await connectionManager.handleError(error, from: conn)
        }
      }
    }
  }

  private func startHeartbeating() {
    mutableState.withValue { state in
      state.heartbeatTask?.cancel()

      state.heartbeatTask = Task { [weak self, options, clock] in
        while !Task.isCancelled {
          try? await clock.sleep(for: .seconds(options.heartbeatInterval))
          guard let self, !Task.isCancelled else {
            break
          }
          await self.sendHeartbeat()
        }
      }
    }
  }

  private func sendHeartbeat() async {
    if status != .connected {
      heartbeatSubject.yield(.disconnected)
      return
    }

    // Check if previous heartbeat is still pending (not acknowledged).
    // Return the new ref if we should send, nil if previous heartbeat timed out.
    let heartbeatRef = mutableState.withValue { state -> String? in
      if state.pendingHeartbeatRef != nil {
        // Previous heartbeat was not acknowledged - this is a timeout
        return nil
      }

      // No pending heartbeat, we can send a new one
      let ref = makeRef()
      state.pendingHeartbeatRef = ref
      return ref
    }

    if let heartbeatRef {
      push(
        RealtimeMessageV2(
          joinRef: nil,
          ref: heartbeatRef,
          topic: "phoenix",
          event: "heartbeat",
          payload: [:]
        )
      )
      heartbeatSubject.yield(.sent)
      await setAuth()
    } else {
      // Timeout: previous heartbeat was never acknowledged
      options.logger?.debug("Heartbeat timeout - previous heartbeat not acknowledged")
      heartbeatSubject.yield(.timeout)

      // Clear the pending ref before reconnecting
      mutableState.withValue { $0.pendingHeartbeatRef = nil }

      // Scope the reconnect to the connection this heartbeat was sent on, so
      // a timeout that fires after a reconnect has already replaced the
      // socket can't tear down the healthy new connection.
      let conn = mutableState.withValue { $0.connection }
      await connectionManager.handleError(RealtimeError("heartbeat timeout"), from: conn)
    }
  }

  /// Closes the WebSocket connection.
  ///
  /// Cancels pending tasks, clears the send buffer, and emits a ``RealtimeClientStatus/disconnected``
  /// status. Any channels that are currently subscribed remain registered and will be re-joined
  /// automatically if ``connect()`` is called again.
  ///
  /// - Parameters:
  ///   - code: An optional numeric close code to send to the server.
  ///   - reason: An optional human-readable reason string.
  public func disconnect(code: Int? = nil, reason: String? = nil) {
    options.logger?.debug("Closing WebSocket connection")

    mutableState.withValue {
      $0.ref = 0
      $0.messageTask?.cancel()
      $0.messageTask = nil
      $0.heartbeatTask?.cancel()
      $0.heartbeatTask = nil
      $0.pendingHeartbeatRef = nil
      $0.pendingDisconnectTask?.cancel()
      $0.pendingDisconnectTask = nil
      $0.connection = nil
      $0.sendBuffer = []
      // A developer-initiated disconnect should not be undone on the next foreground event.
      $0.wasConnectedBeforeBackground = false
    }

    Self.yieldStatusIfChanged(statusSubject, .disconnected)

    Task { [connectionManager, reason] in
      await connectionManager.disconnect(reason: reason ?? "Client disconnect")
    }
  }

  /// Records that the app is entering the background. Captures whether the socket was connected
  /// at that moment so ``handleAppForeground()`` knows whether to attempt recovery when the app
  /// returns to the foreground.
  ///
  /// Invoked automatically by ``RealtimeLifecycleManager`` when
  /// ``RealtimeClientOptions/handleAppLifecycle`` is `true`.
  func handleAppBackground() {
    let wasConnected = status == .connected
    mutableState.withValue { $0.wasConnectedBeforeBackground = wasConnected }
  }

  /// Recover the connection on app foregrounding: reconnect and re-join existing channels if the
  /// socket was connected before the app backgrounded and has since been torn down. No-op if the
  /// socket was already disconnected at background time, or if it is still connected now.
  ///
  /// Invoked automatically by ``RealtimeLifecycleManager`` when
  /// ``RealtimeClientOptions/handleAppLifecycle`` is `true`.
  func handleAppForeground() async {
    // Atomic read-modify-write so two rapid foreground notifications can't both observe `true`.
    let wasConnected = mutableState.withValue { state -> Bool in
      let previous = state.wasConnectedBeforeBackground
      state.wasConnectedBeforeBackground = false
      return previous
    }

    guard wasConnected else { return }
    // Skip if already connected OR if an auto-reconnect is in-flight (.connecting),
    // because the state observer will drive rejoinChannels() when that reconnect completes.
    guard status == .disconnected else { return }

    let hadChannels = !mutableState.channels.isEmpty
    await connect()

    if hadChannels, status == .connected {
      await rejoinChannels()
    }
  }

  /// Updates the JWT access token used for channel authorization and Realtime RLS.
  ///
  /// When called, the token is propagated to all currently-subscribed channels. If `token`
  /// is `nil`, the value is fetched from ``RealtimeClientOptions/accessToken`` if provided,
  /// or the token already stored on the client is used.
  ///
  /// - Parameter token: A JWT string, or `nil` to refresh from the configured `accessToken` callback.
  public func setAuth(_ token: String? = nil) async {
    var tokenToSend = token

    if tokenToSend == nil {
      tokenToSend = try? await options.accessToken?()
    }

    guard tokenToSend != mutableState.accessToken else {
      return
    }

    mutableState.withValue { [tokenToSend] in
      $0.accessToken = tokenToSend
    }

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

  /// Routes a decoded binary broadcast to the appropriate channel.
  private func onBroadcast(_ broadcast: DecodedBroadcast) async {
    options.logger?.debug(
      "Received binary broadcast for topic \(broadcast.topic), event \(broadcast.event)"
    )

    let channel = mutableState.withValue {
      $0.channels[broadcast.topic]
    }

    if let channel {
      await channel.handleBinaryBroadcast(broadcast)
    }
  }

  /// Sends a message over the WebSocket, buffering it if the socket is not yet connected.
  ///
  /// If the socket is connected, the message is serialized and sent immediately.
  /// If the socket is not connected, the message is enqueued and flushed once the
  /// connection is established.
  ///
  /// - Parameter message: The ``RealtimeMessageV2`` to send.
  public func push(_ message: RealtimeMessageV2) {
    let callback = { @Sendable (_ client: RealtimeClientV2) in
      do {
        let text: String
        switch client.options.vsn {
        case .v1:
          let data = try JSONEncoder().encode(message)
          guard let encoded = String(data: data, encoding: .utf8) else {
            client.options.logger?.error("Failed to encode message as UTF-8.")
            return
          }
          text = encoded
        case .v2:
          text = try client.serializer.encodeText(message)
        }

        let conn = client.mutableState.withValue { $0.connection }
        conn?.send(text)
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
      callback(self)
    } else {
      mutableState.withValue {
        $0.sendBuffer.append(callback)
      }
    }
  }

  /// Push a broadcast message as a binary frame (type 0x03) with a JSON payload.
  func pushBroadcast(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    jsonPayload: JSONObject
  ) {
    let callback = { @Sendable (_ client: RealtimeClientV2) in
      do {
        let data = try client.serializer.encodeBroadcastPush(
          joinRef: joinRef,
          ref: ref,
          topic: topic,
          event: event,
          jsonPayload: jsonPayload
        )
        let conn = client.mutableState.withValue { $0.connection }
        conn?.send(data)
      } catch {
        client.options.logger?.error(
          """
          Failed to send binary broadcast:
          topic=\(topic), event=\(event)

          Error:
          \(error)
          """
        )
      }
    }

    if status == .connected {
      callback(self)
    } else {
      mutableState.withValue {
        $0.sendBuffer.append(callback)
      }
    }
  }

  /// Push a broadcast message as a binary frame (type 0x03) with a binary payload.
  func pushBroadcast(
    joinRef: String?,
    ref: String?,
    topic: String,
    event: String,
    binaryPayload: Data
  ) {
    let callback = { @Sendable (_ client: RealtimeClientV2) in
      do {
        let data = try client.serializer.encodeBroadcastPush(
          joinRef: joinRef,
          ref: ref,
          topic: topic,
          event: event,
          binaryPayload: binaryPayload
        )
        let conn = client.mutableState.withValue { $0.connection }
        conn?.send(data)
      } catch {
        client.options.logger?.error(
          """
          Failed to send binary broadcast:
          topic=\(topic), event=\(event)

          Error:
          \(error)
          """
        )
      }
    }

    if status == .connected {
      callback(self)
    } else {
      mutableState.withValue {
        $0.sendBuffer.append(callback)
      }
    }
  }

  private func flushSendBuffer() {
    mutableState.withValue {
      $0.sendBuffer.forEach { $0(self) }
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

  static func realtimeWebSocketURL(
    baseURL: URL, apikey: String?, vsn: RealtimeProtocolVersion, logLevel: LogLevel?
  ) -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    else {
      return baseURL
    }

    components.queryItems = components.queryItems ?? []
    if let apikey {
      components.queryItems!.append(URLQueryItem(name: "apikey", value: apikey))
    }
    components.queryItems!.append(URLQueryItem(name: "vsn", value: vsn.rawValue))

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
