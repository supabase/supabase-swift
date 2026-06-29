//
//  Channel+Broadcast.swift
//  RealtimeV3
//
//  Created by Guilherme Souza on 29/06/26.
//

import Foundation
import Helpers

// MARK: - Channel + broadcast send

extension Channel {

  /// Sends a broadcast message with an `Encodable` payload.
  ///
  /// ## State gating
  /// - `.unsubscribed` / `.joining` → throws `.notSubscribed`
  /// - `.leaving` / `.closed` → throws `.channelClosed(reason)`
  /// - `.joined` → encodes payload and sends the binary push frame
  ///
  /// ## Ack mode
  /// When `options.broadcast.acknowledge == true`, the call suspends until the server
  /// sends a `phx_reply` for this push, or `configuration.broadcastAckTimeout` elapses
  /// (throws `.broadcastAckTimeout`). When `acknowledge == false` the frame is sent
  /// fire-and-forget.
  ///
  /// ## Wire format
  /// The binary frame is a Phoenix 2.0.0 broadcast push (kind byte `0x03`). The JSON
  /// payload inside the frame is:
  /// ```json
  /// {"type": "broadcast", "event": "<event>", "payload": <encodedT>}
  /// ```
  /// This is symmetric with the receive side (`broadcasts(of:event:)`).
  ///
  /// - Parameters:
  ///   - payload: The message payload. Encoded to JSON before sending.
  ///   - event: The broadcast event name (e.g. `"chat"`).
  /// - Throws: `RealtimeError`
  public func broadcast<T: Encodable & Sendable>(_ payload: T, as event: String)
    async throws(RealtimeError)
  {
    // Guard: ensure the owning Realtime is still alive.
    guard let realtime else { throw .channelClosed(.clientDisconnected) }

    // State gating.
    switch channelState {
    case .joined:
      break
    case .unsubscribed, .joining:
      throw .notSubscribed
    case .leaving:
      throw .channelClosed(.userRequested)
    case .closed(let reason):
      throw .channelClosed(reason)
    }

    // Encode the payload to AnyJSON for embedding in the broadcast envelope.
    // AnyJSON.init(_:) requires Codable, but T is only Encodable, so encode to Data first
    // then decode back to AnyJSON via the standard JSON round-trip.
    let encodedPayload: AnyJSON
    do {
      let data = try JSONEncoder().encode(payload)
      encodedPayload = try JSONDecoder().decode(AnyJSON.self, from: data)
    } catch {
      throw .encoding(underlying: error)
    }

    // Build the inner broadcast envelope.
    let innerPayload: JSONObject = [
      "type": .string("broadcast"),
      "event": .string(event),
      "payload": encodedPayload,
    ]

    // Generate a ref (needed for ack mode; always generated for protocol correctness).
    let ref = realtime.nextRef()
    let currentJoinRef = joinRef

    // Encode the binary broadcast frame.
    let frameData: Data
    do {
      frameData = try realtime.serializer.encodeBroadcastPush(
        joinRef: currentJoinRef,
        ref: ref,
        topic: topic,
        event: PhoenixEvent.broadcast.rawValue,
        jsonPayload: innerPayload
      )
    } catch {
      throw error as? RealtimeError ?? .encoding(underlying: error)
    }

    // Send the binary frame (lazy-connects if needed).
    try await realtime.sendBinary(frameData)

    // Ack mode: await the server reply.
    if options.broadcast.acknowledge {
      _ = try await realtime.awaitReply(
        ref: ref,
        timeout: realtime.configuration.broadcastAckTimeout,
        timeoutError: .broadcastAckTimeout
      )
    }
  }

  /// Sends a broadcast message with a raw binary payload.
  ///
  /// The binary data is shipped as-is inside the Phoenix 2.0.0 broadcast push frame
  /// (kind byte `0x03`, encoding byte `0x00`). Ack semantics are identical to the
  /// `Encodable` overload.
  ///
  /// - Parameters:
  ///   - data: The raw binary payload.
  ///   - event: The broadcast event name.
  /// - Throws: `RealtimeError`
  public func broadcast(_ data: Data, as event: String) async throws(RealtimeError) {
    // Guard: ensure the owning Realtime is still alive.
    guard let realtime else { throw .channelClosed(.clientDisconnected) }

    // State gating.
    switch channelState {
    case .joined:
      break
    case .unsubscribed, .joining:
      throw .notSubscribed
    case .leaving:
      throw .channelClosed(.userRequested)
    case .closed(let reason):
      throw .channelClosed(reason)
    }

    let ref = realtime.nextRef()
    let currentJoinRef = joinRef

    let frameData: Data
    do {
      frameData = try realtime.serializer.encodeBroadcastPush(
        joinRef: currentJoinRef,
        ref: ref,
        topic: topic,
        event: PhoenixEvent.broadcast.rawValue,
        binaryPayload: data
      )
    } catch {
      throw error as? RealtimeError ?? .encoding(underlying: error)
    }

    try await realtime.sendBinary(frameData)

    if options.broadcast.acknowledge {
      _ = try await realtime.awaitReply(
        ref: ref,
        timeout: realtime.configuration.broadcastAckTimeout,
        timeoutError: .broadcastAckTimeout
      )
    }
  }
}

