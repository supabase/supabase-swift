//
//  Realtime.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
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
/// The `transport` parameter is required for now (no default).
/// TODO(Task 11): default transport: URLSessionTransport()
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

  /// Topic → Channel registry. First-call-wins (Decision 33).
  private var channels: [String: Channel] = [:]

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
  ///     TODO(Task 11): default transport: URLSessionTransport()
  public init(
    url: URL,
    apiKey: String,
    accessToken: AccessTokenProvider? = nil,
    configuration: Configuration = .default,
    transport: any RealtimeTransport
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
      // Decision 33: first-call-wins — warn but return the pre-existing channel.
      reportIssue(
        "Realtime.channel(\"\(topic)\") called more than once. The options from the first call "
          + "are in effect. To change options, deinit the previous channel first."
      )
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
    let task = Task<Void, any Error> { [weak self] in
      guard let self else { return }
      try await self._performConnect()
    }
    connectTask = task

    do {
      try await task.value
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

  private func transition(to state: ConnectionStatus.State) {
    currentStatus = ConnectionStatus(state: state, since: Date(), latency: nil)
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
    headers[.init("x-api-key")!] = apiKey

    // Signal connecting.
    transition(to: .connecting(attempt: 1))

    // Open the transport.
    let conn = try await transport.connect(to: connectURL, headers: headers)
    connection = conn

    // Signal connected.
    transition(to: .connected)
  }
}
