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

struct WebSocketClient {
  enum ConnectionStatus {
    case open
    case close
    case error(Error)
  }

  var status: AsyncStream<WebSocketClient.ConnectionStatus>

  var send: (_ message: RealtimeMessageV2) async throws -> Void
  var receive: () -> AsyncThrowingStream<RealtimeMessageV2, Error>
  var connect: () async -> Void
  var cancel: () -> Void
}

extension WebSocketClient {
  init(realtimeURL: URL, configuration: URLSessionConfiguration, logger: SupabaseLogger?) {
    let client = LiveWebSocketClient(
      realtimeURL: realtimeURL,
      configuration: configuration,
      logger: logger
    )
    self.init(
      status: client.status,
      send: { try await client.send($0) },
      receive: { client.receive() },
      connect: { await client.connect() },
      cancel: { client.cancel() }
    )
  }
}

private actor LiveWebSocketClient {
  private let realtimeURL: URL
  private let configuration: URLSessionConfiguration
  private let logger: SupabaseLogger?

  private var delegate: Delegate?
  private var session: URLSession?
  private var task: URLSessionWebSocketTask?

  init(realtimeURL: URL, configuration: URLSessionConfiguration, logger: SupabaseLogger?) {
    self.realtimeURL = realtimeURL
    self.configuration = configuration

    let (stream, continuation) = AsyncStream<WebSocketClient.ConnectionStatus>.makeStream()
    status = stream
    self.continuation = continuation

    self.logger = logger
  }

  deinit {
    task?.cancel()
    continuation.finish()
  }

  let continuation: AsyncStream<WebSocketClient.ConnectionStatus>.Continuation
  nonisolated let status: AsyncStream<WebSocketClient.ConnectionStatus>

  func connect() {
    delegate = Delegate { [weak self] status in
      self?.continuation.yield(status)
    }
    session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    task = session?.webSocketTask(with: realtimeURL)
    task?.resume()
  }

  nonisolated func cancel() {
    Task { await _cancel() }
  }

  private func _cancel() {
    task?.cancel()
    continuation.finish()
  }

  nonisolated func receive() -> AsyncThrowingStream<RealtimeMessageV2, Error> {
    let (stream, continuation) = AsyncThrowingStream<RealtimeMessageV2, Error>.makeStream()

    Task {
      while let message = try await self.task?.receive() {
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
    try await task?.send(.string(string))
  }

  final class Delegate: NSObject, URLSessionWebSocketDelegate {
    let onStatusChange: (_ status: WebSocketClient.ConnectionStatus) -> Void

    init(onStatusChange: @escaping (_ status: WebSocketClient.ConnectionStatus) -> Void) {
      self.onStatusChange = onStatusChange
    }

    func urlSession(
      _: URLSession,
      webSocketTask _: URLSessionWebSocketTask,
      didOpenWithProtocol _: String?
    ) {
      onStatusChange(.open)
    }

    func urlSession(
      _: URLSession,
      webSocketTask _: URLSessionWebSocketTask,
      didCloseWith _: URLSessionWebSocketTask.CloseCode,
      reason _: Data?
    ) {
      onStatusChange(.close)
    }

    func urlSession(
      _: URLSession,
      task _: URLSessionTask,
      didCompleteWithError error: Error?
    ) {
      if let error {
        onStatusChange(.error(error))
      }
    }
  }
}
