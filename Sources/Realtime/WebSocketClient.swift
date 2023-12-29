//
//  WebSocketClient.swift
//
//
//  Created by Guilherme Souza on 29/12/23.
//

import ConcurrencyExtras
import Foundation

protocol WebSocketClientProtocol: Sendable {
  func send(_ message: RealtimeMessageV2) async throws
  func receive() -> AsyncThrowingStream<RealtimeMessageV2, Error>
  func connect() -> AsyncThrowingStream<WebSocketClient.ConnectionStatus, Error>
  func cancel()
}

final class WebSocketClient: NSObject, URLSessionWebSocketDelegate, WebSocketClientProtocol,
  @unchecked Sendable
{
  struct MutableState {
    var session: URLSession?
    var task: URLSessionWebSocketTask?
    var statusContinuation: AsyncThrowingStream<ConnectionStatus, Error>.Continuation?
  }

  private let realtimeURL: URL
  private let configuration: URLSessionConfiguration

  private let mutableState = LockIsolated(MutableState())

  enum ConnectionStatus {
    case open
    case close
  }

  init(realtimeURL: URL, configuration: URLSessionConfiguration) {
    self.realtimeURL = realtimeURL
    self.configuration = configuration

    super.init()
  }

  deinit {
    mutableState.withValue {
      $0.statusContinuation?.finish()
      $0.task?.cancel()
    }
  }

  func connect() -> AsyncThrowingStream<ConnectionStatus, Error> {
    mutableState.withValue {
      $0.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
      $0.task = $0.session?.webSocketTask(with: realtimeURL)

      let (stream, continuation) = AsyncThrowingStream<ConnectionStatus, Error>.makeStream()
      $0.statusContinuation = continuation

      $0.task?.resume()

      return stream
    }
  }

  func cancel() {
    mutableState.withValue {
      $0.task?.cancel()
      $0.statusContinuation?.finish()
    }
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    mutableState.statusContinuation?.yield(.open)
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith _: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    mutableState.statusContinuation?.yield(.close)
  }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    mutableState.statusContinuation?.finish(throwing: error)
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, Error>.makeStream()

    Task {
      while let message = try await self.mutableState.task?.receive() {
        do {
          switch message {
          case let .string(stringMessage):
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
    }

    return stream
  }

  func send(_ message: RealtimeMessageV2) async throws {
    let data = try JSONEncoder().encode(message)
    let string = String(decoding: data, as: UTF8.self)
    try await mutableState.task?.send(.string(string))
  }
}
