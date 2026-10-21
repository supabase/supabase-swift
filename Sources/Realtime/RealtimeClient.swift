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
  nonisolated let transport: any WebSocketTransport
  nonisolated let http: HTTPClient
  nonisolated let serializer = RealtimeSerializer()
  nonisolated let clock: any Clock<Duration>
  nonisolated let webSocketURL: URL

  /// The executor this client and its channels share.
  nonisolated let isolation = RealtimeExecutor()

  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    isolation.unownedExecutor
  }

  /// How long before the token's `exp` the client asks the `accessToken` callback for a new
  /// one. The server closes every channel the moment the token expires.
  static let accessTokenRefreshLeeway: Duration = .seconds(60)
  /// The shortest wait between two `accessToken` callback calls, so a token already inside the
  /// leeway, or a callback that fails, is retried at this pace instead of in a tight loop.
  static let accessTokenRefreshInterval: Duration = .seconds(10)

  var tokens = TokenState()
  /// Whether an `accessToken` callback call is in flight. Concurrent refreshes wait for it.
  var isFetchingAccessToken = false
  /// The callers waiting for the call in flight. A cancelled caller is resumed early.
  var accessTokenWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
  /// When the `accessToken` callback was last called, as read from `elapsed`.
  var lastAccessTokenFetch: Duration?
  /// The time since the client was created, on `clock`.
  nonisolated let elapsed: @Sendable () -> Duration
  /// The wall-clock time, advanced by `clock`, so a `TestClock` also drives token expiry.
  nonisolated let now: @Sendable () -> Date

  var accessToken: String? { tokens.token }
  var ref = 0
  var pendingHeartbeatRef: String?

  enum ConnectionState: Equatable {
    case disconnected
    /// `connect()` is waiting on the transport (`connectAttempt`).
    case connecting
    case connected(any WebSocketConnection)
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
    /// The timer that refreshes the access token before it expires.
    case accessTokenRefresh
  }

  let tasks = TaskStorage<TaskLocation>()

  /// Counts socket installs and disconnects. The reader and heartbeat loops carry the value they
  /// were started with, so an event from a socket that has since been replaced is ignored.
  var generation = 0

  /// Frames pushed while the socket was not connected, sent in order once it is.
  var sendBuffer: [WebSocketFrame] = []

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
      transport: URLSessionWebSocketTransport(
        configuration: options.session?.configuration ?? .default,
        delegate: options.session?.delegate
      ),
      http: HTTPClient(configuration: options.http, appending: interceptors),
      clock: options.clock
    )
  }

  /// Designated initializer.
  ///
  /// `clock` is a separate parameter from ``RealtimeClientOptions/clock`` so tests can pair a
  /// `TestClock` with a stub `transport`. The public initializer forwards `options.clock`, so
  /// the two only ever differ inside this package's own tests.
  init(
    url: URL,
    options: RealtimeClientOptions,
    transport: any WebSocketTransport,
    http: HTTPClient,
    clock: any Clock<Duration>
  ) {
    var options = options
    if options.headers[.xClientInfo] == nil {
      options.headers[.xClientInfo] = "realtime-swift/\(version)"
    }

    self.url = url
    self.options = options
    self.transport = transport
    self.http = http
    self.clock = clock
    let elapsed = Self.elapsedTime(on: clock)
    let start = Date()
    self.elapsed = elapsed
    self.now = { start.addingTimeInterval(elapsed().timeInterval) }
    self.webSocketURL = Self.realtimeWebSocketURL(
      baseURL: Self.realtimeBaseURL(url: url),
      apikey: options.apikey,
      logLevel: options.logLevel
    )

    if let accessToken = options.headers[.authorization]?.split(separator: " ").last {
      _ = tokens.apply(String(accessToken), generation: tokens.beginRefresh())
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
      conn.close(code: .normalClosure, reason: "Client deallocated")
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
    // The refresh timer runs only while connected: it stops here on a disconnect and starts
    // again on every connect and reconnect.
    scheduleAccessTokenRefresh()
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

  /// The token a channel joins with, refreshed from the `accessToken` callback first unless it
  /// was called within ``accessTokenRefreshInterval``. While a refresh is in flight, the stored
  /// token is returned at once; only a client with no token yet waits for the refresh.
  func currentAccessToken() async -> String? {
    if !isFetchingAccessToken || tokens.token == nil {
      await refreshAccessToken()
    }
    return tokens.token
  }

  /// Updates the JWT access token used for channel authorization and Realtime RLS.
  ///
  /// When the token changes, it is sent to all currently-subscribed channels. If `token` is
  /// `nil`, the value is fetched from the `accessToken` callback configured on
  /// ``RealtimeClientOptions``. The callback is called at most once every 10 seconds; inside
  /// that window the stored token is kept. A callback that does not return within
  /// ``RealtimeClientOptions/timeout`` is treated as failed.
  ///
  /// While the client is connected, the callback is set, and the token is a JWT, the client also
  /// calls the callback one minute before the token's `exp`, so channels are not closed when it
  /// expires.
  ///
  /// If the callback throws or returns `nil`, the client keeps the current token and no update
  /// is sent to channels. A callback result that arrives after a newer token was set with this
  /// method is discarded.
  /// - Parameter token: A JWT string, or `nil` to refresh from the configured `accessToken` callback.
  public func setAuth(_ token: String? = nil) async {
    guard let token else {
      await refreshAccessToken()
      return
    }
    // An unchanged token must not start a new generation: that would discard a newer token from
    // a callback call in flight.
    guard token != tokens.token else { return }
    await storeAccessToken(token, generation: tokens.beginRefresh())
  }

  /// Calls the `accessToken` callback even inside ``accessTokenRefreshInterval``, for a channel
  /// whose join the server refused because of its token.
  func refreshTokenForRejoin() async {
    await refreshAccessToken(ignoringInterval: true)
  }

  /// Asks the `accessToken` callback for a token and stores it unless a newer token was set
  /// while the callback ran. A caller that arrives while a call is in flight waits for it
  /// instead of starting another.
  func refreshAccessToken(ignoringInterval: Bool = false) async {
    guard let provider = options.accessToken else { return }
    if isFetchingAccessToken {
      return await waitForAccessTokenFetch()
    }
    let now = elapsed()
    if !ignoringInterval, let last = lastAccessTokenFetch,
      now - last < Self.accessTokenRefreshInterval
    {
      return
    }
    lastAccessTokenFetch = now
    isFetchingAccessToken = true

    let generation = tokens.beginRefresh()
    let timeout = options.timeout
    let logger = options.logger
    // A local, because the existential in `self.clock` is not opened when passed directly.
    let clock = self.clock
    // A task of its own, so a cancelled caller does not cancel the call the others wait for.
    Task.immediateIfAvailable { [weak self] in
      let token = await Self.callAccessTokenProvider(
        provider, timeout: timeout, clock: clock, logger: logger)
      await self?.didFetchAccessToken(token, generation: generation)
    }
    await waitForAccessTokenFetch()
  }

  /// Calls `provider` and returns its token, or `nil` when it throws or does not return within
  /// `timeout`. A call that ignores cancellation is left to finish on its own and its result is
  /// dropped, so it cannot hold up the refreshes waiting for it. `withTimeout` cannot do this:
  /// its task group waits for the call to return.
  private static func callAccessTokenProvider(
    _ provider: @escaping @Sendable () async throws -> String?,
    timeout: Duration,
    clock: some Clock<Duration>,
    logger: Logger
  ) async -> String? {
    let deadline = clock.now.advanced(by: timeout)
    let pending = LockIsolated<CheckedContinuation<String?, Never>?>(nil)
    let timer = LockIsolated<Task<Void, Never>?>(nil)
    let finish: @Sendable (String?) -> Void = { token in
      pending.withValue {
        $0?.resume(returning: token)
        $0 = nil
      }
    }
    return await withCheckedContinuation { continuation in
      pending.setValue(continuation)
      let call = Task {
        let token: String?
        do {
          token = try await provider()
        } catch {
          logger.error("Failed to fetch access token: \(error)")
          token = nil
        }
        timer.value?.cancel()
        finish(token)
      }
      timer.setValue(
        Task {
          do {
            try await clock.sleep(until: deadline, tolerance: nil)
          } catch {
            return
          }
          logger.error("The access token callback did not return within \(timeout)")
          call.cancel()
          finish(nil)
        })
    }
  }

  /// Returns when the callback call in flight has finished, or at once when the caller is
  /// cancelled.
  private func waitForAccessTokenFetch() async {
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if isFetchingAccessToken, !Task.isCancelled {
          accessTokenWaiters[id] = continuation
        } else {
          continuation.resume()
        }
      }
    } onCancel: {
      Task { await self.stopWaitingForAccessTokenFetch(id) }
    }
  }

  private func stopWaitingForAccessTokenFetch(_ id: UUID) {
    accessTokenWaiters.removeValue(forKey: id)?.resume()
  }

  private func didFetchAccessToken(_ token: String?, generation: Int) async {
    if await !storeAccessToken(token, generation: generation) {
      // Scheduled even when nothing changed, so a callback that failed or returned the same
      // token is asked again.
      scheduleAccessTokenRefresh()
    }
    isFetchingAccessToken = false
    let waiters = accessTokenWaiters.values
    accessTokenWaiters = [:]
    for waiter in waiters {
      waiter.resume()
    }
  }

  /// Stores `token` if it is new and from the latest refresh, then sends it to every subscribed
  /// channel. Returns whether it was stored.
  @discardableResult
  private func storeAccessToken(_ token: String?, generation: Int) async -> Bool {
    guard tokens.apply(token, generation: generation), let token = tokens.token else {
      return false
    }
    scheduleAccessTokenRefresh()

    for channel in channels.values where await channel.status == .subscribed {
      // A newer token was stored while this loop was suspended; its own loop sends it.
      guard tokens.token == token else { break }
      options.logger.debug("Updating auth token for channel \(channel.topic)")
      await channel.push(ChannelEvent.accessToken, payload: ["access_token": .string(token)])
    }
    return true
  }

  /// Refreshes ``accessTokenRefreshLeeway`` before the token's `exp`, and never sooner than
  /// ``accessTokenRefreshInterval`` from now, which the callback would refuse anyway. A new
  /// token replaces the timer. Without a connection, a callback, or a token with an `exp`, there
  /// is nothing to schedule: the next join or heartbeat refreshes the token instead.
  private func scheduleAccessTokenRefresh() {
    guard options.accessToken != nil, status == .connected,
      let due = tokens.refreshDelay(now: now(), leeway: Self.accessTokenRefreshLeeway)
    else {
      tasks.cancel(at: .accessTokenRefresh)
      return
    }
    let delay = max(due, Self.accessTokenRefreshInterval)
    // A local, because the existential in `self.clock` is not opened when passed directly.
    let clock = self.clock
    let timer = Self.accessTokenRefreshTimer(on: clock, after: delay, client: self)
    tasks.replace([timer], at: .accessTokenRefresh)
  }

  /// The refresh timer's entry point. A client that disconnected since the timer was set has no
  /// channel to keep alive, so it does not call the callback.
  func refreshAccessTokenIfConnected() async {
    guard status == .connected else { return }
    await refreshAccessToken()
  }

  /// The deadline is read here, not inside the task, so a task that starts late still wakes
  /// `delay` after the token was stored.
  private static func accessTokenRefreshTimer(
    on clock: some Clock<Duration>,
    after delay: Duration,
    client: RealtimeClient
  ) -> Task<Void, Never> {
    let deadline = clock.now.advanced(by: delay)
    // Detached and weak: the sleep must not keep a released client alive until the token expires.
    return Task.detached { [weak client] in
      do {
        try await clock.sleep(until: deadline, tolerance: nil)
        await client?.refreshAccessTokenIfConnected()
      } catch {
        // Cancelled: a newer token replaced this timer.
      }
    }
  }

  /// Reads the time since this call on `clock`. A generic function opens the existential, so
  /// two instants of the same concrete clock can be subtracted.
  private static func elapsedTime(on clock: some Clock<Duration>) -> @Sendable () -> Duration {
    let start = clock.now
    return { start.duration(to: clock.now) }
  }

  // MARK: - Sending

  /// Sends a message over the WebSocket, buffering it if the socket is not yet connected.
  ///
  /// If the socket is connected, the message is serialized and sent immediately.
  /// If the socket is not connected, the message is enqueued and flushed once the
  /// connection is established.
  ///
  /// - Parameter message: The ``RealtimeMessageV2`` to send.
  public func push(_ message: RealtimeMessageV2) async {
    do {
      await send(.text(try serializer.encodeText(message)))
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
  ) async {
    do {
      await send(
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
  ) async {
    do {
      await send(
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

  /// Frames queue behind any still in `sendBuffer`, so a push made while the buffer is being
  /// flushed cannot overtake it.
  private func send(_ frame: WebSocketFrame) async {
    guard case .connected(let conn) = connection, sendBuffer.isEmpty else {
      sendBuffer.append(frame)
      return
    }
    await send(frame, on: conn)
  }

  /// Sends the buffered frames in order. Stops if `conn` stops being the current connection;
  /// the frames left over wait for the next one.
  func flushSendBuffer(on conn: any WebSocketConnection) async {
    while !sendBuffer.isEmpty, case .connected(let current) = connection, current === conn {
      await send(sendBuffer.removeFirst(), on: conn)
    }
  }

  /// A failed send closes the connection, and the reader reports that close, so the error is
  /// only logged here.
  private func send(_ frame: WebSocketFrame, on conn: any WebSocketConnection) async {
    do {
      try await conn.send(frame)
    } catch {
      options.logger.error("Failed to send frame: \(error)")
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
