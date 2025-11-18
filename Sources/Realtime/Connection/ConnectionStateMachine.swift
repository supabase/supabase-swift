//
//  ConnectionStateMachine.swift
//  Realtime
//
//  Created on 17/01/25.
//

import Foundation
import Helpers

/// Manages WebSocket connection lifecycle with clear state transitions.
///
/// This actor ensures thread-safe connection management and prevents race conditions
/// by enforcing valid state transitions through Swift's type system.
actor ConnectionStateMachine {
  /// Represents the possible states of a WebSocket connection
  enum State: Sendable {
    case disconnected
    case connecting(Task<Void, any Error>)
    case connected(any WebSocket)
    case reconnecting(Task<Void, any Error>, reason: String)
  }

  // MARK: - Properties

  private(set) var state: State = .disconnected

  private let transport: WebSocketTransport
  private let url: URL
  private let headers: [String: String]
  private let reconnectDelay: TimeInterval
  private let logger: (any SupabaseLogger)?

  // MARK: - Initialization

  init(
    transport: @escaping WebSocketTransport,
    url: URL,
    headers: [String: String],
    reconnectDelay: TimeInterval,
    logger: (any SupabaseLogger)?
  ) {
    self.transport = transport
    self.url = url
    self.headers = headers
    self.reconnectDelay = reconnectDelay
    self.logger = logger
  }

  // MARK: - Public API

  /// Connect to WebSocket. Returns existing connection if already connected.
  ///
  /// This method is safe to call multiple times - it will reuse an existing connection
  /// or wait for an in-progress connection attempt to complete.
  ///
  /// - Returns: The active WebSocket connection
  /// - Throws: Connection errors from the transport layer
  func connect() async throws -> any WebSocket {
    switch state {
    case .connected(let conn):
      logger?.debug("Already connected to WebSocket")
      return conn

    case .connecting(let task):
      logger?.debug("Connection already in progress, waiting...")
      try await task.value
      // Recursively call to get the connection after task completes
      return try await connect()

    case .reconnecting(let task, _):
      logger?.debug("Reconnection in progress, waiting...")
      try await task.value
      return try await connect()

    case .disconnected:
      logger?.debug("Initiating new connection")
      return try await performConnection()
    }
  }

  /// Disconnect and clean up resources.
  ///
  /// - Parameter reason: Optional reason for disconnection
  func disconnect(reason: String? = nil) {
    switch state {
    case .connected(let conn):
      logger?.debug("Disconnecting from WebSocket: \(reason ?? "no reason")")
      conn.close(code: nil, reason: reason)
      state = .disconnected

    case .connecting(let task), .reconnecting(let task, _):
      logger?.debug("Cancelling connection attempt: \(reason ?? "no reason")")
      task.cancel()
      state = .disconnected

    case .disconnected:
      logger?.debug("Already disconnected")
    }
  }

  /// Handle connection error and initiate reconnect.
  ///
  /// - Parameter error: The error that caused the connection failure
  func handleError(_ error: any Error) {
    guard case .connected = state else {
      logger?.debug("Ignoring error in non-connected state: \(error)")
      return
    }

    logger?.debug("Connection error, initiating reconnect: \(error.localizedDescription)")
    initiateReconnect(reason: "error: \(error.localizedDescription)")
  }

  /// Handle connection close.
  ///
  /// - Parameters:
  ///   - code: WebSocket close code
  ///   - reason: WebSocket close reason
  func handleClose(code: Int?, reason: String?) {
    let closeReason = "code: \(code?.description ?? "none"), reason: \(reason ?? "none")"
    logger?.debug("Connection closed: \(closeReason)")

    disconnect(reason: reason)
  }

  /// Handle disconnection event and initiate reconnect.
  func handleDisconnected() {
    guard case .connected = state else { return }

    logger?.debug("Connection disconnected, initiating reconnect")
    initiateReconnect(reason: "disconnected")
  }

  /// Get current connection if connected, nil otherwise.
  var connection: (any WebSocket)? {
    if case .connected(let conn) = state {
      return conn
    }
    return nil
  }

  /// Check if currently connected.
  var isConnected: Bool {
    if case .connected = state {
      return true
    }
    return false
  }

  // MARK: - Private Helpers

  private func performConnection() async throws -> any WebSocket {
    let connectionTask = Task<Void, any Error> {
      let conn = try await transport(url, headers)
      state = .connected(conn)
    }

    state = .connecting(connectionTask)

    do {
      try await connectionTask.value

      // Get the connection that was just set
      guard case .connected(let conn) = state else {
        throw RealtimeError("Connection succeeded but state is invalid")
      }

      return conn
    } catch {
      state = .disconnected
      throw error
    }
  }

  private func initiateReconnect(reason: String) {
    let reconnectTask = Task<Void, any Error> {
      try await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))

      if Task.isCancelled {
        logger?.debug("Reconnect cancelled")
        return
      }

      logger?.debug("Attempting to reconnect...")
      _ = try await performConnection()
    }

    state = .reconnecting(reconnectTask, reason: reason)
  }
}
