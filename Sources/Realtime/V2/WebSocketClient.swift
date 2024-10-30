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

enum WebSocketClientError: Error {
  case unsupportedData
}

enum ConnectionStatus {
  case connected
  case disconnected(reason: String, code: URLSessionWebSocketTask.CloseCode)
  case error((any Error)?)
}

protocol WebSocketClient: Sendable {
  func send(_ message: RealtimeMessageV2) async throws
  func receive() -> AsyncThrowingStream<RealtimeMessageV2, any Error>
  func connect() -> AsyncStream<ConnectionStatus>
  func disconnect(code: Int?, reason: String?)
}

final class WebSocket: NSObject, URLSessionWebSocketDelegate, WebSocketClient, @unchecked Sendable {
  private let realtimeURL: URL
  private let configuration: URLSessionConfiguration
  private let logger: (any SupabaseLogger)?

  struct MutableState {
    var continuation: AsyncStream<ConnectionStatus>.Continuation?
    var task: URLSessionWebSocketTask?
  }

  private let mutableState = LockIsolated(MutableState())

  init(realtimeURL: URL, options: RealtimeClientOptions) {
    self.realtimeURL = realtimeURL

    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.httpAdditionalHeaders = options.headers.dictionary
    configuration = sessionConfiguration
    logger = options.logger
  }

  deinit {
    mutableState.task?.cancel(with: .goingAway, reason: nil)
  }

  func connect() -> AsyncStream<ConnectionStatus> {
    mutableState.withValue { state in
      let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
      let task = session.webSocketTask(with: realtimeURL)
      state.task = task
      task.resume()

      let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
      state.continuation = continuation
      return stream
    }
  }

  func disconnect(code: Int?, reason: String?) {
    mutableState.withValue { state in
      if let code {
        state.task?.cancel(
          with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .invalid,
          reason: reason?.data(using: .utf8))
      } else {
        state.task?.cancel()
      }
    }
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, any Error> {
    AsyncThrowingStream { [weak self] in
      guard let self else { return nil }

      let task = mutableState.task

      guard
        let message = try await task?.receive(),
        !Task.isCancelled
      else { return nil }

      switch message {
      case .data(let data):
        let message = try JSONDecoder().decode(RealtimeMessageV2.self, from: data)
        return message

      case .string(let string):
        guard let data = string.data(using: .utf8) else {
          throw WebSocketClientError.unsupportedData
        }

        let message = try JSONDecoder().decode(RealtimeMessageV2.self, from: data)
        return message

      @unknown default:
        assertionFailure("Unsupported message type.")
        task?.cancel(with: .unsupportedData, reason: nil)
        throw WebSocketClientError.unsupportedData
      }
    }
  }

  func send(_ message: RealtimeMessageV2) async throws {
    logger?.verbose("Sending message: \(message)")

    let data = try JSONEncoder().encode(message)
    try await mutableState.task?.send(.data(data))
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
