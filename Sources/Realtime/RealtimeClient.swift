//
//  RealtimeClient.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
public import Foundation
import HTTPTypes
import Helpers
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Factory function for returning a new WebSocket connection.
typealias LegacyWebSocketTransport =
  @Sendable (_ url: URL, _ headers: [String: String]) async throws ->
  any WebSocket

/// An empty actor is a serial executor. One is created per ``RealtimeClient``; the client and
/// every channel it creates report its executor as their own, so Swift treats them as a single
/// isolation domain: hopping between them is free, and the compiler still checks every access.
actor RealtimeExecutor {}

/// The entry point for Supabase Realtime subscriptions.
///
/// `RealtimeClient` manages the underlying WebSocket connection and routes incoming events to
/// the ``RealtimeChannel`` instances it created. Create one client per Supabase project and
/// reuse it across your app.
///
/// ```swift
/// let client = RealtimeClient(
///   url: URL(string: "https://<project>.supabase.co/realtime/v1")!,
///   options: RealtimeClientOptions(accessToken: { session.accessToken })
/// )
///
/// try await client.connect()
///
/// let channel = await client.channel("room:lobby")
/// try await channel.subscribe()
/// ```
///
/// The client is an actor, and every channel it creates runs on the same executor, so reading
/// ``status`` from a channel never hops threads.
///
/// ## Topics
/// ### Channels
/// - ``channels``
/// - ``channel(_:options:)``
/// - ``removeChannel(_:)``
/// - ``removeAllChannels()``
/// ### Connection Status
/// - ``status``
/// - ``statusChanges()``
/// - ``connect()``
/// - ``disconnect(code:reason:)``
/// ### Heartbeat
/// - ``heartbeats()``
/// ### Authentication
/// - ``setAuth(_:)``
/// ### Sending Messages
/// - ``push(_:)``
public actor RealtimeClient {
  nonisolated let url: URL
  nonisolated let options: RealtimeClientOptions
  nonisolated let wsTransport: LegacyWebSocketTransport
  nonisolated let http: HTTPClient
  nonisolated let serializer = RealtimeSerializer()
  nonisolated let clock: any Clock<Duration>
  nonisolated let webSocketURL: URL

  /// The executor this client and its channels share.
  nonisolated let isolation = RealtimeExecutor()

  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    isolation.unownedExecutor
  }

  var accessToken: String?
  var ref = 0
  var pendingHeartbeatRef: String?

  enum ConnectionState: Equatable {
    case disconnected
    /// `connect()` is waiting on the transport (`connectAttempt`).
    case connecting
    case connected(any WebSocket)
    /// The reconnect loop (`tasks`, at `.connection`) is retrying with backoff.
    case reconnecting

    var status: RealtimeClientStatus {
      switch self {
      case .disconnected: .disconnected
      case .connecting, .reconnecting: .connecting
      case .connected: .connected
      }
    }

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
      switch (lhs, rhs) {
      case (.disconnected, .disconnected), (.connecting, .connecting),
        (.reconnecting, .reconnecting):
        true
      case (.connected(let a), .connected(let b)):
        a === b
      default:
        false
      }
    }
  }

  /// Only ever written by `apply(_:)`.
  var connection: ConnectionState = .disconnected

  /// The `connect()` attempt in flight while `connection` is `.connecting`. Kept outside the
  /// state so the transition table stays pure and comparable.
  var connectAttempt: Task<Void, any Error>?

  /// `apply(_:)` re-entrancy guard and the events raised while it was running.
  var isApplying = false
  var pendingEvents: [Event] = []

  /// Why an unstructured task exists. Starting a new run of some work replaces the previous
  /// run at the same location, so nothing has to be cancelled by hand.
  enum TaskLocation: Hashable {
    /// The reconnect loop (`initiateReconnect`).
    case connection
    /// The loop reading frames from the current socket.
    case socketReader
    /// The loop sending heartbeats on the current socket.
    case heartbeat
    /// The deferred `disconnect()` after the last channel is removed.
    case idleDisconnect
  }

  let tasks = TaskStorage<TaskLocation>()

  /// Counts socket installs and disconnects. The reader and heartbeat loops carry the value they
  /// were started with, so an event from a socket that has since been replaced is ignored.
  var generation = 0

  /// Frames pushed while the socket was not connected, sent in order once it is.
  var sendBuffer: [OutgoingFrame] = []

  /// Retains the optional app-lifecycle observer for the client's lifetime.
  /// Stored as `AnyObject?` so this type remains available on platforms where
  /// the concrete `RealtimeLifecycleManager` is not compiled.
  nonisolated(unsafe) var lifecycleManager: (any Sendable & AnyObject)?

  /// Whether the socket was `.connected` the last time the app entered the
  /// background. `handleAppForeground` only attempts recovery when this is
  /// `true` — otherwise foregrounding a client that was intentionally idle
  /// would spuriously open a connection.
  var wasConnectedBeforeBackground = false

  /// The current WebSocket connection status.
  public private(set) var status: RealtimeClientStatus = .disconnected
  private var statusContinuations: [UUID: AsyncStream<RealtimeClientStatus>.Continuation] = [:]

  private var lastHeartbeat: HeartbeatStatus?
  private var heartbeatContinuations: [UUID: AsyncStream<HeartbeatStatus>.Continuation] = [:]

  /// All managed channels indexed by their topics.
  ///
  /// The dictionary key is the fully-qualified topic string (e.g. `"realtime:room:lobby"`).
  /// Channels are added by ``channel(_:options:)`` and removed by ``removeChannel(_:)``
  /// or ``removeAllChannels()``.
  public private(set) var channels: [String: RealtimeChannel] = [:]

  /// Creates a new ``RealtimeClient`` using the default URLSession WebSocket transport.
  ///
  /// - Parameters:
  ///   - url: The Realtime server URL (e.g. `https://<project>.supabase.co/realtime/v1`).
  ///   - options: Configuration options for the client.
  public init(url: URL, options: RealtimeClientOptions) {
    let interceptors: [any ClientMiddleware] = [
      LoggerInterceptor(logger: options.logger)
    ]

    self.init(
      url: url,
      options: options,
      wsTransport: { url, headers in
        return try await URLSessionWebSocket.connect(
          to: url,
          headers: headers,
          session: options.session
        )
      },
      http: HTTPClient(configuration: options.http, appending: interceptors),
      clock: options.clock
    )
  }

  /// Designated initializer.
  ///
  /// `clock` is a separate parameter from ``RealtimeClientOptions/clock`` so tests can pair a
  /// `TestClock` with a stub `wsTransport`. The public initializer forwards `options.clock`, so
  /// the two only ever differ inside this package's own tests.
  init(
    url: URL,
    options: RealtimeClientOptions,
    wsTransport: @escaping LegacyWebSocketTransport,
    http: HTTPClient,
    clock: any Clock<Duration>
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
    self.webSocketURL = Self.realtimeWebSocketURL(
      baseURL: Self.realtimeBaseURL(url: url),
      apikey: options.apikey,
      logLevel: options.logLevel
    )

    if let accessToken = options.headers[.authorization]?.split(separator: " ").last {
      self.accessToken = String(accessToken)
    }

    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      if options.handleAppLifecycle {
        lifecycleManager = RealtimeLifecycleManager(client: self)
      }
    #endif
  }

  deinit {
    // Close the live socket first: cancelling the bookkeeping tasks alone leaves the
    // underlying WebSocket (and its URLSession) open when a connected client is released
    // without calling `disconnect()`. `deinit` only runs once no other code can reference the
    // actor, so reading isolated state here is safe.
    switch connection {
    case .connected(let conn):
      conn.close(code: nil, reason: "Client deallocated")
    case .connecting:
      connectAttempt?.cancel()
    case .reconnecting:
      break
    case .disconnected:
      break
    }
    // `tasks` cancels its own contents when it is destroyed right after this body.
    for continuation in statusContinuations.values {
      continuation.finish()
    }
    for continuation in heartbeatContinuations.values {
      continuation.finish()
    }
  }

  // MARK: - Status

  /// An async stream that emits connection status changes.
  ///
  /// The stream emits the current status immediately upon iteration and then each
  /// subsequent change. Cancelling the iterating task ends the stream; so does releasing the
  /// client.
  ///
  /// ```swift
  /// for await status in await client.statusChanges() {
  ///   print("Status changed to \(status)")
  /// }
  /// ```
  public func statusChanges() -> AsyncStream<RealtimeClientStatus> {
    let (stream, continuation) = AsyncStream<RealtimeClientStatus>.makeStream(
      bufferingPolicy: .unbounded
    )
    let id = UUID()
    statusContinuations[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeStream(id) }
    }
    continuation.yield(status)
    return stream
  }

  /// An async stream that emits heartbeat status updates.
  ///
  /// The client sends a heartbeat at each ``RealtimeClientOptions/defaultHeartbeatInterval``
  /// interval to keep the connection alive. The stream replays the latest status, if any, and
  /// then emits every later one. Cancelling the iterating task ends the stream; so does
  /// releasing the client.
  ///
  /// ```swift
  /// for await beat in await client.heartbeats() {
  ///   print("Heartbeat: \(beat)")
  /// }
  /// ```
  public func heartbeats() -> AsyncStream<HeartbeatStatus> {
    let (stream, continuation) = AsyncStream<HeartbeatStatus>.makeStream(
      bufferingPolicy: .unbounded
    )
    let id = UUID()
    heartbeatContinuations[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeStream(id) }
    }
    if let lastHeartbeat {
      continuation.yield(lastHeartbeat)
    }
    return stream
  }

  /// `onTermination` runs on the consumer's context, so the removal hops back here once.
  private func removeStream(_ id: UUID) {
    statusContinuations[id] = nil
    heartbeatContinuations[id] = nil
  }

  func setStatus(_ status: RealtimeClientStatus) {
    guard self.status != status else { return }
    self.status = status
    for continuation in statusContinuations.values {
      continuation.yield(status)
    }
  }

  func recordHeartbeat(_ status: HeartbeatStatus) {
    lastHeartbeat = status
    for continuation in heartbeatContinuations.values {
      continuation.yield(status)
    }
  }

  // MARK: - Channels

  /// Returns an existing channel for the given topic or creates a new one.
  ///
  /// The fully-qualified topic sent to the server is `"realtime:<topic>"`. If a channel
  /// with the same topic already exists, it is returned without modification.
  ///
  /// > Note: This method does not subscribe to the channel. Call ``RealtimeChannel/subscribe()``
  /// > on the returned instance to join the topic.
  ///
  /// - Parameters:
  ///   - topic: The channel topic name (without the `realtime:` prefix).
  ///   - options: A builder closure to configure ``RealtimeChannelConfig`` options such as
  ///     broadcast, presence, and privacy settings.
  /// - Returns: A ``RealtimeChannel`` bound to this client.
  public func channel(
    _ topic: String,
    options configure: @Sendable (inout RealtimeChannelConfig) -> Void = { _ in }
  ) -> RealtimeChannel {
    // Cancel any pending deferred disconnect — a new channel is being added.
    tasks.cancel(at: .idleDisconnect)

    let realtimeTopic = "realtime:\(topic)"

    if let channel = channels[realtimeTopic] {
      return channel
    }

    var config = RealtimeChannelConfig(
      broadcast: BroadcastJoinConfig(acknowledgeBroadcasts: false, receiveOwnBroadcasts: false),
      presence: PresenceJoinConfig(key: ""),
      isPrivate: false
    )
    configure(&config)

    let channel = RealtimeChannel(
      topic: realtimeTopic,
      config: config,
      client: self,
      logger: options.logger
    )

    channels[realtimeTopic] = channel

    return channel
  }

  /// Unsubscribes from and removes a channel, ending every stream opened on it.
  ///
  /// If the channel is currently subscribed, it is unsubscribed first. After removal,
  /// if no channels remain, the client disconnects (or schedules a deferred disconnect
  /// based on ``RealtimeClientOptions/defaultDisconnectOnEmptyChannelsAfter``).
  ///
  /// - Parameter channel: The channel to remove.
  public func removeChannel(_ channel: RealtimeChannel) async {
    if await channel.status == .subscribed {
      await channel.unsubscribe()
    }

    channels[channel.topic] = nil
    await channel.finishStreams()

    if channels.isEmpty {
      options.logger.debug("No more subscribed channel in socket")
      if options.disconnectOnEmptyChannelsAfter <= .zero {
        await disconnect()
      } else {
        schedulePendingDisconnect()
      }
    }
  }

  private func schedulePendingDisconnect() {
    let delay = options.disconnectOnEmptyChannelsAfter
    // Detached and weak: the sleep must not keep a released client alive for up to `delay`.
    let task = Task.detached { [weak self, clock] in
      do {
        try await clock.sleep(for: delay)
        await self?.disconnect()
      } catch {
        // Cancelled: a new channel was added or disconnect() was called directly.
      }
    }
    tasks.replace([task], at: .idleDisconnect)
  }

  /// Forgets a channel the server closed. The channel ends its own streams.
  func remove(_ channel: RealtimeChannel) {
    channels[channel.topic] = nil
  }

  /// Unsubscribes from and removes all channels, then disconnects immediately.
  ///
  /// Unlike ``removeChannel(_:)``, this method ignores
  /// ``RealtimeClientOptions/defaultDisconnectOnEmptyChannelsAfter`` and
  /// disconnects the WebSocket right away.
  public func removeAllChannels() async {
    // Keep the channels routable until they have unsubscribed: each one waits for the server's
    // `phx_close`, which `onMessage` can only deliver to a channel still in `channels`.
    let removed = Array(channels.values)
    await withTaskGroup(of: Void.self) { group in
      for channel in removed {
        group.addTask {
          if await channel.status == .subscribed {
            await channel.unsubscribe()
          }
          await channel.finishStreams()
        }
      }
      await group.waitForAll()
    }
    for channel in removed {
      channels[channel.topic] = nil
    }

    // Cancel any pending deferred disconnect and disconnect immediately.
    tasks.cancel(at: .idleDisconnect)
    await disconnect()
  }

  // MARK: - Authentication

  /// The token a channel joins with: the `accessToken` callback's value when there is one, else
  /// the token stored on the client.
  func currentAccessToken() async -> String? {
    if let accessToken = try? await options.accessToken?() {
      return accessToken
    }
    return accessToken
  }

  /// Updates the JWT access token used for channel authorization and Realtime RLS.
  ///
  /// When called, the token is propagated to all currently-subscribed channels. If `token`
  /// is `nil`, the value is fetched from the `accessToken` callback configured on
  /// ``RealtimeClientOptions`` if provided, or the token already stored on the client is used.
  ///
  /// If the `accessToken` callback throws, the client keeps the current token and no update is sent to channels.
  /// - Parameter token: A JWT string, or `nil` to refresh from the configured `accessToken` callback.
  public func setAuth(_ token: String? = nil) async {
    var tokenToSend = token

    if tokenToSend == nil {
      do {
        tokenToSend = try await options.accessToken?()
      } catch {
        options.logger.error("Failed to fetch access token: \(error)")
        return
      }
    }

    guard tokenToSend != accessToken else {
      return
    }

    accessToken = tokenToSend

    for channel in channels.values where await channel.status == .subscribed {
      options.logger.debug("Updating auth token for channel \(channel.topic)")
      await channel.push(
        ChannelEvent.accessToken,
        payload: ["access_token": tokenToSend.map { .string($0) } ?? .null]
      )
    }
  }

  // MARK: - Sending

  /// A frame waiting for, or going out on, the socket.
  enum OutgoingFrame {
    case text(String)
    case binary(Data)

    func send(on connection: any WebSocket) {
      switch self {
      case .text(let text): connection.send(text)
      case .binary(let data): connection.send(data)
      }
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
    do {
      send(.text(try serializer.encodeText(message)))
    } catch {
      options.logger.error(
        """
        Failed to send message:
        \(message)

        Error:
        \(error)
        """
      )
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
    do {
      send(
        .binary(
          try serializer.encodeBroadcastPush(
            joinRef: joinRef, ref: ref, topic: topic, event: event, jsonPayload: jsonPayload
          )
        )
      )
    } catch {
      logBroadcastEncodingFailure(topic: topic, event: event, error: error)
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
    do {
      send(
        .binary(
          try serializer.encodeBroadcastPush(
            joinRef: joinRef, ref: ref, topic: topic, event: event, binaryPayload: binaryPayload
          )
        )
      )
    } catch {
      logBroadcastEncodingFailure(topic: topic, event: event, error: error)
    }
  }

  private func logBroadcastEncodingFailure(topic: String, event: String, error: any Error) {
    options.logger.error(
      """
      Failed to send binary broadcast:
      topic=\(topic), event=\(event)

      Error:
      \(error)
      """
    )
  }

  private func send(_ frame: OutgoingFrame) {
    if case .connected(let conn) = connection {
      frame.send(on: conn)
    } else {
      sendBuffer.append(frame)
    }
  }

  func flushSendBuffer() {
    guard case .connected(let conn) = connection else { return }
    let frames = sendBuffer
    sendBuffer = []
    for frame in frames {
      frame.send(on: conn)
    }
  }

  func makeRef() -> String {
    ref += 1
    return ref.description
  }

  // MARK: - URLs

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
    baseURL: URL, apikey: String?, logLevel: LogLevel?
  ) -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    else {
      return baseURL
    }

    var queryItems = components.queryItems ?? []

    if let apikey {
      queryItems.append(URLQueryItem(name: "apikey", value: apikey))
    }

    queryItems.append(URLQueryItem(name: "vsn", value: "2.0.0"))

    if let logLevel {
      queryItems.append(URLQueryItem(name: "log_level", value: logLevel.rawValue))
    }

    components.queryItems = queryItems

    components.path.append("/websocket")
    components.path = components.path.replacingOccurrences(of: "//", with: "/")

    guard let url = components.url else {
      return baseURL
    }

    return url
  }

  /// Builds the REST broadcast URL for a single event: `.../api/broadcast/{topic}/events/{event}`.
  ///
  /// Topic and event are percent-encoded as individual path segments (so values containing
  /// `/` don't introduce extra path components), and a private channel adds `?private=true`.
  nonisolated func broadcastURL(topic: String, event: String, isPrivate: Bool) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }

    let encodedTopic =
      topic.addingPercentEncoding(withAllowedCharacters: .sbURLPathComponentAllowed) ?? topic
    let encodedEvent =
      event.addingPercentEncoding(withAllowedCharacters: .sbURLPathComponentAllowed) ?? event

    var path = components.percentEncodedPath
    if path.hasSuffix("/") { path.removeLast() }
    path += "/api/broadcast/\(encodedTopic)/events/\(encodedEvent)"
    components.percentEncodedPath = path

    if isPrivate {
      components.queryItems = [URLQueryItem(name: "private", value: "true")]
    }

    guard let url = components.url else {
      return url
    }

    return url
  }
}

extension CharacterSet {
  /// Characters allowed in a single percent-encoded URL path segment (e.g. a broadcast
  /// topic or event name).
  ///
  /// Restricted to RFC 3986 "unreserved" characters so values containing `/`, `:`, or other
  /// reserved characters are always escaped rather than being interpreted as additional
  /// path structure.
  static let sbURLPathComponentAllowed: CharacterSet = {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return allowed
  }()
}
