//
//  Realtime.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Clocks
import Foundation
import IssueReporting

public final actor Realtime: Sendable {
  let url: URL
  private let apiKey: APIKeySource
  public let configuration: Configuration
  private let transport: any RealtimeTransport

  private var connection: (any RealtimeConnection)?
  private var receiveTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var channelRegistry: [String: Channel] = [:]
  private var pendingReplies: [String: CheckedContinuation<PhoenixMessage, any Error>] = [:]
  private var refCounter: Int = 0
  private var statusContinuations: [UUID: AsyncStream<ConnectionStatus>.Continuation] = [:]
  private var _currentStatus: ConnectionStatus.State = .idle

  public var currentStatus: ConnectionStatus.State { _currentStatus }

  public init(
    url: URL,
    apiKey: APIKeySource,
    configuration: Configuration = .default,
    transport: any RealtimeTransport = URLSessionTransport()
  ) {
    self.url = url
    self.apiKey = apiKey
    self.configuration = configuration
    self.transport = transport
  }

  // MARK: - Public API

  public var status: AsyncStream<ConnectionStatus> {
    AsyncStream { continuation in
      let id = UUID()
      statusContinuations[id] = continuation
      // Emit current state immediately so new subscribers don't miss existing state.
      continuation.yield(ConnectionStatus(state: _currentStatus))
      continuation.onTermination = { [id] _ in
        Task { [weak self] in
          await self?.removeStatusContinuation(id: id)
        }
      }
    }
  }

  private func removeStatusContinuation(id: UUID) {
    statusContinuations.removeValue(forKey: id)
  }

  public func connect() async throws(RealtimeError) {
    guard _currentStatus == .idle || _currentStatus == .closed(.userRequested) else { return }
    try await _connect()
  }

  private func _connect() async throws(RealtimeError) {
    setStatus(.connecting(attempt: 1))

    let token: String
    do {
      token = try await resolveToken()
    } catch {
      setStatus(.idle)
      throw .authenticationFailed(reason: error.localizedDescription, underlying: nil)
    }

    var headers = configuration.headers
    headers["apikey"] = token
    headers["Authorization"] = "Bearer \(token)"
    headers["vsn"] = configuration.protocolVersion.rawValue

    let wsURL = buildWebSocketURL()
    let conn: any RealtimeConnection
    do {
      conn = try await transport.connect(to: wsURL, headers: headers)
    } catch {
      setStatus(.closed(.transportFailure))
      throw .transportFailure(underlying: error)
    }
    self.connection = conn
    setStatus(.connected)
    startReceiving(conn)
    startHeartbeat()
  }

  public func disconnect() async {
    receiveTask?.cancel()
    receiveTask = nil
    heartbeatTask?.cancel()
    heartbeatTask = nil
    await connection?.close(code: 1000, reason: "user requested")
    connection = nil
    setStatus(.closed(.userRequested))
    failAllPendingReplies(with: RealtimeError.disconnected)
  }

  public func updateToken(_ newToken: String) async throws(RealtimeError) {
    let msg = PhoenixMessage(
      joinRef: nil, ref: nil,
      topic: "phoenix", event: "access_token",
      payload: ["access_token": .string(newToken)]
    )
    _ = try await sendAndAwait(msg, timeout: configuration.joinTimeout)
  }

  public func channel(
    _ topic: String,
    configure: (inout ChannelOptions) -> Void = { _ in }
  ) -> Channel {
    if let existing = channelRegistry[topic] { return existing }
    var options = ChannelOptions()
    configure(&options)
    let ch = Channel(topic: topic, options: options, realtime: self)
    channelRegistry[topic] = ch
    return ch
  }

  // MARK: - Internal API (used by Channel)

  func sendBinary(_ data: Data) async throws(RealtimeError) {
    guard let connection else { throw .disconnected }
    do {
      try await connection.send(.binary(data))
    } catch let e as RealtimeError {
      throw e
    } catch {
      throw .transportFailure(underlying: error)
    }
  }

  func nextRef() -> String {
    refCounter += 1
    return String(refCounter)
  }

  func send(_ message: PhoenixMessage) async throws(RealtimeError) {
    guard let connection else { throw .disconnected }
    do {
      let text = try PhoenixSerializer.encodeText(message)
      try await connection.send(.text(text))
    } catch let e as RealtimeError {
      throw e
    } catch {
      throw .transportFailure(underlying: error)
    }
  }

  func sendAndAwait(
    _ message: PhoenixMessage,
    timeout: Duration
  ) async throws(RealtimeError) -> PhoenixMessage {
    guard connection != nil else { throw .disconnected }
    let ref = nextRef()
    var tagged = message
    tagged.ref = ref

    // Pre-encode the text frame so we don't capture a var in a concurrent closure.
    let text: String
    do {
      text = try PhoenixSerializer.encodeText(tagged)
    } catch {
      throw .encoding(underlying: error)
    }

    return try await withRealtimeTimeout(
      timeout,
      clock: configuration.clock,
      sendAndAwait: { [weak self] continuation in
        guard let self else {
          continuation.resume(throwing: RealtimeError.disconnected)
          return
        }
        await self.registerAndSend(ref: ref, text: text, continuation: continuation)
      },
      onTimeout: { [weak self] in
        Task { [weak self] in await self?.cancelPendingReply(ref: ref) }
      }
    )
  }

  private func registerAndSend(
    ref: String,
    text: String,
    continuation: CheckedContinuation<PhoenixMessage, any Error>
  ) async {
    pendingReplies[ref] = continuation
    do {
      guard let connection else {
        pendingReplies.removeValue(forKey: ref)
        continuation.resume(throwing: RealtimeError.disconnected)
        return
      }
      try await connection.send(.text(text))
    } catch {
      if let cont = pendingReplies.removeValue(forKey: ref) {
        cont.resume(throwing: error)
      }
    }
  }

  private func cancelPendingReply(ref: String) {
    if let cont = pendingReplies.removeValue(forKey: ref) {
      cont.resume(throwing: RealtimeError.channelJoinTimeout)
    }
  }

  func removeChannel(_ topic: String) {
    channelRegistry.removeValue(forKey: topic)
  }

  // MARK: - Private

  func resolveToken() async throws -> String {
    switch apiKey {
    case .literal(let key): return key
    case .dynamic(let fn): return try await fn()
    }
  }

  private func buildWebSocketURL() -> URL {
    guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    var items = comps.queryItems ?? []
    items.append(URLQueryItem(name: "vsn", value: configuration.protocolVersion.rawValue))
    comps.queryItems = items
    return comps.url ?? url
  }

  private func setStatus(_ state: ConnectionStatus.State) {
    _currentStatus = state
    let s = ConnectionStatus(state: state)
    for cont in statusContinuations.values { cont.yield(s) }
  }

  private func startReceiving(_ conn: any RealtimeConnection) {
    receiveTask = Task { [weak self] in
      do {
        for try await frame in conn.frames {
          await self?.handle(frame)
        }
        // Stream ended cleanly — treat as connection loss.
        await self?.handleConnectionLoss(error: URLError(.networkConnectionLost))
      } catch {
        await self?.handleConnectionLoss(error: error)
      }
    }
  }

  private func handle(_ frame: TransportFrame) async {
    switch frame {
    case .text(let text):
      guard let msg = try? PhoenixSerializer.decodeText(text) else { return }
      await route(msg)
    case .binary(let data):
      guard let broadcast = try? PhoenixSerializer.decodeBinary(data) else { return }
      if let ch = channelRegistry[broadcast.topic] {
        await ch.handleBinaryBroadcast(broadcast)
      }
    }
  }

  private func route(_ msg: PhoenixMessage) async {
    // Heartbeat reply
    if msg.topic == "phoenix", msg.event == "phx_reply" {
      if let ref = msg.ref, let cont = pendingReplies.removeValue(forKey: ref) {
        cont.resume(returning: msg)
      }
      return
    }
    // Pending reply (join/leave/token ack)
    if msg.event == "phx_reply", let ref = msg.ref,
      let cont = pendingReplies.removeValue(forKey: ref)
    {
      cont.resume(returning: msg)
      return
    }
    // Route to channel
    if let ch = channelRegistry[msg.topic] {
      await ch.handle(msg)
    }
  }

  private func handleConnectionLoss(error: any Error) async {
    guard _currentStatus != .closed(.userRequested) else { return }
    setStatus(.closed(.transportFailure))
    failAllPendingReplies(with: .disconnected)
    for ch in channelRegistry.values {
      await ch.handleConnectionLoss()
    }
    await attemptReconnect(lastError: error)
  }

  private func attemptReconnect(lastError: any Error) async {
    var attempt = 1
    while !Task.isCancelled {
      guard let delay = configuration.reconnection.nextDelay(attempt, lastError) else {
        setStatus(.closed(.transportFailure))
        return
      }
      setStatus(.reconnecting(attempt: attempt))
      try? await configuration.clock.sleep(for: delay)
      guard !Task.isCancelled else { return }
      do {
        try await _connect()
        for ch in channelRegistry.values {
          try? await ch.rejoin()
        }
        return
      } catch {
        attempt += 1
      }
    }
  }

  private func startHeartbeat() {
    heartbeatTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          try await self.configuration.clock.sleep(for: self.configuration.heartbeat)
          let msg = PhoenixMessage(
            joinRef: nil, ref: nil,
            topic: "phoenix", event: "heartbeat",
            payload: [:]
          )
          _ = try await self.sendAndAwait(msg, timeout: self.configuration.heartbeat)
        } catch is CancellationError {
          return
        } catch {
          // heartbeat failure triggers connection loss via the receive loop
        }
      }
    }
  }

  private func failAllPendingReplies(with error: RealtimeError) {
    let replies = pendingReplies
    pendingReplies.removeAll()
    for cont in replies.values {
      cont.resume(throwing: error)
    }
  }
}

