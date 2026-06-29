//
//  Realtime.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Clocks
import ConcurrencyExtras
import Foundation
import IssueReporting

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

  private let url: URL
  private let apiKey: String
  private let accessTokenProvider: AccessTokenProvider?
  private let configuration: Configuration
  private let transport: any RealtimeTransport

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

  /// Registry tracking in-flight pushes awaiting a `phx_reply`.
  let inflightPushRegistry = InflightPushRegistry()

  /// Monotonic ref generator shared across all protocol frames.
  let refGenerator = RefGenerator()

  /// Serializer for encoding/decoding Phoenix protocol frames.
  let serializer = PhoenixSerializer()

  /// Topic → Channel registry. First-call-wins (Decision 33).
  var channels: [String: Channel] = [:]

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
    transport: any RealtimeTransport = URLSessionTransport()
  ) {
    self.url = url
    self.apiKey = apiKey
    self.accessTokenProvider = accessToken
    self.configuration = configuration
    self.transport = transport
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
    if let existing = channels[topic] {
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
    let ch = Channel(topic: topic, options: options, realtime: self)
    channels[topic] = ch
    return ch
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

  /// Builds the connect URL (apikey query param), connect headers, and calls transport.connect.
  private func _performConnect() async throws {
    // Build connect URL: append apikey= query item to base URL.
    var components =
      URLComponents(url: url, resolvingAgainstBaseURL: false)
      ?? URLComponents()
    var queryItems = components.queryItems ?? []
    queryItems.append(URLQueryItem(name: "apikey", value: apiKey))
    components.queryItems = queryItems
    guard let connectURL = components.url else {
      throw RealtimeError.transportFailure(
        underlying: URLError(.badURL)
      )
    }

    // Build connect headers: merge configuration headers + x-api-key.
    var headers = configuration.headers
    headers["x-api-key"] = apiKey

    // Signal connecting.
    transition(to: .connecting(attempt: 1))

    // Open the transport.
    let conn = try await transport.connect(to: connectURL, headers: headers)
    connection = conn

    // Signal connected.
    transition(to: .connected)

    // Start the background frame routing loop.
    startFrameRouting(connection: conn)

    // Start the periodic heartbeat loop.
    startHeartbeat(connection: conn)
  }

  // MARK: - Heartbeat

  /// Starts the heartbeat loop and stores the task handle so it can be cancelled.
  private func startHeartbeat(connection: any RealtimeConnection) {
    heartbeatTask?.cancel()
    let heartbeatDuration = configuration.heartbeat
    let clock = configuration.clock
    let registry = inflightPushRegistry
    let gen = refGenerator

    let heartbeater = Heartbeater(
      heartbeat: heartbeatDuration,
      clock: clock,
      refGenerator: gen,
      sendFrame: { text in
        // connection is captured by-value (protocol existential, not a class).
        // If it has been cleared the send is a no-op.
        try await connection.send(.text(text))
      },
      awaitReply: { [weak self] ref in
        guard self != nil else { throw RealtimeError.disconnected }
        return try await registry.awaitReply(
          ref: ref,
          timeout: heartbeatDuration,
          clock: clock,
          timeoutError: .disconnected
        )
      },
      updateLatency: { [weak self] duration in
        await self?.updateLatency(duration)
      },
      onConnectionLost: { [weak self] error in
        await self?.handleConnectionLost(error)
      }
    )
    heartbeatTask = heartbeater.start()
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
  }

  // MARK: - Connection loss

  /// Minimal connection-loss handler. Cancels heartbeat + routing tasks, clears the
  /// connection, and transitions status to `.idle`.
  ///
  /// Expanded in Task 13 (reconnection).
  func handleConnectionLost(_ error: RealtimeError) async {
    // Cancel background tasks.
    heartbeatTask?.cancel()
    heartbeatTask = nil
    routingTask?.cancel()
    routingTask = nil

    // Fail all pending pushes so callers don't hang indefinitely.
    await inflightPushRegistry.failAll(error)

    // Close and clear the connection.
    await connection?.close(code: 1001, reason: "connection lost")
    connection = nil

    // Transition to idle so status stream consumers know the socket is gone.
    transition(to: .idle)
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
}