// MARK: - Channel + broadcasts(of:event:)

extension Channel {
  /// Returns an `AsyncThrowingStream` that yields every broadcast message for the
  /// given `event` name, decoded to `T`.
  ///
  /// ## Wire shape
  /// A broadcast Phoenix frame has `event == "broadcast"` and a JSON payload of the form:
  /// ```json
  /// { "type": "broadcast", "event": "<name>", "payload": { ... } }
  /// ```
  /// This method filters frames whose inner `event` matches the requested name and
  /// decodes the inner `payload` object to `T` using `Configuration.decoder`.
  ///
  /// ## Per-call fan-out (Decision 8)
  /// Each call mints an independent stream. N concurrent calls each receive a copy
  /// of every matching message. Streams created before `subscribe()` are valid —
  /// they start producing once frames arrive after the join.
  ///
  /// ## Decode failure
  /// If the inner `payload` cannot be decoded to `T`, the stream terminates by
  /// throwing `RealtimeError.decoding(type:underlying:)`. Non-matching events are
  /// silently ignored.
  ///
  /// ## Terminal close
  /// When the channel transitions to `.closed(reason)` (e.g. via `leave()`), the
  /// stream terminates by throwing `RealtimeError.channelClosed(reason)`.
  ///
  /// - Note: The thrown error is always a `RealtimeError`. Cast with `as? RealtimeError`
  ///   or use `if case` matching on the caught `any Error`.
  public func broadcasts<T: Decodable & Sendable>(
    of type: T.Type,
    event: String
  ) -> AsyncThrowingStream<T, any Error> {
    let id = UUID()

    // Capture the decoder from realtime configuration, falling back to the default if
    // realtime has already been deallocated (e.g. stream registered after client teardown).
    let decoder = realtime?.configuration.decoder ?? .realtimeDefault

    // AsyncThrowingStream with a typed non-Error Failure requires iOS 17+.
    // On iOS 16 / Swift 6.1 we use the standard `Failure == any Error` form.
    let (stream, continuation) = AsyncThrowingStream<T, any Error>.makeStream()

    // Type-erased message handler registered in the actor's fan-out registry.
    let handler: @Sendable (PhoenixMessage) -> Void = { [weak self] message in
      // Only handle broadcast Phoenix events.
      guard message.event == .broadcast else { return }

      // Extract the JSON object from the payload.
      guard case .json(let jsonValue) = message.payload,
        let obj = jsonValue.objectValue
      else { return }

      // Match the inner "event" field against the requested event name.
      guard let innerEvent = obj["event"]?.stringValue, innerEvent == event else { return }

      // Extract the inner "payload" value.
      guard let innerPayload = obj["payload"] else {
        // No payload key — decode failure terminates the stream.
        continuation.finish(
          throwing: RealtimeError.decoding(
            type: String(describing: T.self),
            underlying: MissingPayloadError()
          ))
        Task { [weak self] in await self?.removeBroadcastConsumer(id: id) }
        return
      }

      // Re-encode the JSONValue to Data, then decode T using the configured decoder.
      do {
        let data = try JSONEncoder().encode(innerPayload)
        let decoded = try decoder.decode(T.self, from: data)
        continuation.yield(decoded)
      } catch {
        // Decode failure terminates this stream (spec: decode failure throws).
        continuation.finish(
          throwing: RealtimeError.decoding(
            type: String(describing: T.self),
            underlying: error
          ))
        Task { [weak self] in await self?.removeBroadcastConsumer(id: id) }
      }
    }

    // Channel-close finisher: throws .channelClosed into the stream.
    let finisher: @Sendable (CloseReason) -> Void = { reason in
      continuation.finish(throwing: RealtimeError.channelClosed(reason))
    }

    // Register both in the actor's fan-out tables.
    broadcastConsumers[id] = handler
    broadcastFinishers[id] = finisher

    // On stream termination (cancellation or normal finish), deregister from the actor.
    continuation.onTermination = { [weak self] _ in
      Task { [weak self] in await self?.removeBroadcastConsumer(id: id) }
    }

    return stream
  }
}

// MARK: - MissingPayloadError

/// Sentinel error used when a broadcast frame has no inner `payload` key.
private struct MissingPayloadError: Error, Sendable {
  var localizedDescription: String { "Broadcast frame is missing the inner 'payload' key." }
}