// MARK: - Timeout helper

/// Runs `sendAndAwait` within a racing timeout.
///
/// - Parameters:
///   - sendAndAwait: Called with a continuation. The callee must eventually resume the continuation.
///   - onTimeout: Called (from a nonisolated context) when the timeout fires first.
func withRealtimeTimeout<T: Sendable>(
  _ duration: Duration,
  clock: any Clock<Duration>,
  sendAndAwait: @escaping @Sendable (CheckedContinuation<T, any Error>) async -> Void,
  onTimeout: @escaping @Sendable () -> Void
) async throws(RealtimeError) -> T {
  // We use a manual continuation + a racing Task instead of TaskGroup so the
  // sendAndAwait closure can be called while already inside the actor.
  do {
    return try await withCheckedThrowingContinuation { continuation in
      Task {
        await withTaskGroup(of: Void.self) { group in
          // Timeout race.
          group.addTask {
            do {
              try await clock.sleep(for: duration)
              onTimeout()
              continuation.resume(throwing: RealtimeError.channelJoinTimeout)
            } catch {
              // Task cancelled — operation already completed.
            }
          }
          // Actual work.
          group.addTask {
            await sendAndAwait(continuation)
          }
          // Wait for the first one to finish, then cancel the other.
          await group.next()
          group.cancelAll()
        }
      }
    }
  } catch let e as RealtimeError {
    throw e
  } catch {
    throw .transportFailure(underlying: error)
  }
}
