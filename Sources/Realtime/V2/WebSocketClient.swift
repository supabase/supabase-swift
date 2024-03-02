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
  case complete(Error?)
}

private actor LiveWebSocketClient {
protocol WebSocketClient {
  var status: AsyncStream<ConnectionStatus> { get }

  func send(_ message: RealtimeMessageV2) async throws
  func receive() -> AsyncThrowingStream<RealtimeMessageV2, Error>
  func connect()
  func cancel()
}

final class DefaultWebSocketClient: NSObject, URLSessionWebSocketDelegate, WebSocketClient {
  private let realtimeURL: URL
  private let configuration: URLSessionConfiguration
  private let logger: (any SupabaseLogger)?

  struct MutableState {
    var task: URLSessionWebSocketTask?
  }

  let mutableState = LockIsolated(MutableState())

  init(realtimeURL: URL, configuration: URLSessionConfiguration, logger: (any SupabaseLogger)?) {
    self.realtimeURL = realtimeURL
    self.configuration = configuration

    let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
    status = stream
    self.continuation = continuation

    self.logger = logger
  }

  deinit {
    cancel()
  }

  let continuation: AsyncStream<ConnectionStatus>.Continuation
  let status: AsyncStream<ConnectionStatus>

  func connect() {
    mutableState.withValue { state in
      let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
      state.task = session.webSocketTask(with: realtimeURL)
      state.task?.resume()
    }
  }

  func cancel() {
    mutableState.withValue { state in
      state.task?.cancel()
      state = .init()
    }

    continuation.finish()
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, Error>.makeStream()

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
    continuation.yield(.open)
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith _: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    continuation.yield(.close)
  }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    continuation.yield(.complete(error))
  }
}
