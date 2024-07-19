//
//  WebSocketConnection.swift
//
//
//  Created by Guilherme Souza on 29/03/24.
//

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

enum WebSocketConnectionError: Error {
  case unsupportedData
}

final class WebSocketConnection<Incoming: Codable, Outgoing: Codable>: Sendable {
  private let task: URLSessionWebSocketTask
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    task: URLSessionWebSocketTask,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder()
  ) {
    self.task = task
    self.encoder = encoder
    self.decoder = decoder

    task.resume()
  }

  deinit {
    task.cancel(with: .goingAway, reason: nil)
  }

  func receiveOnce() async throws -> Incoming {
    switch try await task.receive() {
    case let .data(data):
      let message = try decoder.decode(Incoming.self, from: data)
      return message

    case let .string(string):
      guard let data = string.data(using: .utf8) else {
        throw WebSocketConnectionError.unsupportedData
      }

      let message = try decoder.decode(Incoming.self, from: data)
      return message

    @unknown default:
      assertionFailure("Unsupported message type.")
      task.cancel(with: .unsupportedData, reason: nil)
      throw WebSocketConnectionError.unsupportedData
    }
  }

  func send(_ message: Outgoing) async throws {
    let data = try encoder.encode(message)
    try await task.send(.data(data))
  }

  func receive() -> AsyncThrowingStream<Incoming, any Error> {
    AsyncThrowingStream { [weak self] in
      guard let self else { return nil }

      let message = try await receiveOnce()
      return Task.isCancelled ? nil : message
    }
  }

  func close() {
    task.cancel(with: .normalClosure, reason: nil)
  }
}
