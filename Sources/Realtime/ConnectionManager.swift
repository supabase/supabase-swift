import ConcurrencyExtras
import Foundation

actor ConnectionManager {
  enum State: Sendable {
    case disconnected
    case connecting(Task<Void, any Error>)
    case connected(any WebSocket)
    case reconnecting(Task<Void, any Error>, reason: String)
  }

  private let (stateStream, stateContinuation) = AsyncStream<State>.makeStream()
  private(set) var state: State = .disconnected

  private let transport: WebSocketTransport
  private let url: URL
  private let headers: [String: String]
  private let reconnectDelay: TimeInterval
  private let logger: (any SupabaseLogger)?
  // Captured at init time so parallel test classes that swap _clock cannot
  // change the timing of an already-running client.
  let clock: any _Clock

  /// Get current connection if connected, nil otherwise.
  var connection: (any WebSocket)? {
    if case .connected(let conn) = state {
      return conn
    }
    return nil
  }

  nonisolated var stateChanges: AsyncStream<State> { stateStream }

  init(
    transport: @escaping WebSocketTransport,
    url: URL,
    headers: [String: String],
    reconnectDelay: TimeInterval,
    logger: (any SupabaseLogger)?,
    clock: any _Clock = _clock
  ) {
    self.transport = transport
    self.url = url
    self.headers = headers
    self.reconnectDelay = reconnectDelay
    self.logger = logger
    self.clock = clock
  }

  @discardableResult
  func connect() async throws -> any WebSocket {
    logger?.debug("current state: \(state)")

    switch state {
    case .connected(let conn):
      logger?.debug("Already connected")
      return conn

    case .connecting(let task):
      logger?.debug("Connection already in progress, waiting...")
      try await task.value
      // After waiting, get the connection from state
      guard case .connected(let conn) = state else {
        throw WebSocketError.connection(
          message: "Connection failed", error: NSError(domain: "ConnectionManager", code: -1))
      }
      return conn

    case .disconnected:
      logger?.debug("Initiating new connection")
      try await performConnection()
      guard case .connected(let conn) = state else {
        throw WebSocketError.connection(
          message: "Connection failed", error: NSError(domain: "ConnectionManager", code: -1))
      }
      return conn

    case .reconnecting(let task, _):
      logger?.debug("Reconnection in progress, waiting...")
      try await task.value
      guard case .connected(let conn) = state else {
        throw WebSocketError.connection(
          message: "Connection failed", error: NSError(domain: "ConnectionManager", code: -1))
      }
      return conn
    }
  }

  func disconnect(reason: String? = nil) {
    logger?.debug("current state: \(state)")

    switch state {
    case .connected(let conn):
      logger?.debug("Disconnecting from WebSocket: \(reason ?? "no reason")")
      conn.close(code: nil, reason: reason)
      updateState(.disconnected)

    case .connecting(let task), .reconnecting(let task, _):
      logger?.debug("Cancelling connection attempt: \(reason ?? "no reason")")
      task.cancel()
      updateState(.disconnected)

    case .disconnected:
      logger?.debug("Already disconnected")
    }
  }

  /// Handle connection error and initiate reconnect.
  ///
  /// - Parameters:
  ///   - error: The error that caused the connection failure
  ///   - conn: The connection the error originated from. When provided and it
  ///     isn't the current connection (e.g. a late error surfacing from a
  ///     socket that has already been replaced by a reconnect), the error is
  ///     ignored so it can't tear down a healthy connection.
  func handleError(_ error: any Error, from conn: (any WebSocket)? = nil) {
    guard !(error is CancellationError) else {
      logger?.debug("CancellationError do not trigger reconnects.")
      return
    }

    guard case .connected(let current) = state else {
      logger?.debug("Ignoring error in non-connected state: \(error)")
      return
    }

    if let conn, conn !== current {
      logger?.debug("Ignoring error from stale connection: \(error)")
      return
    }

    logger?.debug("Connection error, initiating reconnect: \(error.localizedDescription)")

    // Close the connection and update to disconnected before reconnecting
    current.close(code: nil, reason: "error: \(error.localizedDescription)")
    updateState(.disconnected)

    initiateReconnect(reason: "error: \(error.localizedDescription)")
  }

  /// Handle connection close initiated by the remote.
  ///
  /// The connection is already closed by the remote; just update state.
  ///
  /// - Parameters:
  ///   - code: WebSocket close code
  ///   - reason: WebSocket close reason
  ///   - conn: The connection the close event originated from. When provided
  ///     and it isn't the current connection (a `.close` frame from an old
  ///     socket can arrive after a reconnect already established a new one),
  ///     the event is ignored so it can't mark a healthy connection as
  ///     disconnected.
  func handleClose(code: Int?, reason: String?, from conn: (any WebSocket)? = nil) {
    let closeReason = "code: \(code?.description ?? "none"), reason: \(reason ?? "none")"
    logger?.debug("Connection closed by remote: \(closeReason)")

    if case .connected(let current) = state {
      if let conn, conn !== current {
        logger?.debug("Ignoring close from stale connection: \(closeReason)")
        return
      }
      updateState(.disconnected)
      // Application-level close codes (4000–4999) typically signal auth or
      // protocol errors. Reconnecting with the same bad token would loop;
      // the caller must re-authenticate before reconnecting.
      guard code.map({ $0 < 4000 }) ?? true else {
        logger?.debug("Skipping reconnect for application close code \(code!)")
        return
      }
      initiateReconnect(reason: closeReason)
    }
  }

  private func performConnection() async throws {
    let connectionTask = Task {
      let conn = try await transport(url, headers)
      try Task.checkCancellation()
      updateState(.connected(conn))
    }

    updateState(.connecting(connectionTask))

    do {
      return try await connectionTask.value
    } catch {
      updateState(.disconnected)
      throw error
    }
  }

  private func initiateReconnect(reason: String) {
    let reconnectTask = Task {
      try await clock.sleep(for: reconnectDelay)
      logger?.debug("Attempting to reconnect...")
      try await performConnection()
    }

    updateState(.reconnecting(reconnectTask, reason: reason))
  }

  private func updateState(_ state: State) {
    self.state = state
    self.stateContinuation.yield(state)
  }
}
