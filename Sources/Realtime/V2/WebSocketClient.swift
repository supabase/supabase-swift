//
//  WebSocketClient.swift
//
//
//  Created by Guilherme Souza on 29/12/23.
//

import ConcurrencyExtras
import Foundation
@_spi(Internal) import _Helpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

enum ConnectionStatus {
  case open
  case close
  case complete((any Error)?)
}

protocol WebSocketClient: Sendable {
  func send(_ message: RealtimeMessageV2) async throws -> Void
  func receive() -> AsyncThrowingStream<RealtimeMessageV2, any Error>
  func connect() -> AsyncStream<ConnectionStatus>
  func cancel()
}

class DefaultWebSocketClient: NSObject, URLSessionWebSocketDelegate, WebSocketClient,
  @unchecked Sendable
{
  private let realtimeURL: URL
  private let configuration: URLSessionConfiguration
  private let logger: (any SupabaseLogger)?

  struct MutableState {
    var task: URLSessionWebSocketTask?
    var continuation: AsyncStream<ConnectionStatus>.Continuation?
  }

  let mutableState = LockIsolated(MutableState())

  init(realtimeURL: URL, configuration: URLSessionConfiguration, logger: (any SupabaseLogger)?) {
    self.realtimeURL = realtimeURL
    self.configuration = configuration
    self.logger = logger
  }

  deinit {
    cancel()
  }

  func connect() -> AsyncStream<ConnectionStatus> {
    mutableState.withValue { state in
      let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
      state.task = session.webSocketTask(with: realtimeURL)
      state.task?.resume()

      let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
      state.continuation = continuation
      return stream
    }
  }

  func cancel() {
    mutableState.withValue { state in
      state.task?.cancel()
      state.continuation?.finish()
      state = .init()
    }
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, any Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, any Error>.makeStream()

    Task {
      while let message = try await mutableState.task?.receive() {
        do {
          switch message {
          case let .string(stringMessage):
            logger?.verbose("Received message: \(stringMessage)")

            guard let data = stringMessage.data(using: .utf8) else {
              throw RealtimeError("Expected a UTF8 encoded message.")
            }

            let message = try JSONDecoder().decode(RealtimeMessageV2.self, from: data)
            continuation.yield(message)

          case .data:
            fallthrough
          default:
            throw RealtimeError("Unsupported message type.")
          }
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.finish()
    }

    return stream
  }

  func send(_ message: RealtimeMessageV2) async throws {
    let data = try JSONEncoder().encode(message)
    let string = String(decoding: data, as: UTF8.self)

    logger?.verbose("Sending message: \(string)")
    try await mutableState.task?.send(.string(string))
  }

  // MARK: - URLSessionWebSocketDelegate

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    mutableState.continuation?.yield(.open)
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith _: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    mutableState.continuation?.yield(.close)
  }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    mutableState.continuation?.yield(.complete(error))
  }
}
