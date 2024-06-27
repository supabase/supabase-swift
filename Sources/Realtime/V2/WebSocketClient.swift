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
  func send(_ message: RealtimeMessageV2) async throws
  func receive() -> AsyncThrowingStream<RealtimeMessageV2, any Error>
  func connect() -> AsyncStream<ConnectionStatus>
  func disconnect(closeCode: URLSessionWebSocketTask.CloseCode)
}

extension WebSocketClient {
  func disconnect() {
    disconnect(closeCode: .normalClosure)
  }
}

final class WebSocket: NSObject, URLSessionWebSocketDelegate, WebSocketClient, @unchecked Sendable {
  private let realtimeURL: URL
  private let configuration: URLSessionConfiguration
  private let logger: (any SupabaseLogger)?

  struct MutableState {
    var continuation: AsyncStream<ConnectionStatus>.Continuation?
    var stream: SocketStream?
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
      state.stream = SocketStream(task: task)
      task.resume()

      let (stream, continuation) = AsyncStream<ConnectionStatus>.makeStream()
      state.continuation = continuation
      return stream
    }
  }

  func disconnect(closeCode: URLSessionWebSocketTask.CloseCode) {
    mutableState.withValue { state in
      state.stream?.cancel(with: closeCode)
    }
  }

  func receive() -> AsyncThrowingStream<RealtimeMessageV2, any Error> {
    mutableState.withValue { mutableState in
      guard let stream = mutableState.stream else {
        return .finished(
          throwing: RealtimeError(
            "receive() called before connect(). Make sure to call `connect()` before calling `receive()`."
          )
        )
      }

      return stream.map { message in
        switch message {
        case let .string(stringMessage):
          self.logger?.verbose("Received message: \(stringMessage)")

          guard let data = stringMessage.data(using: .utf8) else {
            throw RealtimeError("Expected a UTF8 encoded message.")
          }

          let message = try JSONDecoder().decode(RealtimeMessageV2.self, from: data)
          return message

        case .data:
          fallthrough

        default:
          throw RealtimeError("Unsupported message type.")
        }
      }
      .eraseToThrowingStream()
    }
  }

  func send(_ message: RealtimeMessageV2) async throws {
    let data = try JSONEncoder().encode(message)
    let string = String(decoding: data, as: UTF8.self)

    logger?.verbose("Sending message: \(string)")
    try await mutableState.stream?.send(.string(string))
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

typealias WebSocketStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, any Error>

final class SocketStream: AsyncSequence, Sendable {
  typealias AsyncIterator = WebSocketStream.Iterator
  typealias Element = URLSessionWebSocketTask.Message

  struct MutableState {
    var continuation: WebSocketStream.Continuation?
    var stream: WebSocketStream?
  }

  private let task: URLSessionWebSocketTask
  private let mutableState = LockIsolated(MutableState())

  private func makeStreamIfNeeded() -> WebSocketStream {
    mutableState.withValue { state in
      if let stream = state.stream {
        return stream
      }

      let stream = WebSocketStream { continuation in
        state.continuation = continuation
        waitForNextValue()
      }

      state.stream = stream
      return stream
    }
  }

  private func waitForNextValue() {
    guard task.closeCode == .invalid else {
      mutableState.continuation?.finish()
      return
    }

    task.receive { [weak self] result in
      guard let continuation = self?.mutableState.continuation else { return }

      do {
        let message = try result.get()
        continuation.yield(message)
        self?.waitForNextValue()
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }

  init(task: URLSessionWebSocketTask) {
    self.task = task
  }

  deinit {
    mutableState.continuation?.finish()
  }

  func makeAsyncIterator() -> WebSocketStream.Iterator {
    makeStreamIfNeeded().makeAsyncIterator()
  }

  func cancel(with closeCode: URLSessionWebSocketTask.CloseCode = .goingAway) {
    task.cancel(with: closeCode, reason: nil)
    mutableState.continuation?.finish()
  }

  func send(_ message: URLSessionWebSocketTask.Message) async throws {
    try await task.send(message)
  }
}

#if os(Linux) || os(Windows)
  extension URLSessionWebSocketTask {
    func receive(completionHandler: @Sendable @escaping (Result<URLSessionWebSocketTask.Message, any Error>) -> Void) {
      Task {
        let result = await Result(catching: { try await self.receive() })
        completionHandler(result)
      }
    }
  }
#endif
