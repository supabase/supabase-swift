//
//  Channel+Broadcast.swift
//  _Realtime
//
//  Created by Guilherme Souza on 24/04/25.
//

import Foundation

extension Channel {
  // MARK: - Receive API

  /// Returns an `AsyncThrowingStream` that yields every broadcast message arriving on this channel.
  ///
  /// The channel is automatically joined on the first call if it has not been joined yet.
  /// The stream finishes with a `RealtimeError` when the channel closes or an error occurs.
  ///
  /// Multiple calls create independent fan-out streams — all subscribers receive every message.
  ///
  /// - Returns: An async stream of `BroadcastMessage` values.
  public func broadcasts() -> AsyncThrowingStream<BroadcastMessage, any Error> {
    AsyncThrowingStream { continuation in
      let id = UUID()
      Task {
        self.registerBroadcastContinuation(id: id, continuation: continuation)
        continuation.onTermination = { [id] _ in
          Task { await self.removeBroadcastContinuation(id: id) }
        }
        do {
          try await self.joinIfNeeded()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  /// Returns an `AsyncThrowingStream` that yields broadcast messages matching `event`,
  /// decoded as `T` using the channel's configured `JSONDecoder`.
  ///
  /// - Parameters:
  ///   - event: Only messages whose `event` field equals this string are emitted.
  ///   - decoder: A custom `JSONDecoder`. Defaults to `JSONDecoder()`.
  ///   - type: The `Decodable` type to decode the payload into.
  /// - Returns: An async stream of decoded values.
  public func broadcasts<T: Decodable & Sendable>(
    of _: T.Type = T.self,
    event: String,
    decoder: JSONDecoder = JSONDecoder()
  ) -> AsyncThrowingStream<T, any Error> {
    AsyncThrowingStream { continuation in
      let base = self.broadcasts()
      let task = Task {
        do {
          for try await msg in base {
            guard msg.event == event else { continue }
            do {
              let data = try JSONEncoder().encode(msg.payload)
              let value = try decoder.decode(T.self, from: data)
              continuation.yield(value)
            } catch {
              continuation.finish(
                throwing: RealtimeError.decoding(
                  type: String(describing: T.self), underlying: error)
              )
              return
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: - Send API

  /// Broadcasts an `Encodable` value as a JSON payload on this channel.
  ///
  /// The channel must be in the `.joined` state. Use ``join()`` or rely on ``broadcasts()``
  /// auto-join before calling this method.
  ///
  /// - Parameters:
  ///   - value: The value to encode and broadcast.
  ///   - event: The event name carried by the broadcast.
  /// - Throws: `RealtimeError.channelNotJoined` if the channel has not joined,
  ///           `RealtimeError.encoding` if the value cannot be encoded.
  public func broadcast<T: Encodable & Sendable>(
    _ value: T,
    as event: String
  ) async throws(RealtimeError) {
    guard currentState == .joined else { throw .channelNotJoined }
    guard let realtime else { throw .disconnected }

    let payloadData: Data
    do {
      payloadData = try realtime.configuration.encoder.encode(value)
    } catch {
      throw .encoding(underlying: error)
    }

    let payloadDict: [String: JSONValue]
    do {
      payloadDict = try JSONDecoder().decode([String: JSONValue].self, from: payloadData)
    } catch {
      throw .encoding(underlying: error)
    }

    let msg = PhoenixMessage(
      joinRef: nil, ref: nil,
      topic: topic, event: "broadcast",
      payload: [
        "type": "broadcast",
        "event": .string(event),
        "payload": .object(payloadDict),
      ]
    )
    try await realtime.send(msg)
  }

  /// Broadcasts raw binary data on this channel using the Realtime binary frame format.
  ///
  /// - Parameters:
  ///   - data: The raw binary payload.
  ///   - event: The event name carried by the broadcast.
  /// - Throws: `RealtimeError.channelNotJoined` if not joined, or a transport error.
  public func broadcast(_ data: Data, as event: String) async throws(RealtimeError) {
    guard currentState == .joined else { throw .channelNotJoined }
    guard let realtime else { throw .disconnected }

    let frame: Data
    do {
      frame = try PhoenixSerializer.encodeBroadcastPush(
        joinRef: nil, ref: nil,
        topic: topic, event: event,
        binaryPayload: data
      )
    } catch let e as RealtimeError {
      throw e
    } catch {
      throw .encoding(underlying: error)
    }

    try await realtime.sendBinary(frame)
  }
}
