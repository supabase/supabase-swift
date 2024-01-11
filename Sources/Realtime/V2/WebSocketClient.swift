//
//  WebSocketClient.swift
//
//
//  Created by Guilherme Souza on 29/12/23.
//

import Combine
import ConcurrencyExtras
import Foundation
@_spi(Internal) import _Helpers

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

  private let mutableState = LockIsolated(MutableState())

  enum ConnectionStatus {
    case open
    case close
    case error(Error)
  }

  init(realtimeURL: URL, configuration: URLSessionConfiguration) {
    self.realtimeURL = realtimeURL
    self.configuration = configuration

    super.init()
  }

  deinit {
    mutableState.withValue {
      $0.task?.cancel()
    }

    statusSubject.send(completion: .finished)
  }

  private let statusSubject = PassthroughSubject<ConnectionStatus, Never>()

  var status: AsyncStream<ConnectionStatus> {
    statusSubject.values
  }

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

    statusSubject.send(completion: .finished)
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    statusSubject.send(.open)
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith _: URLSessionWebSocketTask.CloseCode,
    reason _: Data?
  ) {
    statusSubject.send(.close)
  }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error {
      statusSubject.send(.error(error))
    }
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, Error>.makeStream()

    Task {
      while let message = try await self.mutableState.task?.receive() {
        do {
          switch message {
          case let .string(stringMessage):
            debug("Received message: \(stringMessage)")

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

    debug("Sending message: \(string)")
    try await mutableState.task?.send(.string(string))
  }
}
