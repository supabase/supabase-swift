//
//  Realtime.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import Helpers
import IssueReporting

/// The wire form of an outgoing push, consumed by ``Realtime/_push(topic:_:_:ref:joinRef:lazyConnect:ack:)``.
///
/// `text` is a JSON text frame (join, leave, presence, access_token, heartbeat); the two
/// `broadcast*` cases are Phoenix binary broadcast frames (kind `0x03`) carrying either a
/// JSON envelope or raw bytes.
enum PushBody: Sendable {
  case text(JSONObject)
  case broadcastJSON(JSONObject)
  case broadcastData(Data)
}

/// Whether an outgoing push awaits a `phx_reply`.
///
/// `require` suspends until the matching reply arrives or `timeout` elapses, throwing
/// `error` on timeout. Best-effort sends (e.g. access_token) use `none` and/or a
/// `try?` at the call site.
enum AckPolicy: Sendable {
  case none
  case require(timeout: Duration, error: RealtimeError)
}

/// The top-level Realtime client. Manages the WebSocket connection, channel registry,
/// and distributes `ConnectionStatus` events to subscribers.
///
/// Create exactly one `Realtime` per Supabase project. Obtain channels via
/// `channel(_:configure:)`, then call `connect()` to establish the WebSocket.
///
/// ## Connection lifecycle
/// `connect()` is idempotent and coalescing — concurrent callers share the single
/// in-flight connect task. Once connected, repeated `connect()` calls are no-ops.
///
/// ## Transport
/// Defaults to `URLSessionTransport()` (production WebSocket). Pass a custom
/// transport in tests via the `InMemoryTransport` test double.
public actor Realtime {
  // MARK: - Public typealiases

  /// A closure that asynchronously vends a fresh access token.
  public typealias AccessTokenProvider = @Sendable () async throws -> String

  // MARK: - Stored properties

  let url: URL
  let apiKey: String
  let accessTokenProvider: AccessTokenProvider?
  let configuration: Configuration

  /// The logger extracted from `configuration` at init time.
  /// Stored as `nonisolated let` so `log(...)` can be called from synchronous
  /// actor-isolated contexts (including from Channel's `log` helper) without an `await`.
  nonisolated let logger: (any RealtimeLogger)?

  private let transport: any RealtimeTransport

  /// HTTP client for broadcast API calls. Uses the HTTP-scheme version of `url`.
  let httpClient: _HTTPClient

  /// Active connection returned by the transport after `connect()`.
  private var connection: (any RealtimeConnection)?

  /// In-flight connect task — used for coalescing concurrent `connect()` callers
  /// and for idempotency once connected.
  private var connectTask: Task<Void, any Error>?

  /// Background task that consumes `connection.frames` and routes messages.
  // intra-module: read/written by Realtime+FrameRouting.swift (same module, separate file).
  // Swift `private` does not cross file boundaries; `internal` is the tightest we can use here.
  var routingTask: Task<Void, Never>?

  /// Background task that sends periodic heartbeat frames and checks replies.
  var heartbeatTask: Task<Void, Never>?

  /// When `true`, a reconnection loop is currently running.
  /// Set to `true` by `runReconnectionLoop`, reset when it exits.
  var isReconnecting: Bool = false

  /// The running reconnection loop task. Stored so it can be cancelled on intentional disconnect.
  var reconnectTask: Task<Void, Never>?

  /// When `true`, connection loss should NOT trigger auto-reconnect.
  /// Set by disconnect() in Task 14.
  var intentionalDisconnect: Bool = false

  /// When `true`, the socket was closed by the idle-close timer (no live channels for
  /// `disconnectOnEmptyChannelsAfter`). The idle close is intentional and must NOT trigger
  /// the auto-reconnect loop, but it IS recoverable: the next `connect()` (from a new
  /// `subscribe()`) clears this flag and re-opens the socket.
  ///
  /// Distinct from `intentionalDisconnect` (which is set by an explicit `disconnect()` call
  /// and represents a permanent user intent). Using a separate flag preserves the semantics
  /// of both: `intentionalDisconnect` keeps existing behaviour, and `idleClosed` adds the
  /// new "idle, but reconnectable" state.
  var idleClosed: Bool = false

  /// The pending idle-close timer task. Armed when the last live channel leaves (live count
  /// transitions to 0). Cancelled when a channel joins (live count rises above 0) or when
  /// `disconnect()` is called (to avoid double teardown).
  ///
  /// `nonisolated` call sites (`_markJoined` / `_markLeft`) arm / cancel via actor-isolated
  /// async tasks spawned from those nonisolated methods — see their implementations.
  var idleCloseTask: Task<Void, Never>?

  /// Registry tracking in-flight pushes awaiting a `phx_reply`.
  let inflightPushRegistry = InflightPushRegistry()

  /// The lifecycle event source injected at init time. `nonisolated let` so it can be
  /// stored during the actor initializer before isolation is established.
  /// `nil` when `lifecycle == .manual` or on unsupported platforms.
  nonisolated let lifecycleSource: (any LifecycleEventSource)?

  /// The active lifecycle observer. Created lazily on the first `connect()` call and
  /// cancelled on `disconnect()`.
  private var lifecycleObserverHandle: LifecycleObserver?

  /// Monotonic ref generator shared across all protocol frames.
  nonisolated let refGenerator = RefGenerator()

  /// Tracks topics of channels that have successfully joined but have not yet been explicitly left.
  ///
  /// ## Design: nonisolated + LockIsolated (Task 32)
  /// Stored as `nonisolated let` backed by a `LockIsolated` value so the synchronous `deinit`
  /// can read it without an actor hop (no `await`, no Swift 6.2 isolated deinit required).
  ///
  /// Topics are added by `_markJoined(_:)` when a channel transitions to `.joined`, and removed
  /// by `_markLeft(_:)` when the channel is explicitly left or terminally evicted.
  ///
  /// ## disconnect() does NOT clear this set
  /// `disconnect()` is a transport-level operation; it does NOT call `leave()` on any channel
  /// (Decision 29). A channel that was joined but never left remains in `joinedTopics` through
  /// a disconnect so the deinit warning fires when the developer forgets to call `leave()`.
  nonisolated let joinedTopics = LockIsolated<Set<String>>([])

  /// Serializer for encoding/decoding Phoenix protocol frames.
  nonisolated let serializer = PhoenixSerializer()

  /// Topic → Channel registry. First-call-wins (Decision 33).
  var channels: [String: Channel] = [:]

  /// Explicitly-set access token, stored by `updateToken(_:)`.
  ///
  /// ## Token precedence (spec §6.3)
  /// `accessTokenForJoin()` checks this field first. When non-nil it is returned
  /// directly, bypassing the `accessTokenProvider` closure. This allows callers to
  /// push a concrete token (e.g. after a token refresh) without replacing the provider.
  ///
  /// Precedence order (highest → lowest):
  ///   1. `_overrideToken` — set by `updateToken(_:)`
  ///   2. `accessTokenProvider` — closure supplied at init
  ///   3. `nil` (anonymous / public channels)
  var _overrideToken: String?

  /// Current connection status.
  private var currentStatus: ConnectionStatus = ConnectionStatus(
    state: .idle,
    since: Date(),
    latency: nil
  )

  /// Broadcast list of `status` stream continuations.
  /// `LockIsolated` because continuations are yielded from actor-isolated context,
  /// so a plain array is fine — but we use a value wrapper to allow capture in closures.
  private var statusContinuations: [UUID: AsyncStream<ConnectionStatus>.Continuation] = [:]

  // MARK: - Initializer

  /// Creates a `Realtime` client.
  ///
  /// - Parameters:
  ///   - url: The Realtime endpoint base URL (e.g. `wss://project.supabase.co/realtime/v1`).
  ///   - apiKey: The project's anon (or service-role) key, sent as `apikey` query param.
  ///   - accessToken: Optional closure that vends a fresh JWT for authenticated operations.
  ///     Used for channel join, **not** for the WebSocket handshake (spec §6.3).
  ///   - configuration: Tuning knobs — heartbeat, reconnection, etc. Defaults to `.default`.
  ///   - transport: The transport to use for the WebSocket connection.
  ///     Defaults to `URLSessionTransport()` (production). Pass `InMemoryTransport`
  ///     in tests.
  public init(
    url: URL,
    apiKey: String,
    accessToken: AccessTokenProvider? = nil,
    configuration: Configuration = .default,
    transport: any RealtimeTransport = URLSessionTransport(),
    urlSession: URLSession = .shared
  ) {
    self.init(
      url: url,
      apiKey: apiKey,
      accessToken: accessToken,
      configuration: configuration,
      transport: transport,
      urlSession: urlSession,
      lifecycleSource: nil
    )
  }

  /// Designated initializer. The `lifecycleSource` parameter is `internal` so tests can
  /// inject a `TestLifecycleEventSource` without exposing it in the public API.
  init(
    url: URL,
    apiKey: String,
    accessToken: AccessTokenProvider? = nil,
    configuration: Configuration = .default,
    transport: any RealtimeTransport = URLSessionTransport(),
    urlSession: URLSession = .shared,
    lifecycleSource: (any LifecycleEventSource)?
  ) {
    self.url = url
    self.apiKey = apiKey
    self.accessTokenProvider = accessToken
    self.configuration = configuration
    self.logger = configuration.logger
    self.transport = transport

    // Build the HTTP base URL from the WebSocket URL by converting the scheme.
    // wss → https, ws → http. The path prefix (/realtime/v1) is preserved.
    let httpBaseURL = Self._httpBaseURL(from: url)

    // Build the _HTTPClient. Token injection is handled at call time via actor isolation,
    // not via the tokenProvider closure, because we need access to the actor-isolated
    // _overrideToken at the time of each call.
    self.httpClient = _HTTPClient(host: httpBaseURL, session: urlSession)

    // Resolve the effective lifecycle source:
    // - Use the injected source if provided (test overrides).
    // - Otherwise, when lifecycle == .automatic, create the platform NotificationCenter source.
    // - .manual (or unsupported platform) → no source, no observation.
    if let injected = lifecycleSource {
      self.lifecycleSource = injected
    } else {
      switch configuration.lifecycle {
      case .automatic:
        #if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
          self.lifecycleSource = NotificationCenterLifecycleEventSource()
        #else
          self.lifecycleSource = nil
        #endif
      case .manual:
        self.lifecycleSource = nil
      }
    }
    // The lifecycle observer is started lazily in connect() to avoid capturing
    // `self` before the actor is fully initialized.
  }

  /// Converts a WebSocket URL to its HTTP equivalent for use with ``_HTTPClient``.
  ///
  /// - `wss://` → `https://`
  /// - `ws://` → `http://`
  /// - Other schemes are left unchanged.
  private static func _httpBaseURL(from wsURL: URL) -> URL {
    var components = URLComponents(url: wsURL, resolvingAgainstBaseURL: false) ?? URLComponents()
    switch components.scheme {
    case "wss": components.scheme = "https"
    case "ws": components.scheme = "http"
    default: break
    }
    return components.url ?? wsURL
  }

  // MARK: - Channel registry

  /// Returns an existing channel for `topic`, or creates a new one applying `configure`.
  ///
  /// **First-call-wins**: if a channel for `topic` already exists, the `configure` closure
  /// is ignored and a debug warning is emitted (Decision 33). The returned channel's
  /// `options` reflect the effective (first-call) options.
  ///
  /// - Parameters:
  ///   - topic: The Phoenix topic string (e.g. `"realtime:public:messages"`).
  ///   - configure: Closure applied to `ChannelOptions` before the channel is created.
  ///     Only called once — on first creation.
  /// - Returns: The `Channel` for this topic (created or pre-existing).
  public func channel(
    _ topic: String,
    configure: (inout ChannelOptions) -> Void = { _ in }
  ) -> Channel {
    // Prepend the "realtime:" namespace once. Guard against double-prefix if the caller
    // already passes the fully-qualified form (e.g. "realtime:room:1").
    let fullTopic = topic.hasPrefix("realtime:") ? topic : "realtime:\(topic)"

    if let existing = channels[fullTopic] {
      // Decision 33: first-call-wins — warn only if the caller requested different options.
      var requested = ChannelOptions()
      configure(&requested)
      if requested != existing.options {
        reportIssue(
          "Realtime.channel(\"\(topic)\") called more than once with different options. "
            + "The options from the first call are in effect. "
            + "To change options, deinit the previous channel first."
        )
      }
      return existing
    }

    var options = ChannelOptions()
    configure(&options)
    let ch = Channel(topic: fullTopic, options: options, realtime: self)
    channels[fullTopic] = ch
    return ch
  }

  // MARK: - Connect

  // MARK: - Disconnect

  /// Closes the socket and awaits close completion.
  ///
  /// Does NOT evict the channel cache or call leave() on any channel (Decision 29).
  /// The reconnection policy does NOT auto-reopen after a manual disconnect; the
  /// next `connect()` starts a fresh session.
  ///
  /// - Note: Channels retain their `.joined` state across a manual disconnect — this
  ///   is by design, so a subsequent `connect()` transparently re-joins them. Call
  ///   ``Channel/leave()`` first if you want a channel to settle to `.closed`.
  ///
  /// Idempotent: if already disconnected, this is a no-op.
  public func disconnect() async {
    // Guard: if there is no active connection AND no reconnect in progress, nothing to do.
    // We still set intentionalDisconnect=true to block any in-flight handleConnectionLost.
    log(.info, .connection, "Disconnecting from Realtime server")
    intentionalDisconnect = true

    // Cancel any pending idle-close timer so there is no double teardown.
    idleCloseTask?.cancel()
    idleCloseTask = nil

    // Cancel the lifecycle observer so foreground events no longer trigger reconnect.
    lifecycleObserverHandle?.cancel()
    lifecycleObserverHandle = nil

    // Cancel a running reconnection loop if any.
    reconnectTask?.cancel()
    reconnectTask = nil

    // Cancel background tasks.
    heartbeatTask?.cancel()
    heartbeatTask = nil
    routingTask?.cancel()
    routingTask = nil

    // Fail all in-flight pushes so callers don't hang.
    await inflightPushRegistry.failAll(.disconnected)

    // Close and clear the active connection (if any).
    if let conn = connection {
      connection = nil
      await conn.close(code: 1000, reason: "client disconnected")
    }

    // Transition to closed state.
    transition(to: .closed(.clientDisconnected))
  }

  // MARK: - App lifecycle foreground handler

  /// Called by `LifecycleObserver` when the app returns to the foreground.
  ///
  /// Reconnects if all of the following are true:
  /// - `intentionalDisconnect` is false (the user did not call `disconnect()`).
  /// - The socket is not currently connected.
  ///
  /// If the connection is already live, this is a no-op.
  func handleAppForeground() async {
    // Do nothing if the caller explicitly disconnected.
    guard !intentionalDisconnect else { return }

    // Already connected — no-op.
    if case .connected = currentStatus.state { return }

    // Already reconnecting — no-op (the running loop will recover).
    if isReconnecting { return }

    // Trigger a fresh connect attempt (the same path as connect(), which clears
    // intentionalDisconnect and coalesces concurrent callers).
    try? await connect()
  }

  // MARK: - Connect

  /// Establishes the WebSocket connection to the Realtime server.
  ///
  /// Idempotent: if already connected or connecting, this call joins the in-flight task
  /// (coalescing) without triggering a second `transport.connect`. On success the
  /// `status` stream emits `.connecting(attempt: 1)` then `.connected`.
  ///
  /// The WebSocket handshake uses the literal `apiKey`, never the `accessTokenProvider`
  /// (spec §6.3 "On connect()").
  ///
  /// - Throws: `RealtimeError.transportFailure` if the underlying transport fails.
  public func connect() async throws(RealtimeError) {
    // Clear the intentional-disconnect flag so reconnection works for the new session.
    intentionalDisconnect = false
    // Clear the idle-closed flag so a subscribe() after an idle close re-opens the socket.
    idleClosed = false
    // Cancel any pending idle-close timer (it would be stale after a new connect).
    idleCloseTask?.cancel()
    idleCloseTask = nil

    // Start the lifecycle observer lazily (idempotent — skipped if already running).
    _startLifecycleObserverIfNeeded()

    // Already connected — no-op.
    if case .connected = currentStatus.state {
      return
    }

    // Coalesce concurrent callers onto the existing in-flight task.
    if let existing = connectTask {
      do {
        try await existing.value
      } catch {
        throw .transportFailure(underlying: error)
      }
      return
    }

    // Build and store the connect task.
    let task = Task<Void, any Error> {
      try await self._performConnect()
    }
    connectTask = task

    do {
      try await task.value
      connectTask = nil
    } catch {
      connectTask = nil
      throw RealtimeError.transportFailure(underlying: error)
    }
  }

  // MARK: - Status stream

  /// Returns a fresh `AsyncStream<ConnectionStatus>` seeded with the current status.
  ///
  /// Each call to `status` mints an independent stream. Callers should iterate it to
  /// receive future transitions. The stream completes only when the continuation is
  /// explicitly cancelled (e.g. task cancellation).
  public var status: AsyncStream<ConnectionStatus> {
    let id = UUID()
    let current = currentStatus
    let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
    continuation.yield(current)
    statusContinuations[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { [weak self] in await self?.removeStatusContinuation(id: id) }
    }
    return stream
  }

  // MARK: - Private helpers

  private func removeStatusContinuation(id: UUID) {
    statusContinuations.removeValue(forKey: id)
  }

  func transition(to state: ConnectionStatus.State, latency: Duration? = nil) {
    currentStatus = ConnectionStatus(state: state, since: Date(), latency: latency)
    for continuation in statusContinuations.values {
      continuation.yield(currentStatus)
    }
  }

  /// Signals connecting, opens the transport, stores the connection, signals connected,
  /// and starts the connection tasks.
  private func _performConnect() async throws {
    // Signal connecting.
    log(.info, .connection, "Connecting to Realtime server")
    transition(to: .connecting(attempt: 1))

    // Open the transport (shared helper also used during reconnection).
    let conn = try await _openConnection()
    connection = conn

    // Signal connected.
    log(.info, .connection, "Connected to Realtime server")
    transition(to: .connected)

    // Start the background frame routing and heartbeat loops bound to this connection.
    startConnectionTasks(connection: conn)
  }

  // MARK: - Connection tasks

  /// Starts (or restarts) the frame routing task and heartbeat loop for `connection`.
  ///
  /// Call this after every successful connect — both initial and after a reconnect.
  /// Cancels any pre-existing tasks first so they are never duplicated.
  func startConnectionTasks(connection: any RealtimeConnection) {
    startFrameRouting(connection: connection)
    startHeartbeat()
  }

  // MARK: - Heartbeat

  /// Starts the heartbeat loop and stores the task handle so it can be cancelled.
  private func startHeartbeat() {
    heartbeatTask?.cancel()
    let heartbeater = Heartbeater(
      heartbeat: configuration.heartbeat,
      clock: configuration.clock,
      beat: { [weak self] in try await self?._sendHeartbeat() },
      onConnectionLost: { [weak self] error in
        await self?.handleConnectionLost(error)
      }
    )
    heartbeatTask = heartbeater.start()
  }

  /// Sends one `[null, ref, "phoenix", "heartbeat", {}]` frame on the current connection and
  /// awaits its reply, updating `ConnectionStatus.latency` with the measured round-trip.
  ///
  /// Routes through ``_push`` with `lazyConnect: false`: a dead socket must surface as a
  /// `.disconnected`/timeout (→ `onConnectionLost`) rather than trigger a reconnect. Throws
  /// if the send fails or the reply times out, which the heartbeat loop maps to connection loss.
  func _sendHeartbeat() async throws(RealtimeError) {
    // Wall clock for round-trip measurement; scheduling/timeout uses `configuration.clock`.
    let wallClock = ContinuousClock()
    let sentAt = wallClock.now
    _ = try await _push(
      topic: "phoenix", .heartbeat, .text([:]),
      joinRef: nil, lazyConnect: false,
      ack: .require(timeout: configuration.heartbeat, error: .disconnected)
    )
    updateLatency(sentAt.duration(to: wallClock.now))
  }

  /// Updates `currentStatus.latency` in-place while preserving the current state.
  private func updateLatency(_ latency: Duration) {
    currentStatus = ConnectionStatus(
      state: currentStatus.state,
      since: currentStatus.since,
      latency: latency
    )
    for continuation in statusContinuations.values {
      continuation.yield(currentStatus)
    }
    // Emit heartbeat RTT metric as a log event (spec §10 metrics-as-logs).
    log(
      .debug, .connection, "Heartbeat round-trip complete",
      metadata: ["heartbeat.rtt_ms": "\(latency.inMilliseconds)"]
    )
  }

  // MARK: - Connection loss

  /// Connection-loss handler with automatic reconnection.
  ///
  /// When `intentionalDisconnect` is false (the default), this drives the reconnection
  /// loop: it consults `configuration.reconnection.nextDelay`, sleeps on
  /// `configuration.clock`, and retries `transport.connect` until success or the
  /// policy returns `nil` (give up).
  ///
  /// Idempotency: re-entry is prevented by the `connection == nil` guard at the top of
  /// this function. The guard atomically claims and clears the connection reference before
  /// any suspension point, so a concurrent or re-entrant call (e.g. both the frame-routing
  /// stream and the heartbeat firing almost simultaneously) will see `connection == nil`
  /// and return immediately, preventing overlapping cleanup or reconnection loops.
  ///
  /// `isReconnecting` is reserved for Task 14 (disconnect()/state introspection) and is
  /// NOT the idempotency mechanism.
  func handleConnectionLost(_ error: RealtimeError) async {
    // Atomically claim and clear the connection reference before any suspension point.
    // This is the single-ownership guard: any concurrent or re-entrant call will see
    // connection == nil and return immediately, preventing overlapping cleanup or
    // reconnection loops.
    guard let lostConnection = connection else { return }
    connection = nil

    // Cancel background tasks.
    heartbeatTask?.cancel()
    heartbeatTask = nil
    routingTask?.cancel()
    routingTask = nil

    // Fail all pending pushes so callers don't hang indefinitely.
    await inflightPushRegistry.failAll(error)

    // Close the connection we captured above.
    await lostConnection.close(code: 1001, reason: "connection lost")

    // If the disconnect was intentional (set by disconnect()), stay closed.
    // Do NOT overwrite .closed(.clientDisconnected) and do NOT trigger reconnection.
    if intentionalDisconnect {
      return
    }

    // If the socket was closed by the idle-close timer, suppress reconnection.
    // The idle close already transitioned status to .idle and cleared the connection.
    // A future connect() call (from subscribe()) will re-open the socket.
    if idleClosed {
      return
    }

    // Spawn reconnection as an unstructured Task so it runs independently of the routing
    // task (which may be the caller and may be cancelled). The reconnection loop must NOT
    // inherit cancellation from the routing task — it needs to outlive it.
    reconnectTask = Task {
      await runReconnectionLoop(initialError: error)
    }
  }

  /// Reconnection loop. Runs in its own unstructured Task so it is not affected by the
  /// cancellation of the routing task that detected the connection loss.
  private func runReconnectionLoop(initialError: RealtimeError) async {
    isReconnecting = true
    // Clear reconnectTask on ALL exit paths (success, give-up, cancellation) so Task 14
    // can reliably check `reconnectTask == nil` to determine whether reconnection is in progress.
    defer {
      isReconnecting = false
      reconnectTask = nil
    }

    var attempt = 1
    var lastError: any Error & Sendable = initialError

    while true {
      // Consult the policy for the delay before this attempt.
      guard let delay = configuration.reconnection.nextDelay(attempt, lastError) else {
        // Policy says give up: fail all (in case new pushes arrived), go to closed.
        await inflightPushRegistry.failAll(initialError)
        transition(to: .closed(.transportFailure))
        // Terminate all eligible channels so their streams throw/finish (Task 29).
        await terminateChannelsOnGiveUp()
        return
      }

      // Signal reconnecting.
      log(
        .info, .connection, "Reconnecting to Realtime server",
        metadata: ["reconnect.attempt": "\(attempt)"]
      )
      transition(to: .reconnecting(attempt: attempt, lastError: lastError))

      // Wait the backoff delay on the configured clock.
      do {
        try await configuration.clock.sleep(for: delay)
      } catch {
        // CancellationError: actor is being torn down — exit silently.
        return
      }

      // Attempt to reconnect.
      do {
        let conn = try await _openConnection()
        // Successfully reconnected: bind fresh tasks to the new connection.
        // (reconnectTask is cleared by the defer at the top of this function.)
        connection = conn
        log(.info, .connection, "Reconnected to Realtime server")
        transition(to: .connected)
        startConnectionTasks(connection: conn)
        // Re-join eligible channels (Task 29).
        await rejoinEligibleChannels()
        return
      } catch {
        // Reconnect attempt failed — record and loop.
        log(.warn, .connection, "Reconnect attempt \(attempt) failed: \(error)")
        lastError = error
        attempt += 1
      }
    }
  }

  // MARK: - Channel rejoin on reconnect (Task 29)

  /// Re-joins all channels that were previously joined and not explicitly left by the user.
  ///
  /// Called after every successful reconnect. Channels with `shouldRejoin == true` are
  /// eligible (they were transport-dropped, not user-left). Each channel's existing streams
  /// (messages, broadcasts, postgres, presence) stay open across the gap — only the
  /// `phx_join` handshake is re-sent.
  ///
  /// Channels are re-joined concurrently so a slow join on one topic does not block others.
  private func rejoinEligibleChannels() async {
    // Snapshot the full channel list. We check eligibility per-channel (actor hop).
    let allChannels = Array(channels.values)
    guard !allChannels.isEmpty else { return }

    // Re-join concurrently. Each channel's rejoin() checks its own shouldRejoin flag
    // at the start and is a no-op if not eligible.
    await withTaskGroup(of: Void.self) { group in
      for channel in allChannels {
        group.addTask {
          // Only rejoin if this channel was previously joined (actor-isolated read).
          guard await channel.shouldRejoin else { return }
          await channel.rejoin()
        }
      }
    }
  }

  /// Terminates all eligible channels when the reconnection policy gives up.
  ///
  /// Called from the give-up path in `runReconnectionLoop`. For each channel with
  /// `shouldRejoin == true`, transitions it to `.closed(.transportFailure)`, which
  /// cascades stream terminations via the existing `transition(to:)` logic.
  /// Those channels are then evicted from the registry.
  private func terminateChannelsOnGiveUp() async {
    // Snapshot topic+channel pairs. We check eligibility per-channel (actor hop).
    let snapshot = Array(channels)
    var toEvict: [String] = []
    for (topic, channel) in snapshot {
      if await channel.shouldRejoin {
        await channel.transition(to: .closed(.transportFailure))
        toEvict.append(topic)
      }
    }
    for topic in toEvict {
      channels.removeValue(forKey: topic)
    }
  }

  /// Builds the connect URL and headers, then calls transport.connect.
  /// Used by both initial connect and reconnect.
  private func _openConnection() async throws -> any RealtimeConnection {
    var components =
      URLComponents(url: url, resolvingAgainstBaseURL: false)
      ?? URLComponents()
    // Append the Phoenix WebSocket endpoint path component if not already present.
    // Supabase Realtime routes WebSocket upgrades at `.../websocket`.
    // Guard against double-append in case the caller already included `/websocket`.
    let existingPath = components.path
    if !existingPath.hasSuffix("/websocket") {
      components.path =
        existingPath.hasSuffix("/")
        ? existingPath + "websocket"
        : existingPath + "/websocket"
    }
    var queryItems = components.queryItems ?? []
    // Remove any pre-existing apikey / vsn entries to avoid duplication.
    queryItems.removeAll { $0.name == "apikey" || $0.name == "vsn" }
    queryItems.append(URLQueryItem(name: "apikey", value: apiKey))
    // Send vsn so the backend can negotiate the binary serializer format.
    // Configuration.protocolVersion carries the negotiated version (default: v2 = "2.0.0").
    queryItems.append(
      URLQueryItem(name: "vsn", value: configuration.protocolVersion.rawValue)
    )
    components.queryItems = queryItems
    guard let connectURL = components.url else {
      throw RealtimeError.transportFailure(underlying: URLError(.badURL))
    }

    var headers = configuration.headers
    headers["x-api-key"] = apiKey

    return try await transport.connect(to: connectURL, headers: headers)
  }

  // MARK: - Leaked-channel deinit warning (Task 32)

  deinit {
    // Synchronous deinit: read joinedTopics WITHOUT an actor hop.
    // `joinedTopics` is a nonisolated LockIsolated — safe to read from a synchronous deinit
    // on any thread without isolation (no `await`, no Swift 6.2 isolated deinit).
    let leaked = joinedTopics.value
    guard !leaked.isEmpty else { return }

    let sorted = leaked.sorted()
    let list = sorted.joined(separator: ", ")
    reportIssue(
      "Realtime deinited with \(leaked.count) channel(s) still joined and never left: [\(list)]. "
        + "Call channel.leave() before releasing the Realtime instance to avoid server-side "
        + "resource leaks. In release builds the server will close the channels after its "
        + "heartbeat timeout."
    )
  }

  // MARK: - Joined-topic registry (nonisolated — readable from synchronous deinit)

  /// Records that `topic` has successfully joined. Called by `Channel` after a successful
  /// `phx_join` handshake (transition to `.joined`).
  ///
  /// Declared `nonisolated` so `Channel` can call it synchronously from its actor-isolated
  /// `transition(to:)` without an `await`, and so `deinit` can read the same `LockIsolated`
  /// without an actor hop.
  ///
  /// ## Idle-close interaction
  /// When the live-channel count rises above zero (i.e. the first channel joins), any pending
  /// idle-close timer is cancelled. The actor-isolated cancellation is performed by spawning
  /// an unstructured `Task` that hops back onto the actor. This is safe because:
  /// - The task only writes actor-isolated state (`idleCloseTask`).
  /// - Any ordering race (timer fires just before cancel) is benign: the timer performs its
  ///   own final liveness check before closing, so a concurrent join wins.
  nonisolated func _markJoined(_ topic: String) {
    joinedTopics.withValue { _ = $0.insert(topic) }
    // Cancel any pending idle-close timer: live count is now > 0.
    Task { await _cancelIdleCloseTimer() }
  }

  /// Records that `topic` has been left or terminally evicted. Called by `Channel` when
  /// it transitions to a terminal state (`.closed(.userRequested)` via `leave()`, or when
  /// the reconnection policy gives up and the channel is evicted).
  ///
  /// Declared `nonisolated` for the same reasons as `_markJoined`.
  ///
  /// ## Idle-close interaction
  /// When the live-channel count drops to zero (the last channel left), the idle-close timer
  /// is armed. The actor-isolated arming is performed by spawning an unstructured `Task`.
  nonisolated func _markLeft(_ topic: String) {
    joinedTopics.withValue { _ = $0.remove(topic) }
    // Arm the idle-close timer if live count just reached zero.
    // The actual liveness check (is socket open? is count still 0?) happens inside the actor.
    Task { await _armIdleCloseTimerIfNeeded() }
  }

  // MARK: - Idle-close timer (Decision 39)

  /// Arms the idle-close timer if the socket is connected and no channels are live.
  ///
  /// Called from `_markLeft` (via an unstructured Task) whenever a channel leaves.
  /// The timer fires after `configuration.disconnectOnEmptyChannelsAfter`; if the live
  /// count is still zero and the socket is still open at that point, the socket is closed
  /// with status `.idle` (NOT `.closed(.clientDisconnected)` — this is an optimization).
  ///
  /// ## Re-arm behaviour
  /// Each call supersedes the previous timer. This handles rapid leave/join/leave cycles
  /// correctly: only the last arming matters. Cancellation via `_cancelIdleCloseTimer`
  /// prevents the close when a new channel joins before the timer fires.
  private func _armIdleCloseTimerIfNeeded() {
    // Only arm when the socket is connected and no live channels remain.
    guard connection != nil else { return }
    guard joinedTopics.value.isEmpty else { return }

    // Cancel any previously-armed timer (supersede it).
    idleCloseTask?.cancel()

    let idleDuration = configuration.disconnectOnEmptyChannelsAfter
    let clock = configuration.clock

    idleCloseTask = Task {
      do {
        try await clock.sleep(for: idleDuration)
      } catch {
        // Cancelled (a channel joined or disconnect() was called) — do nothing.
        return
      }

      // Re-check conditions after the sleep: connection still open, no live channels.
      guard connection != nil else { return }
      guard joinedTopics.value.isEmpty else { return }

      // Perform the idle close.
      await _performIdleClose()
    }
  }

  /// Cancels the pending idle-close timer. Called from `_markJoined` when a channel joins.
  private func _cancelIdleCloseTimer() {
    idleCloseTask?.cancel()
    idleCloseTask = nil
  }

  /// Closes the socket as an idle-optimization (no live channels for the configured duration).
  ///
  /// - Status transitions to `.idle` (NOT `.closed(.clientDisconnected)`).
  /// - Sets `idleClosed = true` to suppress the auto-reconnect loop in `handleConnectionLost`.
  /// - Does NOT set `intentionalDisconnect` — the next `connect()` clears `idleClosed` and
  ///   fully re-opens the socket.
  private func _performIdleClose() async {
    guard let conn = connection else { return }
    connection = nil

    log(
      .info, .connection,
      "Idle-closing socket (no live channels for disconnectOnEmptyChannelsAfter)")

    // Mark as idle-closed so handleConnectionLost (triggered by the frame stream ending)
    // does NOT start the auto-reconnect loop.
    idleClosed = true
    idleCloseTask = nil

    // Cancel background tasks.
    heartbeatTask?.cancel()
    heartbeatTask = nil
    routingTask?.cancel()
    routingTask = nil

    // Fail in-flight pushes so callers don't hang.
    await inflightPushRegistry.failAll(.disconnected)

    // Close the underlying connection.
    await conn.close(code: 1000, reason: "idle close")

    // Transition to .idle (recoverable — next connect() re-opens the socket).
    transition(to: .idle)
  }

  // MARK: - Channel seam (internal API consumed by Channel)

  /// Returns the next monotonic ref string from the shared generator.
  nonisolated func nextRef() -> String {
    refGenerator.next()
  }

  /// Sends a raw frame on the current connection without lazy-connecting.
  ///
  /// Throws `.disconnected` if no connection is available, `.transportFailure` if the send
  /// fails. This is the single point where any frame reaches the socket.
  func _rawSend(_ frame: TransportFrame) async throws(RealtimeError) {
    guard let conn = connection else {
      throw .disconnected
    }
    do {
      try await conn.send(frame)
    } catch {
      throw .transportFailure(underlying: error)
    }
  }

  /// Encodes and sends a single Phoenix frame, optionally awaiting its `phx_reply`.
  ///
  /// The single funnel for every framed send — channel pushes (broadcast, presence, join,
  /// leave, access_token) and the connection heartbeat all route through here. Handles ref
  /// generation, text/binary encoding (mapping encode failures to `.encoding`), the send,
  /// and — when `ack == .require` — reply correlation via the in-flight registry. Send
  /// failures (`.transportFailure`/`.disconnected`) propagate unchanged.
  ///
  /// Because the registry buffers early replies, awaiting *after* sending is race-free, so
  /// every ack site uses this one flow (no manual pre-register task needed).
  ///
  /// - Parameters:
  ///   - topic: The Phoenix topic (e.g. a channel's `realtime:` topic, or `"phoenix"` for heartbeat).
  ///   - event: The Phoenix event for the frame.
  ///   - body: The wire payload (text JSON, or a binary broadcast frame).
  ///   - ref: The push ref. Defaults to a fresh `nextRef()`; `join` passes its own ref so
  ///     `ref == joinRef`.
  ///   - joinRef: The join ref stamped on the frame.
  ///   - lazyConnect: When `true` (default) the socket is opened if needed before sending
  ///     (spec §6.1). The heartbeat passes `false` — it must report a dead connection via the
  ///     ack timeout rather than trigger a reconnect.
  ///   - ack: Whether to await a reply.
  /// - Returns: The `phx_reply` when `ack == .require`, otherwise `nil`.
  @discardableResult
  func _push(
    topic: String,
    _ event: PhoenixEvent,
    _ body: PushBody,
    ref: String? = nil,
    joinRef: String? = nil,
    lazyConnect: Bool = true,
    ack: AckPolicy = .none
  ) async throws(RealtimeError) -> PushReply? {
    let ref = ref ?? nextRef()

    let frame: TransportFrame
    do {
      switch body {
      case .text(let payload):
        frame = .text(
          try serializer.encodeText(
            joinRef: joinRef, ref: ref, topic: topic, event: event.rawValue, payload: payload))
      case .broadcastJSON(let payload):
        frame = .binary(
          try serializer.encodeBroadcastPush(
            joinRef: joinRef, ref: ref, topic: topic, event: event.rawValue, jsonPayload: payload))
      case .broadcastData(let payload):
        frame = .binary(
          try serializer.encodeBroadcastPush(
            joinRef: joinRef, ref: ref, topic: topic, event: event.rawValue, binaryPayload: payload)
        )
      }
    } catch {
      throw .encoding(underlying: error)
    }

    // Lazy connect (idempotent) then send. The heartbeat opts out so a dead socket surfaces
    // as `.disconnected` rather than kicking off a reconnect that races the recovery loop.
    if lazyConnect {
      try await connect()
    }
    let wallClock = ContinuousClock()
    let sentAt = wallClock.now
    try await _rawSend(frame)

    switch ack {
    case .none:
      return nil
    case .require(let timeout, let error):
      let reply = try await awaitReply(ref: ref, timeout: timeout, timeoutError: error)
      // Emit the acked-broadcast round-trip metric (spec §10 metrics-as-logs). The heartbeat
      // reports its own `heartbeat.rtt_ms`; join/leave/presence acks have no defined metric.
      if event == .broadcast {
        log(
          .debug, .broadcast, "Broadcast acknowledged",
          metadata: [
            "broadcast.ack_latency_ms": "\(sentAt.duration(to: wallClock.now).inMilliseconds)"
          ]
        )
      }
      return reply
    }
  }

  /// Encodes an `Encodable` value to `AnyJSON` using `configuration.encoder`, mapping any
  /// failure to `.encoding`. Shared by channel broadcast/presence payloads and HTTP broadcast.
  ///
  /// `nonisolated`: it only reads the immutable, Sendable `configuration` and does pure
  /// encoding, so callers (including the synchronous `Channel._encodeToJSON`) need no `await`.
  nonisolated func _encodeToJSON<T: Encodable & Sendable>(_ value: T) throws(RealtimeError)
    -> AnyJSON
  {
    do {
      let data = try configuration.encoder.encode(value)
      return try JSONDecoder().decode(AnyJSON.self, from: data)
    } catch {
      throw .encoding(underlying: error)
    }
  }

  /// Registers `ref` with the in-flight registry and suspends until the matching
  /// `phx_reply` arrives or `timeout` elapses on `configuration.clock`.
  func awaitReply(
    ref: String,
    timeout: Duration,
    timeoutError: RealtimeError
  ) async throws(RealtimeError) -> PushReply {
    try await inflightPushRegistry.awaitReply(
      ref: ref,
      timeout: timeout,
      clock: configuration.clock,
      timeoutError: timeoutError
    )
  }

  /// Returns the current access token for channel join, consulting stored state in order:
  ///
  /// 1. `_overrideToken` — set by `updateToken(_:)`; takes highest precedence.
  /// 2. `accessTokenProvider` — async closure supplied at init.
  /// 3. `nil` — anonymous / public channels (no token configured).
  ///
  /// This ordering ensures a token pushed via `updateToken(_:)` is immediately
  /// used for any subsequent joins, regardless of whether a provider is also set.
  func accessTokenForJoin() async throws(RealtimeError) -> String? {
    if let override = _overrideToken { return override }
    guard let provider = accessTokenProvider else { return nil }
    do {
      return try await provider()
    } catch {
      throw .authenticationFailed(
        reason: "Access token provider threw an error.", underlying: error)
    }
  }

  // MARK: - Token management

  /// Updates the access token used for future channel joins and pushes it to all
  /// currently-joined channels via the Phoenix `access_token` event.
  ///
  /// ## Behavior
  /// The new token is stored immediately (before any network I/O) so subsequent
  /// `subscribe()` calls always use it, even if the socket is currently down.
  ///
  /// For each channel in the registry that is currently `.joined`, an `access_token`
  /// frame is sent best-effort via `Channel.pushAccessToken(_:)`. The backend does
  /// **not** send a `phx_reply` to this event (Finding I1), so `updateToken` returns
  /// after queueing the pushes rather than awaiting an ACK.
  ///
  /// If `sendText` throws (e.g. socket is down), the per-channel push failure is
  /// swallowed — the stored token still applies on the next reconnect/rejoin.
  ///
  /// - Parameter newToken: The new JWT to store and distribute.
  /// - Throws: `RealtimeError` only if an unexpected non-send error occurs. Send
  ///   failures are swallowed (best-effort push semantics).
  public func updateToken(_ newToken: String) async throws(RealtimeError) {
    // Store the token first so future joins always pick it up, even if push fails.
    _overrideToken = newToken

    // Push to each joined channel. Failures are swallowed (best-effort).
    for channel in channels.values {
      // Channel.pushAccessToken is a no-op unless the channel is .joined.
      await channel.pushAccessToken(newToken)
    }
  }

  // MARK: - Lifecycle observer

  /// Starts the lifecycle observer if a source is available and no observer is running yet.
  /// Idempotent: a second call while the observer is already active is a no-op.
  private func _startLifecycleObserverIfNeeded() {
    guard lifecycleObserverHandle == nil, let source = lifecycleSource else { return }
    lifecycleObserverHandle = LifecycleObserver(source: source, client: self)
  }

  // MARK: - Test shims

  /// Registers a pending push with the in-flight registry and suspends until the
  /// matching `phx_reply` arrives or the timeout fires.
  ///
  /// - Note: **Test-only**. Named with a leading underscore to discourage production use.
  func _test_awaitReply(ref: String, timeoutError: RealtimeError) async throws -> PushReply {
    try await inflightPushRegistry.awaitReply(
      ref: ref,
      timeout: configuration.joinTimeout,
      clock: configuration.clock,
      timeoutError: timeoutError
    )
  }

  /// The number of pushes currently registered with the in-flight registry.
  ///
  /// - Note: **Test-only**. Used to synchronize tests before injecting reply frames.
  var _test_pendingCount: Int {
    inflightPushRegistry.pendingCount
  }

  // MARK: - Logging helper

  /// Emits a structured `LogEvent` to the configured logger.
  ///
  /// No-ops when no logger is configured. Never throws and never affects control flow.
  /// Declared `nonisolated` so it can be called from Channel's synchronous `log` helper
  /// without requiring an `await`.
  nonisolated func log(
    _ level: LogLevel,
    _ category: Category,
    _ message: String,
    metadata: [String: String] = [:]
  ) {
    logger?.log(
      LogEvent(
        level: level,
        category: category,
        message: message,
        metadata: metadata
      )
    )
  }
}

extension Duration {
  /// Whole milliseconds, for metric logging (`heartbeat.rtt_ms`, `broadcast.ack_latency_ms`).
  fileprivate var inMilliseconds: Int64 {
    components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
  }
}
