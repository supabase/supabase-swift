//
//  RealtimeClient.swift
//
//
//  Created by Guilherme Souza on 26/12/23.
//

public import Foundation
internal import HTTPTypes
import Helpers
import IssueReporting
import Logging

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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
/// The client is an actor that owns the state of the connection and of every channel. Reads and
/// stream subscriptions, such as ``status`` and ``statusChanges()``, are `async` from outside
/// the actor. A stream is registered by the time its method returns, so it sees every change
/// the next action causes.
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

  /// How long before the token's `exp` the client asks the `accessToken` callback for a new
  /// one. The server closes every channel the moment the token expires.
  static let accessTokenRefreshLeeway: Duration = .seconds(60)
  /// The shortest wait between two `accessToken` callback calls, so a token already inside the
  /// leeway, or a callback that fails, is retried at this pace instead of in a tight loop.
  static let accessTokenRefreshInterval: Duration = .seconds(10)

  /// The random source of ``reconnectBackoff``.
  nonisolated let jitter: @Sendable (ClosedRange<Double>) -> Double

  /// The time since the client was created, on `clock`.
  nonisolated let elapsed: @Sendable () -> Duration
  /// The wall-clock time, advanced by `clock`, so a `TestClock` also drives token expiry.
  nonisolated let now: @Sendable () -> Date

  enum ConnectionState: Equatable {
    /// Idle or stopped. Carries the error when a failure, not the user, stopped the client.
    case disconnected(RealtimeError?)
    /// The transport is opening a socket. Attempt 1 is the user's `connect()`; later attempts
    /// are automatic retries after a drop.
    case connecting(attempt: Int)
    case connected(any WebSocketConnection)
    /// Waiting `retryIn` before attempt `attempt + 1`.
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

  // MARK: Shell state

  /// The protocol state. Only ``apply(_:)`` hands it events.
  ///
  /// Lazy, so its `hasRegisteredChannels` closure is formed on the actor and reads
  /// ``channelStates`` directly.
  lazy var core: RealtimeCore = makeCore()
  var waiters = WaiterTable()
  var timers = TimerTable()
  /// The writer for the current socket.
  var outbox: Outbox?
  /// The current socket, so `deinit` can close it.
  var socket: (any WebSocketConnection)?
  /// Set only while ``disconnect(code:reason:)`` applies its event. The batch keeps the outbox and
  /// the close of the socket it stops here, so the frames still queued are written before the
  /// socket closes. Every other stop drops them.
  var stoppedByDisconnect: StoppedSocket?
  /// Counts socket installs and stops. The reader stamps its inputs with the value it started
  /// with, so a frame from a socket that has since been replaced is dropped.
  var generation = 0
  var reader: Task<Void, Never>?
  /// The connect attempt in flight. Its result carries `id`, so the result of an attempt that
  /// was cancelled or replaced is dropped.
  var connectAttempt: (id: Int, task: Task<Void, Never>)?
  /// The id of the latest connect attempt.
  var lastConnectAttempt = 0
  /// The wait before the next reconnect attempt. Its fire carries `token`, so the fire of a
  /// wait that was cancelled or replaced is dropped.
  var retryTimer: (token: UInt64, task: Task<Void, Never>)?
  /// The wait before the deferred disconnect, stamped as ``retryTimer`` is.
  var idleDisconnectTimer: (token: UInt64, task: Task<Void, Never>)?
  /// The token of the latest retry or idle disconnect timer.
  var lastShellTimerToken: UInt64 = 0
  /// The `accessToken` callback call in flight for fetch `generation`, and the timer that ends
  /// the wait for it after `requestTimeout`. The first of the two to report wins.
  var tokenFetch: (generation: Int, call: Task<Void, Never>, timeout: Task<Void, Never>)?
  /// The callers of ``setAuth(_:)`` that wait for the callback call in flight.
  var tokenFetchWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

  /// The state of every channel this client created and has not removed. A handle with no entry
  /// is spent: ``removeChannel(_:)`` or a server `phx_close` removed it.
  var channelStates: [ChannelID: ChannelState] = [:]
  /// The channel ``channel(_:configure:)`` returns for each topic.
  var liveChannels: [String: ChannelID] = [:]
  /// The last ``ChannelID`` issued.
  var lastChannelID: UInt64 = 0
  /// The published client status.
  let statusFanout = Fanout<RealtimeClientStatus>(retaining: .disconnected(nil))
  /// The published heartbeats. Retains nothing until the first heartbeat, then the latest one.
  let heartbeatFanout = Fanout<HeartbeatEvent>(retaining: nil)
  /// The last stream id issued. Ids only grow, so no two streams share one.
  var lastStreamID: UInt64 = 0

  /// Where every edge of the client hands its input: the socket reader, connect attempts,
  /// timers, token fetches, task cancellations, and app lifecycle changes. One pump task,
  /// started in `init`, applies the inputs on the actor in the order they were yielded.
  nonisolated let inbox: AsyncStream<Input>.Continuation

  #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
    /// Yields the app lifecycle changes into ``inbox`` when
    /// ``RealtimeClientOptions/handleAppLifecycle`` is `true`.
    let lifecycleManager: RealtimeLifecycleManager?
  #endif

  /// The current WebSocket connection status.
  public var status: RealtimeClientStatus {
    statusFanout.current ?? .disconnected(nil)
  }

  /// Every channel this client created and has not removed.
  ///
  /// ``channel(_:configure:)`` adds a channel. ``removeChannel(_:)``, ``removeAllChannels()``,
  /// and a server that closes the channel remove it. The order is not specified.
  public var channels: [RealtimeChannel] {
    channelStates.values.map(\.handle)
  }

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

    let logger = Self.logger(for: options)
    self.url = url
    self.options = options
    self.logger = logger
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

    let (inputs, inbox) = AsyncStream.makeStream(of: Input.self, bufferingPolicy: .unbounded)
    self.inbox = inbox
    #if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
      lifecycleManager = options.handleAppLifecycle ? RealtimeLifecycleManager(inbox: inbox) : nil
    #endif

    // The pump. Not stored: it holds the client weakly, so it never keeps it alive, and it ends
    // when `deinit` finishes the inbox. It still reads the inputs buffered before then.
    Task(priority: .medium) { [weak self] in
      for await input in inputs {
        guard let self else {
          Self.receiveAfterRelease(input)
          continue
        }
        await self.receive(input)
      }
    }
  }

  /// The core, with options read from the client. Its `hasRegisteredChannels` closure reads the
  /// channels this client still has, including those that never subscribed.
  private func makeCore() -> RealtimeCore {
    let reconnectBackoff = reconnectBackoff
    let jitter = jitter
    let coreOptions = RealtimeCore.Options(
      timeout: options.requestTimeout,
      heartbeatInterval: options.heartbeatInterval,
      connectOnSubscribe: options.connectOnSubscribe,
      disconnectOnEmptyChannelsAfter: options.disconnectOnEmptyChannelsAfter,
      hasAccessTokenProvider: options.accessToken != nil,
      accessTokenRefreshInterval: Self.accessTokenRefreshInterval,
      accessTokenRefreshLeeway: Self.accessTokenRefreshLeeway,
      retryDelay: { reconnectBackoff.delay(forAttempt: $0, random: jitter) },
      rejoinDelay: { RealtimeChannel.rejoinBackoff.delay(forAttempt: $0) },
      version: headers[.xClientInfo],
      // Unowned: the core belongs to this client, so it never outlives it.
      hasRegisteredChannels: { [unowned self] in !self.channelStates.isEmpty }
    )
    let initialToken = headers[.authorization]?.split(separator: " ").last.map(String.init)
    return RealtimeCore(options: coreOptions, logger: logger, initialToken: initialToken)
  }

  deinit {
    // No waiter can be parked here: a parked caller runs an isolated method, so it retains the
    // client. The lifecycle manager removes its observers in its own `deinit`, and the fan-outs
    // and channel states end their streams in theirs.
    inbox.finish()
    // Close the live socket: cancelling the tasks alone leaves the underlying WebSocket (and its
    // URLSession) open when a connected client is released without calling `disconnect()`.
    socket?.close(code: .normalClosure, reason: "Client deallocated")
    outbox?.close()
    reader?.cancel()
    connectAttempt?.task.cancel()
    retryTimer?.task.cancel()
    idleDisconnectTimer?.task.cancel()
    tokenFetch?.call.cancel()
    tokenFetch?.timeout.cancel()
    timers.cancelAll()
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
    let id = nextStreamID(channel: nil)
    return statusFanout.subscribe(id, onTermination: onStreamEnd(id))
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
    let id = nextStreamID(channel: nil)
    return heartbeatFanout.subscribe(id, onTermination: onStreamEnd(id))
  }

  /// A new stream id, for a stream of the channel `channel`, or of the client when it is `nil`.
  func nextStreamID(channel: ChannelID?) -> StreamID {
    lastStreamID += 1
    return StreamID(rawValue: lastStreamID, channel: channel)
  }

  /// The `onTermination` of stream `id`: it only yields ``Input/streamEnded(_:)``.
  nonisolated func onStreamEnd(_ id: StreamID) -> @Sendable () -> Void {
    { [inbox] in inbox.yield(.streamEnded(id)) }
  }

  /// Forgets the stream `id`, which its consumer ended. A Postgres stream changes the channel's
  /// join payload, so the core learns of the binding it loses.
  func streamEnded(_ id: StreamID) {
    guard let channel = id.channel else {
      if !statusFanout.remove(id) { heartbeatFanout.remove(id) }
      return
    }
    guard let state = channelStates[channel], state.removeStream(id) else { return }
    apply(.bindingsChanged(channel: channel, snapshot: state.joinSnapshot))
  }

  // MARK: - Connection

  /// Opens the WebSocket connection and suspends until it is established.
  ///
  /// Calling this method when already connected is a no-op, and calling it while a connection
  /// attempt is in progress waits for that attempt. While an automatic reconnect is waiting
  /// out its backoff, this tries at once instead; if that attempt fails, this throws and the
  /// automatic reconnect carries on. If
  /// ``RealtimeClientOptions/connectOnSubscribe`` is `true` (the default), this is called
  /// automatically when a channel is subscribed to.
  ///
  /// ```swift
  /// try await client.connect()
  /// ```
  ///
  /// - Throws: ``RealtimeError`` with kind `.transport` when the socket could not be opened, or
  ///   `CancellationError` when the calling task is cancelled or ``disconnect(code:reason:)``
  ///   interrupts the attempt.
  public func connect() async throws {
    logger.debug("Connecting...")
    do {
      try await wait { .connect(waiter: $0) }
    } catch {
      throw Self.connectionError(error)
    }
  }

  /// Closes the WebSocket connection.
  ///
  /// Cancels pending tasks, fails every push still waiting for a reply with
  /// ``RealtimeError/Kind/notConnected``, and emits ``RealtimeClientStatus/disconnected(_:)``.
  /// Subscribed channels become ``RealtimeChannelStatus/unsubscribed`` and stay registered; the
  /// next ``connect()`` does not join them again, so call ``RealtimeChannel/subscribe()`` on each.
  ///
  /// The frames already queued, such as broadcasts that returned before this call, are still
  /// written before the socket closes. The method returns once the socket is closed; a second call
  /// made while that happens returns at once. The wait
  /// lasts at most ``RealtimeClientOptions/requestTimeout``; after that, or when the calling task
  /// is cancelled, the frames left are dropped.
  ///
  /// - Parameters:
  ///   - code: An optional numeric close code to send to the server.
  ///   - reason: An optional reason string to send to the server.
  public func disconnect(code: Int? = nil, reason: String? = nil) async {
    logger.debug("Closing WebSocket connection")
    // A local, because the existential in `self.clock` is not opened when passed directly.
    let clock = clock
    // Started before the event, so the bound runs from the call.
    let deadline = sleepThenRun(on: clock, after: options.requestTimeout) {}
    defer { deadline.cancel() }
    stoppedByDisconnect = StoppedSocket()
    apply(.disconnectRequested(code: code, reason: reason))
    let stopped = stoppedByDisconnect
    stoppedByDisconnect = nil
    if let outbox = stopped?.outbox {
      await withTaskCancellationHandler {
        await outbox.drain(until: deadline)
      } onCancel: {
        deadline.cancel()
      }
    }
    stopped?.close?()
  }

  /// Records whether the socket is connected as the app enters the background.
  ///
  /// Runs when the inbox delivers ``Input/appBackground``, which ``RealtimeLifecycleManager``
  /// yields when ``RealtimeClientOptions/handleAppLifecycle`` is `true`.
  func handleAppBackground() {
    apply(.appBackground)
  }

  /// Recovers the connection on app foregrounding when the socket was connected before the app
  /// went to the background and has since gone away.
  ///
  /// Runs when the inbox delivers ``Input/appForeground``, which ``RealtimeLifecycleManager``
  /// yields when ``RealtimeClientOptions/handleAppLifecycle`` is `true`.
  func handleAppForeground() {
    apply(.appForeground)
  }

  // MARK: - Channels

  /// Returns an existing channel for the given topic or creates a new one.
  ///
  /// The returned channel's ``RealtimeChannel/topic`` is `topic`; the SDK adds the `realtime:`
  /// prefix the server expects on the WebSocket only. The client keeps one
  /// channel per topic: when a channel with the same topic already exists, it is returned
  /// unchanged. Asking for it with a different configuration reports an issue, because the
  /// configuration is fixed when the channel is created; remove the channel first to change it.
  /// Concurrent calls for the same topic return the same channel.
  ///
  /// `configure` runs on the caller's actor before the call reaches the client, so it can read
  /// the caller's state.
  ///
  /// ```swift
  /// let channel = await client.channel("room:lobby") { config in
  ///   config.broadcast.receiveOwnMessages = true
  /// }
  /// ```
  ///
  /// > Note: This method does not subscribe to the channel. Call ``RealtimeChannel/subscribe()``
  /// > on the returned instance to join the topic. Only the subscribe cancels a disconnect
  /// > scheduled by ``RealtimeClientOptions/disconnectOnEmptyChannelsAfter``.
  ///
  /// - Parameters:
  ///   - topic: The channel topic name, such as `"room:lobby"`.
  ///   - configure: A closure that sets the channel's ``RealtimeChannelConfiguration``: privacy,
  ///     broadcast, presence and Postgres changes options.
  /// - Returns: A ``RealtimeChannel`` bound to this client.
  public nonisolated func channel(
    _ topic: String,
    configure: (inout RealtimeChannelConfiguration) -> Void = { _ in }
  ) async -> RealtimeChannel {
    var configuration = RealtimeChannelConfiguration()
    configure(&configuration)
    return await channel(topic, configuration: configuration)
  }

  /// The live channel for `topic`, or a new one with `configuration` and the next ``ChannelID``.
  func channel(
    _ topic: String, configuration: RealtimeChannelConfiguration
  ) -> RealtimeChannel {
    if let id = liveChannels[topic], let state = channelStates[id] {
      if state.handle.configuration != configuration {
        reportIssue(
          """
          Channel "\(topic)" already exists with a different configuration. The existing channel \
          is returned unchanged; remove it first to change its configuration.
          """
        )
      }
      return state.handle
    }
    lastChannelID += 1
    let id = ChannelID(rawValue: lastChannelID)
    let handle = RealtimeChannel(id: id, topic: topic, configuration: configuration, client: self)
    channelStates[id] = ChannelState(handle: handle)
    liveChannels[topic] = id
    return handle
  }

  /// Unsubscribes from and removes a channel, ending every stream opened on it.
  ///
  /// The channel is removed before the first suspension point: its streams end, and its
  /// actions throw ``RealtimeError/Kind-swift.struct/channelRemoved``, even when the calling
  /// task is cancelled. Its ``RealtimeChannel/status`` reads
  /// ``RealtimeChannelStatus/unsubscribed``, its ``RealtimeChannel/presenceState`` is empty, and
  /// a stream opened on it later ends at once. A subscribed or joining channel then leaves the
  /// topic, and the method returns when the leave ends. A new channel for the same topic, from
  /// ``channel(_:configure:)``, can subscribe meanwhile. After removal, if no channels remain,
  /// the client disconnects (or schedules a deferred disconnect based on
  /// ``RealtimeClientOptions/disconnectOnEmptyChannelsAfter``).
  ///
  /// Removing a channel that was already removed, or that another client created, does nothing.
  ///
  /// - Parameter channel: The channel to remove.
  public func removeChannel(_ channel: RealtimeChannel) async {
    guard let state = state(of: channel) else { return }
    channelStates[channel.id] = nil
    if liveChannels[channel.topic] == channel.id {
      liveChannels[channel.topic] = nil
    }
    state.finishAll()
    try? await wait(evenIfCancelled: true) { [id = channel.id] in
      .removeChannel(channel: id, waiter: $0)
    }
  }

  /// Unsubscribes from and removes all channels, then disconnects immediately.
  ///
  /// Unlike ``removeChannel(_:)``, this method ignores
  /// ``RealtimeClientOptions/disconnectOnEmptyChannelsAfter`` and
  /// disconnects the WebSocket right away.
  public func removeAllChannels() async {
    let removed = channels
    await withTaskGroup(of: Void.self) { group in
      for channel in removed {
        group.addTask { await self.removeChannel(channel) }
      }
    }
    // `disconnect()` also cancels a pending idle disconnect.
    await disconnect()
  }

  // MARK: - Authentication

  /// The token channels join with.
  var accessToken: String? { core.tokens.token }

  /// The token an HTTP request sends, refreshed from the `accessToken` callback first unless it
  /// was called within ``accessTokenRefreshInterval``. A call in flight is waited for: the
  /// stored token may be expired, or the key from the `Authorization` header.
  func currentAccessToken() async -> String? {
    await refreshAccessToken()
    return core.tokens.token
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
    apply(.setAuth(token: token))
  }

  /// Asks the `accessToken` callback for a token, then waits for the call in flight, if any. A
  /// cancelled caller stops waiting at once; the call goes on.
  func refreshAccessToken() async {
    apply(.setAuth(token: nil))
    guard core.tokenFetchInFlight else { return }
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if core.tokenFetchInFlight, !Task.isCancelled {
          tokenFetchWaiters[id] = continuation
        } else {
          continuation.resume()
        }
      }
    } onCancel: { [inbox] in
      inbox.yield(.tokenWaitCancelled(id))
    }
  }

  /// Reads the time since this call on `clock`. A generic function opens the existential, so
  /// two instants of the same concrete clock can be subtracted.
  private static func elapsedTime(on clock: some Clock<Duration>) -> @Sendable () -> Duration {
    let start = clock.now
    return { start.duration(to: clock.now) }
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
