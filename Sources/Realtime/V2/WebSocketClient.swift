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

protocol WebSocketClientProtocol: Sendable {
  var status: AsyncStream<WebSocketClient.ConnectionStatus> { get }

  func send(_ message: RealtimeMessageV2) async throws
  func receive() -> AsyncThrowingStream<RealtimeMessageV2, Error>
  func connect() async
  func cancel()
}

final class WebSocketClient: NSObject, URLSessionWebSocketDelegate, WebSocketClientProtocol,
  @unchecked Sendable
{
  struct MutableState {
    var session: URLSession?
    var task: URLSessionWebSocketTask?
  }

  private let realtimeURL: URL
  private let configuration: URLSessionConfiguration
  private let logger: SupabaseLogger?

  private let mutableState = LockIsolated(MutableState())

  enum ConnectionStatus {
    case open
    case close
    case error(Error)
  }

  init(realtimeURL: URL, configuration: URLSessionConfiguration, logger: SupabaseLogger?) {
    self.realtimeURL = realtimeURL
    self.configuration = configuration

    let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
    status = stream
    self.continuation = continuation

    self.logger = logger
    super.init()
  }

  deinit {
    mutableState.withValue {
      $0.task?.cancel()
    }

    continuation.finish()
  }

  private let continuation: AsyncStream<ConnectionStatus>.Continuation
  var status: AsyncStream<ConnectionStatus>

  func connect() {
    mutableState.withValue {
      $0.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
      $0.task = $0.session?.webSocketTask(with: realtimeURL)
      $0.task?.resume()
    }
  }

  func cancel() {
    mutableState.withValue {
      $0.task?.cancel()
    }

    continuation.finish()
  }

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
    if let error {
      continuation.yield(.error(error))
    }
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, Error>.makeStream()

    Task {
      while let message = try await self.mutableState.task?.receive() {
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
}
