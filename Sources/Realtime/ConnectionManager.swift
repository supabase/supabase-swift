//
//  ConnectionManager.swift
//  Supabase
//
//  Created by Guilherme Souza on 19/11/25.
//

import Foundation

actor ConnectionManager {
  enum State {
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

  /// Get current connection if connected, nil otherwise.
  var connection: (any WebSocket)? {
    if case .connected(let conn) = state {
      return conn
    }
    return nil
  }

  var stateChanges: AsyncStream<State> { stateStream }

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

  func connect() async throws {
    logger?.debug("current state: \(state)")

    switch state {
    case .connected:
      logger?.debug("Already connected")

    case .connecting(let task):
      logger?.debug("Connection already in progress, waiting...")
      try await task.value

    case .disconnected:
      logger?.debug("Initiating new connection")
      try await performConnection()

    case .reconnecting(let task, _):
      logger?.debug("Reconnection in progress, waiting...")
      try await task.value
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
  /// - Parameter error: The error that caused the connection failure
  func handleError(_ error: any Error) {
    guard !(error is CancellationError) else {
      logger?.debug("CancellationError do not trigger reconnects.")
      return
    }

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
      try await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
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
