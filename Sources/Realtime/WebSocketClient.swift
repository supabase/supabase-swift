//
//  WebSocketClient.swift
//
//
//  Created by Guilherme Souza on 29/12/23.
//

import ConcurrencyExtras
import Foundation
import Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

enum ConnectionStatus {
  case connected
  case disconnected(reason: String, code: URLSessionWebSocketTask.CloseCode)
  case error((any Error)?)
}

protocol WebSocketClient: Sendable {
  func send(_ message: RealtimeMessage) async throws
  func receive() -> AsyncThrowingStream<RealtimeMessage, any Error>
  func connect() -> AsyncStream<ConnectionStatus>
  func disconnect()
}

final class WebSocket: NSObject, URLSessionWebSocketDelegate, WebSocketClient, @unchecked Sendable {
  private let realtimeURL: URL
  private let configuration: URLSessionConfiguration
  private let logger: (any SupabaseLogger)?

  struct MutableState {
    var continuation: AsyncStream<ConnectionStatus>.Continuation?
    var connection: WebSocketConnection<RealtimeMessageV2, RealtimeMessageV2>?
  }

  private let mutableState = LockIsolated(MutableState())

  init(realtimeURL: URL, options: RealtimeClientOptions) {
    self.realtimeURL = realtimeURL

    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.httpAdditionalHeaders = options.headers.dictionary
    configuration = sessionConfiguration
    logger = options.logger
  }

  func connect() -> AsyncStream<ConnectionStatus> {
    mutableState.withValue { state in
      let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
      let task = session.webSocketTask(with: realtimeURL)
      state.connection = WebSocketConnection(task: task)
      task.resume()

      let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
      state.continuation = continuation
      return stream
    }
  }

  func disconnect() {
    mutableState.withValue { state in
      state.connection?.close()
    }
  }

  func receive() -> AsyncThrowingStream<RealtimeMessage, any Error> {
    guard let connection = mutableState.connection else {
      return .finished(
        throwing: RealtimeError(
          "receive() called before connect(). Make sure to call `connect()` before calling `receive()`."
        )
      )
    }

    return connection.receive()
  }

  func send(_ message: RealtimeMessage) async throws {
    logger?.verbose("Sending message: \(message)")
    try await mutableState.connection?.send(message)
  }

  // MARK: - URLSessionWebSocketDelegate

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    mutableState.continuation?.yield(.connected)
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    let status = ConnectionStatus.disconnected(
      reason: reason.flatMap { String(data: $0, encoding: .utf8) } ?? "",
      code: closeCode
    )

    mutableState.continuation?.yield(status)
  }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    mutableState.continuation?.yield(.error(error))
  }
}
