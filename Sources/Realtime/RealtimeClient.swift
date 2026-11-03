//
//  RealtimeClient.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

import ConcurrencyExtras
public import Foundation
internal import HTTPTypes
import Helpers
import IssueReporting
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
/// - ``channel(_:configure:)``
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
public actor RealtimeClient {
  nonisolated let url: URL
  nonisolated let options: RealtimeClientOptions
  /// ``RealtimeClientOptions/logger``, or the default logger when it is `nil`, tagged with the
  /// `system` metadata key set to `realtime`.
  nonisolated let logger: Logger
  /// `options.headers` with `X-Client-Info` added when the app did not set it.
  nonisolated let headers: HTTPFields
  nonisolated let transport: any WebSocketTransport
  nonisolated let http: HTTPClient
  nonisolated let serializer = RealtimeSerializer()
  nonisolated let clock: any Clock<Duration>
  nonisolated let webSocketURL: URL
  /// The wait before each reconnect attempt. Internal, like the channel rejoin backoff; tests
  /// pass their own through the designated initializer.
  nonisolated let reconnectBackoff: BackoffPolicy
  /// A random wait in `0...min(30 s, 1 s · 2^(attempt-1))`.
  static let defaultReconnectBackoff = BackoffPolicy.fullJitter(
    base: .seconds(1), cap: .seconds(30))
  /// The random source for the backoff jitter. Tests pin it to make the waits exact.
  nonisolated let jitter: @Sendable (ClosedRange<Double>) -> Double

  /// The executor this client and its channels share.
  nonisolated let isolation = RealtimeExecutor()

  /// The serial executor this client shares with every channel it creates.
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
  /// How many `accessToken` callback calls have started.
  var accessTokenFetchCount = 0
  /// When the `accessToken` callback was last called, as read from `elapsed`.
  var lastAccessTokenFetch: Duration?
  /// The time since the client was created, on `clock`.
  nonisolated let elapsed: @Sendable () -> Duration
  /// The wall-clock time, advanced by `clock`, so a `TestClock` also drives token expiry.
  nonisolated let now: @Sendable () -> Date

  var accessToken: String? { tokens.token }
  var ref = 0
  var pendingHeartbeatRef: String?
  /// When the pending heartbeat was sent, as read from `elapsed`.
  var pendingHeartbeatSentAt: Duration?

  enum ConnectionState: Equatable {
    /// Idle or stopped. Carries the error when a failure, not the user, stopped the client.
    case disconnected(RealtimeError?)
    /// The transport is opening a socket (`connectAttempt`). Attempt 1 is the user's
    /// `connect()`; later attempts are automatic retries after a drop.
    case connecting(attempt: Int)
    case connected(any WebSocketConnection)
    /// Waiting `retryIn` (the timer in `tasks`, at `.connection`) before attempt `attempt + 1`.
    case reconnecting(attempt: Int, retryIn: Duration, lastError: RealtimeError)

    var status: RealtimeClientStatus {
      switch self {
      case .disconnected(let error): .disconnected(error)
      case .connecting(let attempt): .connecting(attempt: attempt)
      case .connected: .connected
      case .reconnecting(let attempt, let retryIn, let lastError):
        .reconnecting(attempt: attempt, retryIn: retryIn, lastError: lastError)
      }
    }

    var error: RealtimeError? {
      switch self {
      case .disconnected(let error): error
      case .reconnecting(_, _, let error): error
      case .connecting, .connected: nil
      }
    }

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
      switch (lhs, rhs) {
      case (.disconnected(let a), .disconnected(let b)):
        a?.isSameFailure(as: b) ?? (b == nil)
      case (.connecting(let a), .connecting(let b)):
        a == b
      case (.connected(let a), .connected(let b)):
        a === b
      case (.reconnecting(let a, let da, let ea), .reconnecting(let b, let db, let eb)):
        a == b && da == db && ea.isSameFailure(as: eb)
      default:
        false
      }
    }
  }

  /// Only ever written by `apply(_:)`.
  var connection: ConnectionState = .disconnected(nil)

  /// The `connect()` attempt in flight while `connection` is `.connecting`. Kept outside the
  /// state so the transition table stays pure and comparable.
  var connectAttempt: Task<Void, any Error>?

  /// `apply(_:)` re-entrancy guard and the events raised while it was running.
  var isApplying = false
  var pendingEvents: [Event] = []

  /// Why an unstructured task exists. Starting a new run of some work replaces the previous
  /// run at the same location, so nothing has to be cancelled by hand.
  enum TaskLocation: Hashable {
    /// The backoff timer before the next reconnect attempt.
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
  public var status: RealtimeClientStatus { connection.status }
  private var statusContinuations: [UUID: AsyncStream<RealtimeClientStatus>.Continuation] = [:]

  private var lastHeartbeat: HeartbeatEvent?
  private var heartbeatContinuations: [UUID: AsyncStream<HeartbeatEvent>.Continuation] = [:]

  /// Every channel this client created and has not removed.
  ///
  /// ``channel(_:configure:)`` adds a channel. ``removeChannel(_:)``, ``removeAllChannels()``,
  /// and a server that closes the channel remove it. The order is not specified.
  public var channels: [RealtimeChannel] { Array(channelsByTopic.values) }

  /// The channels by their ``RealtimeChannel/topic``. Incoming messages carry the wire topic; see
  /// ``RealtimeChannel/topic(forWireTopic:)``.
  private(set) var channelsByTopic: [String: RealtimeChannel] = [:]

  /// Creates a new ``RealtimeClient``.
  ///
  /// The client connects through ``RealtimeClientOptions/webSocketTransport``, or through
  /// ``URLSessionWebSocketTransport`` when that option is `nil`.
  ///
  /// - Parameters:
  ///   - url: The Realtime server URL (e.g. `https://<project>.supabase.co/realtime/v1`).
  ///   - options: Configuration options for the client.
  public init(url: URL, options: RealtimeClientOptions) {
    let interceptors: [any ClientMiddleware] = [
      LoggerInterceptor(logger: Self.logger(for: options))
    ]

    self.init(
      url: url,
      options: options,
      transport: options.webSocketTransport ?? URLSessionWebSocketTransport(),
      http: HTTPClient(configuration: options.http, appending: interceptors),
      clock: options.clock
    )
  }

  private static func logger(for options: RealtimeClientOptions) -> Logger {
    var logger = options.logger ?? supabaseDefaultLogger(label: "io.supabase.realtime")
    logger[metadataKey: "system"] = "realtime"
    return logger
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
    clock: any Clock<Duration>,
    reconnectBackoff: BackoffPolicy = defaultReconnectBackoff,
    jitter: @escaping @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
  ) {
    var headers = HTTPFields(options.headers)
    if headers[.xClientInfo] == nil {
      headers[.xClientInfo] = "realtime-swift/\(version)"
    }

    self.url = url
    self.options = options
    self.logger = Self.logger(for: options)
    self.headers = headers
    self.transport = transport
    self.http = http
    self.clock = clock
    let elapsed = Self.elapsedTime(on: clock)
    let start = Date()
    self.elapsed = elapsed
    self.now = { start.addingTimeInterval(elapsed().timeInterval) }
    self.reconnectBackoff = reconnectBackoff
    self.jitter = jitter
    self.webSocketURL = Self.realtimeWebSocketURL(
      baseURL: Self.realtimeBaseURL(url: url),
      apikey: headers[.apiKey],
      serverLogLevel: options.serverLogLevel
    )

    if let accessToken = headers[.authorization]?.split(separator: " ").last {
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
    case .reconnecting, .disconnected:
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

  /// An async stream that emits each step of the heartbeat cycle.
  ///
  /// The client sends a heartbeat at each ``RealtimeClientOptions/heartbeatInterval``
  /// interval to keep the connection alive. The stream replays the latest event, if any, and
  /// then emits every later one. Cancelling the iterating task ends the stream; so does
  /// releasing the client.
  ///
  /// ```swift
  /// for await event in await client.heartbeats() {
  ///   if case .acknowledged(let latency) = event {
  ///     print("Round trip: \(latency)")
  ///   }
  /// }
  /// ```
  public func heartbeats() -> AsyncStream<HeartbeatEvent> {
    let (stream, continuation) = AsyncStream<HeartbeatEvent>.makeStream(
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

  /// Called by `apply(_:)` after `connection` changed.
  func connectionDidChange() {
    // The refresh timer runs only while connected: it stops here on a disconnect and starts
    // again on every connect and reconnect.
    scheduleAccessTokenRefresh()
    let status = status
    for continuation in statusContinuations.values {
      continuation.yield(status)
    }
  }

  func recordHeartbeat(_ event: HeartbeatEvent) {
    lastHeartbeat = event
    for continuation in heartbeatContinuations.values {
      continuation.yield(event)
    }
  }

  // MARK: - Channels

  /// Returns an existing channel for the given topic or creates a new one.
  ///
  /// The returned channel's ``RealtimeChannel/topic`` is `topic`; the SDK adds the `realtime:`
  /// prefix the server expects on the WebSocket only. The client keeps one
  /// channel per topic: when a channel with the same topic already exists, it is returned
  /// unchanged. Asking for it with a different configuration reports an issue, because the
  /// configuration is fixed when the channel is created; remove the channel first to change it.
  ///
  /// > Note: This method does not subscribe to the channel. Call ``RealtimeChannel/subscribe()``
  /// > on the returned instance to join the topic.
  ///
  /// - Parameters:
  ///   - topic: The channel topic name, such as `"room:lobby"`.
  ///   - configure: A closure that sets the channel's ``RealtimeChannelConfiguration``: privacy,
  ///     broadcast, presence and Postgres changes options.
  /// - Returns: A ``RealtimeChannel`` bound to this client.
  public func channel(
    _ topic: String,
    configure: @Sendable (inout RealtimeChannelConfiguration) -> Void = { _ in }
  ) -> RealtimeChannel {
    apply(.channelAdded)

    var configuration = RealtimeChannelConfiguration()
    configure(&configuration)

    if let channel = channelsByTopic[topic] {
      if channel.configuration != configuration {
        reportIssue(
          """
          Channel "\(topic)" already exists with a different configuration. The existing channel \
          is returned unchanged; remove it first to change its configuration.
          """
        )
      }
      return channel
    }

    let channel = RealtimeChannel(
      topic: topic,
      configuration: configuration,
      client: self,
      logger: logger
    )

    channelsByTopic[topic] = channel

    return channel
  }

  /// Unsubscribes from and removes a channel, ending every stream opened on it.
  ///
  /// The channel is unsubscribed first, which also stops a join still in flight, and it never
  /// joins again: get a new one from ``channel(_:configure:)``. After removal, if no channels
  /// remain, the client disconnects (or schedules a deferred disconnect based on
  /// ``RealtimeClientOptions/disconnectOnEmptyChannelsAfter``).
  ///
  /// - Parameter channel: The channel to remove.
  public func removeChannel(_ channel: RealtimeChannel) async {
    await channel.unsubscribeForRemoval()

    forget(channel)
    await channel.finishStreams()

    if channelsByTopic.isEmpty {
      logger.debug("No more subscribed channel in socket")
      if options.disconnectOnEmptyChannelsAfter <= .zero {
        await disconnect()
      } else {
        apply(.lastChannelRemoved(disconnectAfter: options.disconnectOnEmptyChannelsAfter))
      }
    }
  }

  /// Forgets a channel the server closed. The channel ends its own streams.
  func remove(_ channel: RealtimeChannel) {
    forget(channel)
  }

  /// Clears `channel`'s topic only while it still holds `channel`: a newer channel created for
  /// the same topic after `channel` was removed stays registered.
  private func forget(_ channel: RealtimeChannel) {
    if channelsByTopic[channel.topic] === channel {
      channelsByTopic[channel.topic] = nil
    }
  }

  /// Unsubscribes from and removes all channels, then disconnects immediately.
  ///
  /// Unlike ``removeChannel(_:)``, this method ignores
  /// ``RealtimeClientOptions/disconnectOnEmptyChannelsAfter`` and
  /// disconnects the WebSocket right away.
  public func removeAllChannels() async {
    // Keep the channels routable until they have unsubscribed: each one waits for the server's
    // `phx_close`, which `onMessage` can only deliver to a channel still in `channels`.
    let removed = Array(channelsByTopic.values)
    await withTaskGroup(of: Void.self) { group in
      for channel in removed {
        group.addTask {
          await channel.unsubscribeForRemoval()
          await channel.finishStreams()
        }
      }
      await group.waitForAll()
    }
    for channel in removed {
      forget(channel)
    }

    // `disconnect()` also cancels a pending idle disconnect.
    await disconnect()
  }

  // MARK: - Authentication

  /// The token a channel joins with, refreshed from the `accessToken` callback first unless it
  /// was called within ``accessTokenRefreshInterval``. A join that arrives while a call is in
  /// flight waits for it: the stored token may be expired, or the key from the `Authorization`
  /// header.
  func currentAccessToken() async -> String? {
    await refreshAccessToken()
    return tokens.token
  }

  /// Updates the JWT access token used for channel authorization and Realtime RLS.
  ///
  /// When the token changes, it is sent to all currently-subscribed channels. If `token` is
  /// `nil`, the value is fetched from the `accessToken` callback configured on
  /// ``RealtimeClientOptions``. The callback is called at most once every 10 seconds; inside
  /// that window the stored token is kept. A callback that does not return within
  /// ``RealtimeClientOptions/requestTimeout`` is treated as failed.
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
    guard token != tokens.token, tokens.apply(token, generation: tokens.beginRefresh()) else {
      return
    }
    scheduleAccessTokenRefresh()
    await pushAccessToken(token)
  }

  /// Calls the `accessToken` callback even inside ``accessTokenRefreshInterval``, for a channel
  /// whose join the server refused because of its token. A call already in flight started
  /// before the refusal and may return the refused token, so a new call follows it unless
  /// another caller already started one.
  func refreshTokenForRejoin() async {
    let fetchesBefore = accessTokenFetchCount
    if isFetchingAccessToken {
      await waitForAccessTokenFetch()
    }
    if accessTokenFetchCount == fetchesBefore {
      await refreshAccessToken(ignoringInterval: true)
    } else if isFetchingAccessToken {
      await waitForAccessTokenFetch()
    }
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
    accessTokenFetchCount += 1

    let generation = tokens.beginRefresh()
    let timeout = options.requestTimeout
    let logger = self.logger
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
    let call = LockIsolated<Task<Void, Never>?>(nil)
    // Returns whether this resumed the caller: only the first of the call and the timer does.
    let finish: @Sendable (String?) -> Bool = { token in
      pending.withValue { continuation in
        guard let waiting = continuation else { return false }
        continuation = nil
        waiting.resume(returning: token)
        return true
      }
    }
    return await withCheckedContinuation { continuation in
      pending.setValue(continuation)
      // The timer exists before the call starts, so a call that returns at once can cancel it.
      let timer = Task {
        do {
          try await clock.sleep(until: deadline, tolerance: nil)
        } catch {
          return
        }
        guard finish(nil) else { return }
        logger.error("The access token callback did not return within \(timeout)")
        call.value?.cancel()
      }
      call.setValue(
        Task {
          let token: String?
          do {
            token = try await provider()
          } catch {
            logger.error("Failed to fetch access token: \(error)")
            token = nil
          }
          timer.cancel()
          _ = finish(token)
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

  /// Stores the result, then resumes the waiters before the token is sent to channels, so a
  /// join waiting for it does not also wait for every push.
  private func didFetchAccessToken(_ token: String?, generation: Int) async {
    let stored = tokens.apply(token, generation: generation)
    // Scheduled even when nothing changed, so a callback that failed or returned the same token
    // is asked again.
    scheduleAccessTokenRefresh()
    isFetchingAccessToken = false
    let waiters = accessTokenWaiters.values
    accessTokenWaiters = [:]
    for waiter in waiters {
      waiter.resume()
    }
    if stored, let token = tokens.token {
      await pushAccessToken(token)
    }
  }

  /// Sends `token` to every subscribed channel, and to every channel whose `phx_join` already
  /// went out with another token. A channel still waiting for a token joins with this one.
  private func pushAccessToken(_ token: String) async {
    for channel in channelsByTopic.values {
      // A newer token was stored while this loop was suspended; its own loop sends it.
      guard tokens.token == token else { break }
      switch await channel.status {
      case .subscribed:
        break
      case .subscribing, .resubscribing:
        guard await channel.joinRef != nil, await channel.joinAccessToken != token else {
          continue
        }
      default:
        continue
      }
      logger.debug("Updating auth token for channel \(channel.topic)")
      await channel.push(ChannelEvent.accessToken, payload: ["access_token": .string(token)])
    }
  }

  /// Refreshes ``accessTokenRefreshLeeway`` before the token's `exp`, and never sooner than
  /// ``accessTokenRefreshInterval`` from now, which the callback would refuse anyway. A new
  /// token replaces the timer. Without a connection, a callback, or a token with an `exp`, there
  /// is nothing to schedule: the next join or heartbeat refreshes the token instead.
  private func scheduleAccessTokenRefresh() {
    guard options.accessToken != nil, status.isConnected,
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
    guard status.isConnected else { return }
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

  /// Sends a message over the WebSocket, or buffers it until the socket connects.
  func push(_ message: RealtimeMessage) async {
    do {
      await send(.text(try serializer.encodeText(message)))
    } catch {
      logger.error(
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
    logger.error(
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
      logger.error("Failed to send frame: \(error)")
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
    baseURL: URL, apikey: String?, serverLogLevel: RealtimeServerLogLevel?
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

    if let serverLogLevel {
      queryItems.append(URLQueryItem(name: "log_level", value: serverLogLevel.rawValue))
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
